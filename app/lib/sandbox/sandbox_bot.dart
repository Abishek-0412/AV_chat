import 'dart:async';

import 'package:av_chat/data/messaging/secure_messenger.dart';
import 'package:av_chat/data/messaging/session_crypto.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_identity_repository.dart';
import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:uuid/uuid.dart';

/// A pretend contact for the sandbox build. Runs the real encrypted
/// messenger, accepts requests, and answers like a person would:
/// delivered → read → typing… → reply.
final class SandboxBot {
  SandboxBot._(this.identity, this._messenger, this._reply);

  final Identity identity;
  final SecureMessenger _messenger;
  final String Function(String text) _reply;
  final _trusted = <AvId, Peer>{};
  final _groups = <String, Group>{};
  static const _uuid = Uuid();

  ContactCard get card => ContactCard(
    id: identity.id,
    name: identity.name,
    publicKey: identity.publicKey,
  );

  Peer get asPeer => Peer(
    id: identity.id,
    name: identity.name,
    publicKey: identity.publicKey,
  );

  static Future<SandboxBot> start(
    InMemoryRelayNetwork net, {
    required String name,
    required String Function(String text) reply,
    bool online = true,
  }) async {
    final repo = SecureIdentityRepository(MemoryKeyValueStore());
    final identity = await repo.create(name);
    final relay = net.client(identity.id.value);
    final messenger = SecureMessenger(
      relay: relay,
      self: identity,
      sign: repo.sign,
      crypto: await SessionCrypto.create(),
      newId: _uuid.v4,
    );
    final bot = SandboxBot._(identity, messenger, reply);
    messenger
      ..setPeerLookup((id) => bot._trusted[id])
      ..start();
    messenger.requests.listen((r) {
      bot._trusted[r.id] = Peer(id: r.id, name: r.name, publicKey: r.publicKey);
      messenger.accept(r.id);
    });
    messenger.incoming.listen(bot._onIncoming);
    if (online) await relay.connect('sandbox');
    return bot;
  }

  /// Lets bots in the same demo group talk to each other.
  void trust(SandboxBot other) => _trusted[other.identity.id] = other.asPeer;

  Future<void> _onIncoming(Incoming event) async {
    final from = event.from;
    switch (event.payload) {
      case GroupUpdatePayload(:final group):
        _groups[group.id] = group;
        for (final m in group.members) {
          if (m.id != identity.id) _trusted[m.id] = m;
        }
      case ChatPayload(:final messageId, :final content, :final groupId):
        // Bots only answer people, not each other.
        if (_isBot(from)) return;
        _messenger.send(
          from,
          ReceiptPayload(
            kind: ReceiptKind.delivered,
            messageIds: [messageId],
            groupId: groupId,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        _messenger.send(
          from,
          ReceiptPayload(
            kind: ReceiptKind.read,
            messageIds: [messageId],
            groupId: groupId,
          ),
        );
        if (content is TextContent && content.text.contains('?')) {
          _messenger.send(
            from,
            ReactionPayload(
              messageId: messageId,
              emoji: '🤔',
              groupId: groupId,
            ),
          );
        }
        final text = switch (content) {
          TextContent(:final text) => _reply(text),
          ImageContent() => 'Nice photo! 📷',
          VoiceContent() => 'Got your voice note 🎧',
        };
        for (final to in _audience(from, groupId)) {
          _messenger.send(to, TypingPayload(groupId: groupId));
        }
        await Future<void>.delayed(
          Duration(milliseconds: 900 + text.length * 25),
        );
        for (final to in _audience(from, groupId)) {
          _messenger.send(
            to,
            ChatPayload(
              messageId: _uuid.v4(),
              content: TextContent(text),
              sentAt: DateTime.now(),
              groupId: groupId,
            ),
          );
        }
      case CallPayload(:final callId, :final action, :final groupId)
          when action == CallAction.invite:
        _messenger.send(
          from,
          CallPayload(
            callId: callId,
            action: CallAction.ringing,
            groupId: groupId,
          ),
        );
        if (groupId != null) return;
        await Future<void>.delayed(const Duration(seconds: 3));
        _messenger.send(
          from,
          CallPayload(
            callId: callId,
            action: CallAction.decline,
            groupId: groupId,
          ),
        );
      default:
        return;
    }
  }

  bool _isBot(AvId id) => _botIds.contains(id);
  static final _botIds = <AvId>{};

  List<AvId> _audience(AvId from, String? groupId) {
    if (groupId == null) return [from];
    final group = _groups[groupId];
    if (group == null) return [];
    return [
      for (final m in group.members)
        if (m.id != identity.id) m.id,
    ];
  }

  /// Marks these identities as bots so they ignore each other's chatter.
  static void register(Iterable<SandboxBot> bots) =>
      _botIds.addAll(bots.map((b) => b.identity.id));
}
