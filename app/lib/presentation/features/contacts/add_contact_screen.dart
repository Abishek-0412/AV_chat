import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/user_facing_exception.dart';
import 'package:av_chat/presentation/shared/theme/app_radii.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/my_code_card.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scan a QR code, type an AV-ID, or show your own code.
class AddContactScreen extends ConsumerWidget {
  const AddContactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add contact'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan'),
              Tab(icon: Icon(Icons.keyboard_outlined), text: 'Enter ID'),
              Tab(icon: Icon(Icons.qr_code_2), text: 'My code'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const _ScanTab(),
            const _EnterIdTab(),
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Consumer(
                builder: (context, ref, _) {
                  final identity = ref.watch(identityProvider).value;
                  return identity == null
                      ? const SizedBox.shrink()
                      : MyCodeCard(identity: identity);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanTab extends ConsumerStatefulWidget {
  const _ScanTab();

  @override
  ConsumerState<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends ConsumerState<_ScanTab> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  var _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final code in capture.barcodes) {
      final card = ContactCard.tryDecode(code.rawValue ?? '');
      if (card == null) continue;
      _handled = true;
      await HapticFeedback.mediumImpact();
      final session = ref.read(sessionProvider).value;
      try {
        await session?.contacts.addFromCard(card);
      } on UserFacingException catch (e) {
        _toast(e.message);
        _handled = false;
        return;
      }
      if (!mounted) return;
      _toast('${card.name} added');
      context.pop();
      return;
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Camera unavailable. Allow camera access, or use "Enter ID".',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: AppRadii.lg,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.xxl,
          child: Text(
            "Point at your friend's AV Chat code",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              shadows: [Shadow(blurRadius: 8)],
            ),
          ),
        ),
      ],
    );
  }
}

class _EnterIdTab extends ConsumerStatefulWidget {
  const _EnterIdTab();

  @override
  ConsumerState<_EnterIdTab> createState() => _EnterIdTabState();
}

class _EnterIdTabState extends ConsumerState<_EnterIdTab> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final id = AvId.tryParse(_id.text);
    if (id == null) {
      setState(() => _error = 'That does not look like an AV-ID');
      return;
    }
    final session = ref.read(sessionProvider).value;
    try {
      await session?.contacts.addById(id, name: _name.text);
    } on UserFacingException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request sent. They need to accept while online.'),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        TextField(
          controller: _id,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'AV-ID',
            hintText: 'AV-XXXX-XXXX-XXXX',
            errorText: _error,
            prefixIcon: const Icon(Icons.tag),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Send request'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Scanning a QR code is safer: it also checks their key. '
          'With a typed ID, compare safety codes afterwards.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
