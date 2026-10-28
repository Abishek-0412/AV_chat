import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/presentation/features/groups/new_group_screen.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({required this.groupId, super.key});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref
        .watch(groupsProvider)
        .value
        ?.where((g) => g.id == groupId)
        .firstOrNull;
    final me = ref.watch(identityProvider).value;
    final online = ref.watch(onlineProvider).value ?? const {};
    final session = ref.watch(sessionProvider).value;
    final theme = Theme.of(context);
    if (group == null || me == null || session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Group not found')),
      );
    }
    final isOwner = group.owner == me.id;
    final ref0 = GroupRef(group.id);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (isOwner)
            IconButton(
              onPressed: () => _rename(context, session.groups.rename, group),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename group',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          Center(
            child: Hero(
              tag: 'avatar-${ref0.key}',
              child: AvAvatar(
                seed: ref0.key,
                name: group.name,
                radius: 48,
                icon: Icons.groups_2_outlined,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            group.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          Text(
            '${group.members.length} of ${Group.maxMembers} members',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => unawaited(session.calls.start(ref0)),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Group call'),
              ),
              if (isOwner && group.members.length < Group.maxMembers) ...[
                const SizedBox(width: AppSpacing.md),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final added = await pickMembers(
                      context,
                      ref,
                      exclude: group.members.map((m) => m.id).toSet(),
                      max: Group.maxMembers - group.members.length,
                    );
                    if (added != null) {
                      await session.groups.addMembers(group.id, added);
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final m in group.members)
            ListTile(
              leading: AvAvatar(
                seed: DirectRef(m.id).key,
                name: m.name,
                online: m.id == me.id ? null : online.contains(m.id),
              ),
              title: Text(m.id == me.id ? '${m.name} (you)' : m.name),
              subtitle: Text(
                m.id == group.owner
                    ? 'Owner'
                    : online.contains(m.id)
                    ? 'Online'
                    : 'Offline',
              ),
              trailing: isOwner && m.id != me.id
                  ? IconButton(
                      onPressed: () =>
                          session.groups.removeMember(group.id, m.id),
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove ${m.name}',
                    )
                  : null,
            ),
          const Divider(height: AppSpacing.xxl),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Leave group',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Leave ${group.name}?'),
                  content: Text(
                    isOwner
                        ? 'Ownership passes to the next member.'
                        : 'You can only rejoin if the owner adds you again.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Leave'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await session.groups.leave(group.id);
              if (context.mounted) context.go(AppRoutes.chats);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    Future<void> Function(String, String) rename,
    Group group,
  ) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) await rename(group.id, name);
  }
}
