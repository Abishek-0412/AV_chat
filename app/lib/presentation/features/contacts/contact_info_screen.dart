import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_radii.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ContactInfoScreen extends ConsumerWidget {
  const ContactInfoScreen({required this.id, super.key});
  final AvId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref
        .watch(contactsProvider)
        .value
        ?.where((c) => c.id == id)
        .firstOrNull;
    final me = ref.watch(identityProvider).value;
    final online = ref.watch(onlineProvider).value?.contains(id) ?? false;
    final session = ref.watch(sessionProvider).value;
    final theme = Theme.of(context);

    if (contact == null || me == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Contact not found')),
      );
    }
    final code = contact.publicKey == null
        ? null
        : safetyCode(me.publicKey, contact.publicKey!);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => _rename(context, ref, contact.name),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Center(
            child: Hero(
              tag: 'avatar-${DirectRef(id).key}',
              child: AvAvatar(
                seed: DirectRef(id).key,
                name: contact.name,
                radius: 48,
                online: contact.isPending ? null : online,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            contact.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            id.value,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!contact.isPending)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.push(AppRoutes.chat(DirectRef(id))),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message'),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.tonalIcon(
                  onPressed: online && session != null
                      ? () => unawaited(session.calls.start(DirectRef(id)))
                      : null,
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call'),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.xl),
          if (code != null)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.md),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          contact.verified
                              ? Icons.verified
                              : Icons.shield_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Safety code', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        height: 1.6,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Compare this with ${contact.name}, in person or on '
                      'a call. If it matches on both phones, nobody is '
                      'listening in.',
                      style: theme.textTheme.bodySmall,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Marked as verified'),
                      value: contact.verified,
                      onChanged: (v) =>
                          session?.contacts.setVerified(id, verified: v),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          ListTile(
            leading: Icon(
              Icons.person_remove_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Remove contact',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _remove(context, ref, contact.name),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Rename contact'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) {
      await ref.read(sessionProvider).value?.contacts.rename(id, name);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'They will need to send you a new request to chat again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider).value;
    session?.chats.clear(DirectRef(id));
    await session?.contacts.remove(id);
    if (context.mounted) context.go(AppRoutes.contacts);
  }
}
