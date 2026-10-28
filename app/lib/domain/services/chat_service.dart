import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/domain/services/group_service.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/domain/value_objects/message_status.dart';
import 'package:av_protocol/av_protocol.dart';

/// One chat as the UI sees it.
final class Conversation {
  const Conversation({
    required this.ref,
    this.messages = const [],
    this.unread = 0,
    this.typing = const {},
  });

  final ConversationRef ref;

  /// Oldest first.
  final List<Message> messages;
  final int unread;
  final Set<AvId> typing;

  Message? get last => messages.isEmpty ? null : messages.last;

  Conversation copyWith({
    List<Message>? messages,
    int? unread,
    Set<AvId>? typing,
  }) => Conversation(
    ref: ref,
    messages: messages ?? this.messages,
    unread: unread ?? this.unread,
    typing: typing ?? this.typing,
  );
}

/// All chats, in memory only. Nothing here is ever written to disk:
/// closing the app ends the process and the messages with it.
final class ChatService {
  ChatService({
    required Messenger messenger,
    required GroupService groups,
    required AvId self,
    required String Function() newId,
    DateTime Function()? clock,
  }) : _messenger = messenger,
       _groups = groups,
       _self = self,
       _newId = newId,
       _clock = clock ?? DateTime.now;

  static const typingTimeout = Duration(seconds: 5);
  static const _typingThrottle = Duration(seconds: 3);

  final Messenger _messenger;
  final GroupService _groups;
  final AvId _self;
  final String Function() _newId;
  final DateTime Function() _clock;

  final conversations = Store<Map<String, Conversation>>(const {});

  /// Incoming chat messages, for notifications.
  final _arrivals = StreamController<Message>.broadcast();
  Stream<Message> get arrivals => _arrivals.stream;

  /// Per outgoing message: status of each recipient.
  final _recipients = <String, Map<AvId, MessageStatus>>{};
  final _typingTimers = <String, Timer>{};
  final _lastTypingSent = <String, DateTime>{};
  final _subs = <StreamSubscription<Object?>>[];

  /// Chat currently on screen; its messages are read on arrival.
  ConversationRef? _open;

  void init() {
    _subs
      ..add(_messenger.incoming.listen(_onIncoming))
      ..add(_messenger.failures.listen(_onFailure))
      ..add(_messenger.sessionResets.listen(_resendUnconfirmed))
      ..add(_groups.groups.stream.listen((_) => _dropStaleGroups()));
  }

  Conversation conversation(ConversationRef ref) =>
      conversations.value[ref.key] ?? Conversation(ref: ref);

  /// Call when a chat opens (or with null when it closes / app hides).
  void setOpen(ConversationRef? ref) {
    _open = ref;
    if (ref != null) markRead(ref);
  }

  void sendText(ConversationRef ref, String text, {String? replyToId}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _sendContent(ref, TextContent(trimmed), replyToId: replyToId);
  }

  void sendContent(ConversationRef ref, MessageContent content) =>
      _sendContent(ref, content);

  void sendTyping(ConversationRef ref) {
    final now = _clock();
    final last = _lastTypingSent[ref.key];
    if (last != null && now.difference(last) < _typingThrottle) return;
    _lastTypingSent[ref.key] = now;
    _fanOut(ref, TypingPayload(groupId: _groupId(ref)));
  }

  void markRead(ConversationRef ref) {
    final convo = conversations.value[ref.key];
    if (convo == null) return;
    final unreadBySender = <AvId, List<String>>{};
    final messages = <Message>[];
    for (final m in convo.messages) {
      if (!m.outgoing && m.status == MessageStatus.delivered) {
        (unreadBySender[m.sender] ??= []).add(m.id);
        messages.add(m.copyWith(status: MessageStatus.read));
      } else {
        messages.add(m);
      }
    }
    if (unreadBySender.isEmpty && convo.unread == 0) return;
    for (final entry in unreadBySender.entries) {
      _messenger.send(
        entry.key,
        ReceiptPayload(
          kind: ReceiptKind.read,
          messageIds: entry.value,
          groupId: _groupId(ref),
        ),
      );
    }
    _put(convo.copyWith(messages: messages, unread: 0));
  }

