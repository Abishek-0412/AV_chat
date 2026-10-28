import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/presentation/shared/theme/app_radii.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Your QR code and AV-ID. The AV-ID is public, so copying it is allowed.
class MyCodeCard extends StatelessWidget {
  const MyCodeCard({required this.identity, super.key});
  final Identity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = ContactCard(
      id: identity.id,
      name: identity.name,
      publicKey: identity.publicKey,
    );
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadii.md,
              ),
              child: QrImageView(
                data: card.encode(),
                size: 200,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Color(0xFF0F766E),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Color(0xFF134E4A),
                ),
                semanticsLabel: 'QR code with your AV-ID',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              identity.id.value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.primary,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: identity.id.value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AV-ID copied')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy AV-ID'),
            ),
          ],
        ),
      ),
    );
  }
}
