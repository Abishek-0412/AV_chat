import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Slim strip that appears only while the relay is unreachable.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionStatusProvider).value ?? ConnectionStatus.offline;
    final scheme = Theme.of(context).colorScheme;
    final visible = status != ConnectionStatus.online;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: scheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Connecting to server…',
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
