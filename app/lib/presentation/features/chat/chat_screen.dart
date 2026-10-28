import 'dart:async';

import 'package:av_chat/di/app_session.dart';
import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/services/chat_service.dart';
import 'package:av_chat/presentation/features/chat/composer.dart';
import 'package:av_chat/presentation/features/chat/message_bubble.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/names.dart';
import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.conversation, super.key});
  final ConversationRef conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  /// Messages already shown, so only new ones animate in.
  final _seen = <String>{};
  var _firstBuild = true;
  Message? _replyTo;
  AppSession? _session;

  ConversationRef get _ref => widget.conversation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session = ref.read(sessionProvider).value;
      _session?.chats.setOpen(_ref);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.chats.setOpen(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Read receipts only while the chat is really on screen.
    _session?.chats.setOpen(state == AppLifecycleState.resumed ? _ref : null);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final convo =
        ref.watch(conversationsProvider).value?[_ref.key] ??
        Conversation(ref: _ref);
    final online = ref.watch(onlineProvider).value ?? const {};
    final group = switch (_ref) {
      GroupRef(:final groupId) =>
        ref
            .watch(groupsProvider)
            .value
            ?.where((g) => g.id == groupId)
            .firstOrNull,
      DirectRef() => null,
    };
    final contact = switch (_ref) {
      DirectRef(:final peer) =>
        ref
            .watch(contactsProvider)
            .value
            ?.where((c) => c.id == peer)
            .firstOrNull,
      GroupRef() => null,
    };
    final self = ref.watch(identityProvider).value?.id;
    final othersOnline = switch (_ref) {
      DirectRef(:final peer) => online.contains(peer) ? 1 : 0,
      GroupRef() =>
        group?.members
                .where((m) => m.id != self && online.contains(m.id))
                .length ??
            0,
    };

    final title = titleOf(ref, _ref);
    final subtitle = _subtitle(convo, othersOnline, group?.members.length);
    final (canSend, hint) = _sendState(
      title: title,
      othersOnline: othersOnline,
      pending: contact?.isPending ?? false,
      groupGone: _ref is GroupRef && group == null,
    );

    final messages = convo.messages.reversed.toList();
    if (_firstBuild) {
      _seen.addAll(convo.messages.map((m) => m.id));
      _firstBuild = false;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openInfo,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Hero(
                  tag: 'avatar-${_ref.key}',
                  child: AvAvatar(
                    seed: _ref.key,
                    name: title,
                    radius: 20,
                    icon: _ref is GroupRef ? Icons.groups_2_outlined : null,
                    online: _ref is DirectRef ? othersOnline > 0 : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      AnimatedSwitcher(
                        duration: AppMotion.fast,
                        child: Text(
                          subtitle,
                          key: ValueKey(subtitle),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: convo.typing.isNotEmpty
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: canSend && session != null
                ? () => unawaited(session.calls.start(_ref))
                : null,
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const _EphemeralNote()
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, i) {
                      if (i == messages.length) return const _EphemeralNote();
                      final m = messages[i];
                      final older = i + 1 < messages.length
                          ? messages[i + 1]
                          : null;
                      final bubble = _bubble(m, older, convo);
                      if (_seen.add(m.id)) {
                        return bubble
                            .animate()
                            .fadeIn(duration: AppMotion.medium)
                            .slideY(begin: 0.3, curve: AppMotion.curve)
                            .scaleXY(
                              begin: 0.96,
                              alignment: m.outgoing
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft,
                            );
                      }
                      return bubble;
                    },
                  ),
          ),
          if (session != null)
            Composer(
              media: ref.read(mediaCaptureProvider),
              enabled: canSend,
              disabledHint: hint,
              replyTo: _replyTo,
              replyToName: _replyTo == null
                  ? null
                  : nameOf(ref, _replyTo!.sender),
              onCancelReply: () => setState(() => _replyTo = null),
              onTyping: () => session.chats.sendTyping(_ref),
              onSend: (text) {
                session.chats.sendText(_ref, text, replyToId: _replyTo?.id);
                setState(() => _replyTo = null);
              },
              onContent: (content) => session.chats.sendContent(_ref, content),
            ),
        ],
      ),
    );
  }

  Widget _bubble(Message m, Message? older, Conversation convo) {
    final replyTo = m.replyToId == null
        ? null
        : convo.messages.where((x) => x.id == m.replyToId).firstOrNull;
    return MessageBubble(
      key: ValueKey(m.id),
      message: m,
      joinsPrevious:
          older != null &&
          older.sender == m.sender &&
          m.sentAt.difference(older.sentAt) < const Duration(minutes: 2),
      senderName: _ref is GroupRef && !m.outgoing
          ? nameOf(ref, m.sender)
          : null,
      replyTo: replyTo,
      replyToName: replyTo == null ? null : nameOf(ref, replyTo.sender),
      onLongPress: () => _actions(m),
    );
  }

  String _subtitle(Conversation c, int othersOnline, int? groupSize) {
    if (c.typing.isNotEmpty) {
      if (_ref is DirectRef) return 'typing…';
      final names = c.typing.map((id) => nameOf(ref, id)).join(', ');
      return '$names typing…';
    }
    return switch (_ref) {
      DirectRef() => othersOnline > 0 ? 'Online' : 'Offline',
      GroupRef() => '${groupSize ?? 0} members · $othersOnline online',
    };
  }

  (bool, String?) _sendState({
    required String title,
    required int othersOnline,
    required bool pending,
    required bool groupGone,
  }) {
    if (groupGone) return (false, 'You are no longer in this group.');
    if (pending) {
      return (false, 'Waiting for $title to accept your request.');
    }
    if (othersOnline == 0) {
      return (
        false,
        _ref is DirectRef
            ? '$title is offline. You can chat when you both have the app open.'
            : 'Nobody else in this group is online right now.',
      );
    }
    return (true, null);
  }

  void _openInfo() {
    switch (_ref) {
      case DirectRef(:final peer):
        unawaited(context.push(AppRoutes.contact(peer)));
      case GroupRef(:final groupId):
        unawaited(context.push(AppRoutes.group(groupId)));
    }
  }

  Future<void> _actions(Message m) async {
    unawaited(HapticFeedback.mediumImpact());
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final self = ref.read(identityProvider).value?.id;
    final mine = self == null ? null : m.reactions[self];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final (i, e) in emojis.indexed)
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: e == mine
                            ? Theme.of(sheet).colorScheme.primaryContainer
                            : null,
                      ),
                      onPressed: () {
                        session.chats.react(_ref, m.id, e == mine ? '' : e);
                        Navigator.pop(sheet);
                      },
                      icon: Text(e, style: const TextStyle(fontSize: 26)),
                    ).animate(delay: (30 * i).ms).scale(duration: 200.ms),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => _replyTo = m);
              },
            ),
            if (m.outgoing)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheet).colorScheme.error,
                ),
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(color: Theme.of(sheet).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  session.chats.deleteForEveryone(_ref, m.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EphemeralNote extends StatelessWidget {
  const _EphemeralNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'End-to-end encrypted. '
                'Messages disappear when you close the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
