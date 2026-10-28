import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/services/chat_service.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/format.dart';
import 'package:av_chat/presentation/shared/names.dart';
import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_chat/presentation/shared/widgets/empty_state.dart';
import 'package:av_chat/presentation/shared/widgets/status_ticks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Conversations of this session, newest first. Empty on every launch.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations =
        (ref.watch(conversationsProvider).value ?? const {}).values
            .where((c) => c.messages.isNotEmpty)
            .toList()
          ..sort((a, b) => b.last!.sentAt.compareTo(a.last!.sentAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startChat(context, ref),
        tooltip: 'New chat',
        child: const Icon(Icons.edit_outlined),
      ),
      body: conversations.isEmpty
          ? const EmptyState(
              illustration: 'assets/illustrations/empty_chats.svg',
              title: 'No conversations yet',
              message: 'Messages disappear when you close the app.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: conversations.length,
              itemBuilder: (context, i) => _ConversationTile(conversations[i])
                  .animate(delay: AppMotion.stagger * i.clamp(0, 8))
                  .fadeIn(duration: AppMotion.medium)
                  .slideX(begin: 0.05),
            ),
    );
  }

  Future<void> _startChat(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<ConversationRef>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _NewChatSheet(),
    );
    if (picked != null && context.mounted) {
      await context.push(AppRoutes.chat(picked));
    }
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile(this.conversation);
  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ref0 = conversation.ref;
    final last = conversation.last!;
    final online = ref.watch(onlineProvider).value ?? const {};
    final typing = conversation.typing.isNotEmpty;
    final preview = typing ? 'typing…' : _preview(ref, last);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: Hero(
        tag: 'avatar-${ref0.key}',
        child: AvAvatar(
          seed: ref0.key,
          name: titleOf(ref, ref0),
          icon: ref0 is GroupRef ? Icons.groups_2_outlined : null,
          online: ref0 is DirectRef ? online.contains(ref0.peer) : null,
        ),
      ),
      title: Text(
        titleOf(ref, ref0),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Row(
        children: [
          if (last.outgoing && !typing) ...[
            StatusTicks(last.status),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typing
                  ? TextStyle(
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    )
                  : null,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Format.time(last.sentAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: conversation.unread > 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedScale(
            scale: conversation.unread > 0 ? 1 : 0,
            duration: AppMotion.fast,
            child: Badge(label: Text('${conversation.unread}')),
          ),
        ],
      ),
      onTap: () => context.push(AppRoutes.chat(ref0)),
    );
  }

  String _preview(WidgetRef ref, Message m) {
    final who = conversation.ref is GroupRef && !m.outgoing
        ? '${nameOf(ref, m.sender)}: '
        : '';
    if (m.deleted) return 'Message deleted';
    return who +
        switch (m.content) {
          TextContent(:final text) => text,
          ImageContent() => '📷 Photo',
          VoiceContent(:final duration) =>
            '🎤 Voice note (${Format.duration(duration)})',
        };
  }
}

class _NewChatSheet extends ConsumerWidget {
  const _NewChatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = (ref.watch(contactsProvider).value ?? const [])
        .where((c) => !c.isPending)
        .toList();
    final groups = ref.watch(groupsProvider).value ?? const [];
    final online = ref.watch(onlineProvider).value ?? const {};
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Start a chat',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (contacts.isEmpty && groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  const Text('Add a contact first.'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(context.push(AppRoutes.addContact));
                    },
                    child: const Text('Add contact'),
                  ),
                ],
              ),
            ),
          for (final g in groups)
            ListTile(
              leading: AvAvatar(
                seed: GroupRef(g.id).key,
                name: g.name,
                icon: Icons.groups_2_outlined,
              ),
              title: Text(g.name),
              subtitle: Text('${g.members.length} members'),
              onTap: () => Navigator.pop(context, GroupRef(g.id)),
            ),
          for (final c in contacts)
            ListTile(
              leading: AvAvatar(
                seed: DirectRef(c.id).key,
                name: c.name,
                online: online.contains(c.id),
              ),
              title: Text(c.name),
              subtitle: Text(online.contains(c.id) ? 'Online' : 'Offline'),
              onTap: () => Navigator.pop(context, DirectRef(c.id)),
            ),
        ],
      ),
    );
  }
}
