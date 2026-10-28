import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_chat/presentation/shared/theme/app_colors.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_chat/presentation/shared/widgets/my_code_card.dart';
import 'package:av_chat/presentation/shared/widgets/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider).value;
    final url = ref.watch(relayUrlProvider).value ?? '';
    final status =
        ref.watch(connectionStatusProvider).value ?? ConnectionStatus.offline;
    final theme = Theme.of(context);
    if (identity == null) return const Scaffold();

    final (statusText, statusColor) = switch (status) {
      ConnectionStatus.online => ('Connected', AppColors.online),
      ConnectionStatus.connecting => (
        'Connecting…',
        theme.colorScheme.tertiary,
      ),
      ConnectionStatus.offline => ('Offline', AppColors.offline),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          ListTile(
            leading: AvAvatar(
              seed: DirectRef(identity.id).key,
              name: identity.name,
              radius: 28,
            ),
            title: Text(identity.name, style: theme.textTheme.titleLarge),
            subtitle: Text(
              identity.id.value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editName(context, ref, identity.name),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('My code'),
            onTap: () => showModalBottomSheet<void>(
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
                  child: MyCodeCard(identity: identity),
                ),
              ),
            ),
          ),
          const _Header('Connection'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(url),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: statusColor),
                const SizedBox(width: AppSpacing.xs),
                Text(statusText),
              ],
            ),
            onTap: () => _editServer(context, ref, url),
          ),
          const _Header('Security'),
          const _BiometricsTile(),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Change PIN'),
            onTap: () => _changePin(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.timer_outlined),
            title: Text('Auto-lock'),
            subtitle: Text('After 30 seconds in the background'),
          ),
          const ListTile(
            leading: Icon(Icons.screenshot_monitor_outlined),
            title: Text('Screenshots & screen recording'),
            subtitle: Text('Blocked'),
          ),
          const _Header('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('End-to-end encrypted'),
            subtitle: Text(
              'Messages and calls are encrypted on your phone. '
              'The server only passes sealed data along.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.auto_delete_outlined),
            title: Text('Nothing is saved'),
            subtitle: Text(
              'Chats live in memory and vanish when you close the app. '
              'Only your ID, contacts and groups are kept, encrypted.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await _prompt(context, 'Your name', current, maxLength: 40);
    if (name != null) await ref.read(identityProvider.notifier).rename(name);
  }

  Future<void> _editServer(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final url = await _prompt(
      context,
      'Server address',
      current,
      hint: 'ws://192.168.1.5:8080',
      help: 'Leave empty to use the default.',
    );
    if (url != null) await ref.read(relayUrlProvider.notifier).set(url);
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final lock = ref.read(appLockProvider);
    final ok = await _askPin(context, 'Current PIN', verify: lock.verifyPin);
    if (ok == null || !context.mounted) return;
    final first = await _askPin(context, 'New PIN');
    if (first == null || !context.mounted) return;
    final second = await _askPin(context, 'Confirm new PIN');
    if (!context.mounted) return;
    if (second != first) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("PINs don't match")));
      return;
    }
    await lock.setPin(first);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('PIN changed')));
  }

  static Future<String?> _askPin(
    BuildContext context,
    String title, {
    Future<bool> Function(String)? verify,
  }) {
    final pad = GlobalKey<PinPadState>();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xl),
              PinPad(
                key: pad,
                onComplete: (pin) async {
                  if (verify != null && !await verify(pin)) {
                    pad.currentState?.reject();
                    return;
                  }
                  if (sheet.mounted) Navigator.pop(sheet, pin);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<String?> _prompt(
    BuildContext context,
    String title,
    String initial, {
    String? hint,
    String? help,
    int? maxLength,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          autocorrect: false,
          decoration: InputDecoration(hintText: hint, helperText: help),
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
    return result;
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
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

class _BiometricsTile extends ConsumerStatefulWidget {
  const _BiometricsTile();

  @override
  ConsumerState<_BiometricsTile> createState() => _BiometricsTileState();
}

class _BiometricsTileState extends ConsumerState<_BiometricsTile> {
  bool? _available;
  var _enabled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final lock = ref.read(appLockProvider);
    final available = await lock.biometricsAvailable();
    final enabled = await lock.biometricsEnabled();
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Unlock with fingerprint'),
      subtitle: _available == false
          ? const Text('No fingerprint set up on this phone')
          : null,
      value: _enabled && (_available ?? false),
      onChanged: _available ?? false
          ? (v) async {
              if (v &&
                  !await ref
                      .read(appLockProvider)
                      .authenticateWithBiometrics()) {
                return;
              }
              await ref.read(appLockProvider).setBiometricsEnabled(enabled: v);
              setState(() => _enabled = v);
            }
          : null,
    );
  }
}