  void react(ConversationRef ref, String messageId, String emoji) {
    _applyReaction(ref, messageId, _self, emoji);
    _fanOut(
      ref,
      ReactionPayload(
        messageId: messageId,
        emoji: emoji,
        groupId: _groupId(ref),
      ),
    );
  }

  /// Removes one of our own messages on every phone in the chat.
  void deleteForEveryone(ConversationRef ref, String messageId) {
    final msg = _find(ref, messageId);
    if (msg == null || !msg.outgoing) return;
    _replace(ref, msg.copyWith(deleted: true));
    _fanOut(
      ref,
      DeletePayload(messageId: messageId, groupId: _groupId(ref)),
    );
  }

  /// Clears a chat on this phone only.
  void clear(ConversationRef ref) {
    final next = {...conversations.value}..remove(ref.key);
    conversations.value = next;
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    await _arrivals.close();
  }

  // ── Sending ────────────────────────────────────────────────────────

  void _sendContent(
    ConversationRef ref,
    MessageContent content, {
    String? replyToId,
  }) {
    final recipients = _recipientsOf(ref);
    final message = Message(
      id: _newId(),
      conversation: ref,
      sender: _self,
      outgoing: true,
      content: content,
      sentAt: _clock(),
      status: recipients.isEmpty ? MessageStatus.failed : MessageStatus.sending,
      replyToId: replyToId,
    );
    _recipients[message.id] = {
      for (final r in recipients) r: MessageStatus.sending,
    };
    _append(ref, message);
    final payload = ChatPayload(
      messageId: message.id,
      content: content,
      sentAt: message.sentAt,
      replyToId: replyToId,
      groupId: _groupId(ref),
    );
    for (final r in recipients) {
      _messenger.send(r, payload);
    }
  }

  void _fanOut(ConversationRef ref, WirePayload payload) {
    for (final r in _recipientsOf(ref)) {
      _messenger.send(r, payload);
    }
  }

  List<AvId> _recipientsOf(ConversationRef ref) => switch (ref) {
    DirectRef(:final peer) => [peer],
    GroupRef(:final groupId) => [
      for (final m in _groups.byId(groupId)?.members ?? const <Peer>[])
        if (m.id != _self) m.id,
    ],
  };

  String? _groupId(ConversationRef ref) => ref is GroupRef ? ref.groupId : null;

  // ── Receiving ──────────────────────────────────────────────────────

  void _onIncoming(Incoming event) {
    final payload = event.payload;
    if (payload is! ConversationPayload) return;
    final ref = _refFor(event.from, payload.groupId);
    if (ref == null) return;
    switch (payload) {
      case ChatPayload():
        _onChat(event.from, ref, payload);
      case ReceiptPayload(:final kind, :final messageIds):
        final status = kind == ReceiptKind.read
            ? MessageStatus.read
            : MessageStatus.delivered;
        for (final id in messageIds) {
          _setRecipientStatus(ref, id, event.from, status);
        }
      case TypingPayload():
        _onTyping(ref, event.from);
      case ReactionPayload(:final messageId, :final emoji):
        _applyReaction(ref, messageId, event.from, emoji);
      case DeletePayload(:final messageId):
        final msg = _find(ref, messageId);
        if (msg != null && msg.sender == event.from) {
          _replace(ref, msg.copyWith(deleted: true));
        }
    }
  }

  /// Null if the sender has no business in that conversation.
  ConversationRef? _refFor(AvId from, String? groupId) {
    if (groupId == null) return DirectRef(from);
    final group = _groups.byId(groupId);
    if (group == null || !group.contains(from)) return null;
    return GroupRef(groupId);
  }

  void _onChat(AvId from, ConversationRef ref, ChatPayload p) {
    if (_find(ref, p.messageId) != null) return; // duplicate
    final isOpen = _open == ref;
    final message = Message(
      id: p.messageId,
      conversation: ref,
      sender: from,
      outgoing: false,
      content: p.content,
      sentAt: p.sentAt,
      status: isOpen ? MessageStatus.read : MessageStatus.delivered,
      replyToId: p.replyToId,
    );
    _clearTyping(ref, from);
    _append(ref, message, countUnread: !isOpen);
    _messenger.send(
      from,
      ReceiptPayload(
        kind: isOpen ? ReceiptKind.read : ReceiptKind.delivered,
        messageIds: [p.messageId],
        groupId: p.groupId,
      ),
    );
    _arrivals.add(message);
  }

