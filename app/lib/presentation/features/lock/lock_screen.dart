import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PIN / fingerprint gate shown on launch and after time in background.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const _maxTries = 5;
  static const _cooldown = Duration(seconds: 30);

  final _pad = GlobalKey<PinPadState>();
  var _failures = 0;
  var _bioEnabled = false;
  DateTime? _blockedUntil;
  Timer? _tick;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initBiometrics());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    final lock = ref.read(appLockProvider);
    final enabled =
        await lock.biometricsEnabled() && await lock.biometricsAvailable();
    if (!mounted) return;
    setState(() => _bioEnabled = enabled);
    if (enabled) await _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    final ok = await ref.read(appLockProvider).authenticateWithBiometrics();
    if (ok && mounted) ref.read(lockedProvider.notifier).unlock();
  }

  bool get _blocked =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  Future<void> _onPin(String pin) async {
    if (_blocked || _checking) return;
    setState(() => _checking = true);
    final ok = await ref.read(appLockProvider).verifyPin(pin);
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      ref.read(lockedProvider.notifier).unlock();
      return;
    }
    _failures++;
    _pad.currentState?.reject();
    if (_failures >= _maxTries) {
      _failures = 0;
      _blockedUntil = DateTime.now().add(_cooldown);
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!_blocked) t.cancel();
        setState(() {});
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _blocked
        ? _blockedUntil!.difference(DateTime.now()).inSeconds + 1
        : 0;
    final message = _blocked
        ? 'Too many tries. Wait $remaining s.'
        : _failures > 0
        ? 'Wrong PIN. ${_maxTries - _failures} tries left.'
        : 'Enter your PIN';
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Image.asset('assets/icon/icon_full.png', width: 72)
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(begin: const Offset(0.8, 0.8)),
                  const SizedBox(height: AppSpacing.lg),
                  Text('AV Chat', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: 200.ms,
                    child: Text(
                      message,
                      key: ValueKey(message),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _failures > 0 || _blocked
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  PinPad(
                    key: _pad,
                    enabled: !_blocked && !_checking,
                    onComplete: _onPin,
                    trailing: _bioEnabled
                        ? IconButton(
                            onPressed: _tryBiometrics,
                            icon: const Icon(Icons.fingerprint, size: 32),
                            tooltip: 'Use fingerprint',
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
