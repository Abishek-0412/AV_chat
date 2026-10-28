import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_chat/presentation/shared/widgets/empty_state.dart';
import 'package:av_chat/presentation/shared/widgets/my_code_card.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider).value ?? const [];
    final requests = ref.watch(contactRequestsProvider).value ?? const [];
    final groups = ref.watch(groupsProvider).value ?? const [];
    final online = ref.watch(onlineProvider).value ?? const {};
    final empty = contacts.isEmpty && requests.isEmpty && groups.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            onPressed: () => _showMyCode(context, ref),
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'My code',
          ),
          IconButton(
            onPressed: contacts.any((c) => !c.isPending)
                ? () => context.push(AppRoutes.newGroup)
                : null,
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'New group',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addContact),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add contact'),
      ),
      body: empty
          ? const EmptyState(
              illustration: 'assets/illustrations/empty_contacts.svg',
              title: 'No contacts yet',
              message:
                  'Add someone by scanning their QR code '
                  'or entering their AV-ID.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (requests.isNotEmpty) ...[
                  const _Section('Requests'),
                  for (final r in requests) _RequestTile(r),
                ],
                if (groups.isNotEmpty) ...[
                  const _Section('Groups'),
                  for (final g in groups)
                    ListTile(
                      leading: AvAvatar(
                        seed: GroupRef(g.id).key,
                        name: g.name,
                        icon: Icons.groups_2_outlined,
                      ),
                      title: Text(g.name),
                      subtitle: Text(
                        '${g.members.length} members · '
                        '${_countOnline(g.members.map((m) => m.id), online)}'
                        ' online',
                      ),
                      onTap: () => context.push(AppRoutes.chat(GroupRef(g.id))),
                    ),
                ],
                if (contacts.isNotEmpty) ...[
                  _Section(
                    'Contacts · '
                    '${contacts.where((c) => online.contains(c.id)).length}'
                    ' online',
                  ),
                  for (final (i, c) in contacts.indexed)
                    _ContactTile(contact: c, online: online.contains(c.id))
                        .animate(delay: AppMotion.stagger * i.clamp(0, 8))
                        .fadeIn(duration: AppMotion.medium),
                ],
              ],
            ),
    );
  }

  static int _countOnline(Iterable<AvId> ids, Set<AvId> online) =>
      ids.where(online.contains).length;

  void _showMyCode(BuildContext context, WidgetRef ref) {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Let a friend scan this',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                MyCodeCard(identity: identity),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.online});
  final Contact contact;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: AvAvatar(
        seed: DirectRef(contact.id).key,
        name: contact.name,
        online: contact.isPending ? null : online,
      ),
      title: Row(
        children: [
          Flexible(child: Text(contact.name, overflow: TextOverflow.ellipsis)),
          if (contact.verified) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.verified, size: 16, color: scheme.primary),
          ],
        ],
      ),
      subtitle: Text(
        contact.isPending
            ? 'Request sent · waiting'
            : online
            ? 'Online'
            : 'Offline',
      ),
      trailing: contact.isPending
          ? null
          : IconButton(
              onPressed: () =>
                  context.push(AppRoutes.chat(DirectRef(contact.id))),
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Message',
            ),
      onTap: () => context.push(AppRoutes.contact(contact.id)),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile(this.request);
  final ContactRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      color: scheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            AvAvatar(seed: DirectRef(request.id).key, name: request.name),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    request.id.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => session?.contacts.decline(request.id),
              icon: const Icon(Icons.close),
              tooltip: 'Decline',
            ),
            IconButton.filled(
              onPressed: () => session?.contacts.accept(request),
              icon: const Icon(Icons.check),
              tooltip: 'Accept',
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }
}