  void _onTyping(ConversationRef ref, AvId from) {
    final convo = conversation(ref);
    _put(convo.copyWith(typing: {...convo.typing, from}));
    final key = '${ref.key}|${from.value}';
    _typingTimers[key]?.cancel();
    _typingTimers[key] = Timer(typingTimeout, () => _clearTyping(ref, from));
  }

  void _clearTyping(ConversationRef ref, AvId from) {
    _typingTimers.remove('${ref.key}|${from.value}')?.cancel();
    final convo = conversations.value[ref.key];
    if (convo == null || !convo.typing.contains(from)) return;
    _put(convo.copyWith(typing: {...convo.typing}..remove(from)));
  }

  void _onFailure(DeliveryFailure failure) {
    final payload = failure.payload;
    if (payload is! ChatPayload) return;
    final ref = payload.groupId == null
        ? DirectRef(failure.to)
        : GroupRef(payload.groupId!);
    _setRecipientStatus(
      ref,
      payload.messageId,
      failure.to,
      MessageStatus.failed,
    );
  }

  /// A peer restarted: anything they never confirmed was lost with
  /// their old session, so send it again.
  void _resendUnconfirmed(AvId peer) {
    for (final convo in conversations.value.values) {
      for (final m in convo.messages) {
        if (!m.outgoing || m.deleted) continue;
        if (_recipients[m.id]?[peer] != MessageStatus.sending) continue;
        _messenger.send(
          peer,
          ChatPayload(
            messageId: m.id,
            content: m.content,
            sentAt: m.sentAt,
            replyToId: m.replyToId,
            groupId: _groupId(convo.ref),
          ),
        );
      }
    }
  }

  // ── State helpers ──────────────────────────────────────────────────

  void _setRecipientStatus(
    ConversationRef ref,
    String messageId,
    AvId recipient,
    MessageStatus status,
  ) {
    final perRecipient = _recipients[messageId];
    if (perRecipient == null || !perRecipient.containsKey(recipient)) return;
    final current = perRecipient[recipient]!;
    // Never move backwards (a late "delivered" must not undo "read").
    if (current == MessageStatus.read ||
        (current == MessageStatus.delivered && status != MessageStatus.read)) {
      return;
    }
    perRecipient[recipient] = status;
    final msg = _find(ref, messageId);
    if (msg != null) {
      _replace(ref, msg.copyWith(status: _aggregate(perRecipient)));
    }
  }

  /// Group message status = the slowest recipient that could be reached.
  static MessageStatus _aggregate(Map<AvId, MessageStatus> statuses) {
    final reachable = statuses.values.where((s) => s != MessageStatus.failed);
    if (reachable.isEmpty) return MessageStatus.failed;
    return reachable.reduce((a, b) => a.index < b.index ? a : b);
  }

  void _applyReaction(
    ConversationRef ref,
    String messageId,
    AvId who,
    String emoji,
  ) {
    final msg = _find(ref, messageId);
    if (msg == null || msg.deleted) return;
    final reactions = {...msg.reactions};
    if (emoji.isEmpty) {
      reactions.remove(who);
    } else {
      reactions[who] = emoji;
    }
    _replace(ref, msg.copyWith(reactions: reactions));
  }

  Message? _find(ConversationRef ref, String id) {
    for (final m
        in conversations.value[ref.key]?.messages ?? const <Message>[]) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _append(ConversationRef ref, Message m, {bool countUnread = false}) {
    final convo = conversation(ref);
    _put(
      convo.copyWith(
        messages: [...convo.messages, m],
        unread: convo.unread + (countUnread ? 1 : 0),
      ),
    );
  }

  void _replace(ConversationRef ref, Message updated) {
    final convo = conversation(ref);
    _put(
      convo.copyWith(
        messages: [
          for (final m in convo.messages) m.id == updated.id ? updated : m,
        ],
      ),
    );
  }

  void _put(Conversation convo) {
    conversations.value = {...conversations.value, convo.ref.key: convo};
  }

  void _dropStaleGroups() {
    final stale = conversations.value.keys.where((key) {
      final ref = ConversationRef.parse(key);
      return ref is GroupRef && _groups.byId(ref.groupId) == null;
    }).toList();
    if (stale.isEmpty) return;
    conversations.value = {...conversations.value}
      ..removeWhere((k, _) => stale.contains(k));
  }
}
