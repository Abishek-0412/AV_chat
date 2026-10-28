import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/my_code_card.dart';
import 'package:av_chat/presentation/shared/widgets/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

enum _Step { welcome, name, pin, confirm, biometrics, done }

/// First launch: name → PIN → (fingerprint) → your AV-ID.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  final _name = TextEditingController();
  final _confirmPad = GlobalKey<PinPadState>();
  String? _pin;
  late Identity _identity;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _go(_Step step) => setState(() => _step = step);

  Future<void> _onConfirm(String pin) async {
    if (pin != _pin) {
      _confirmPad.currentState?.reject();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PINs don't match. Try again.")),
      );
      return;
    }
    setState(() => _busy = true);
    final lock = ref.read(appLockProvider);
    await lock.setPin(pin);
    final canBio = await lock.biometricsAvailable();
    if (!mounted) return;
    setState(() => _busy = false);
    if (canBio) {
      _go(_Step.biometrics);
    } else {
      await _finish();
    }
  }

  Future<void> _finish({bool biometrics = false}) async {
    setState(() => _busy = true);
    await ref.read(appLockProvider).setBiometricsEnabled(enabled: biometrics);
    ref.read(lockedProvider.notifier).unlock();
    final identity = await ref
        .read(identityProvider.notifier)
        .create(_name.text);
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _busy = false;
      _step = _Step.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_step), child: _body()),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_step) {
    _Step.welcome => _Welcome(onStart: () => _go(_Step.name)),
    _Step.name => _NameStep(
      controller: _name,
      onNext: () => _go(_Step.pin),
    ),
    _Step.pin => _PinStep(
      title: 'Create a PIN',
      subtitle: 'You will need it every time you open AV Chat.',
      onComplete: (pin) {
        _pin = pin;
        _go(_Step.confirm);
      },
    ),
    _Step.confirm => _PinStep(
      padKey: _confirmPad,
      title: 'Confirm your PIN',
      subtitle: 'Enter the same 6 digits again.',
      enabled: !_busy,
      onComplete: _onConfirm,
    ),
    _Step.biometrics => _BiometricsStep(
      busy: _busy,
      onChoice: (enabled) => _finish(biometrics: enabled),
    ),
    _Step.done => _DoneStep(
      identity: _identity,
      onContinue: () => context.go(AppRoutes.chats),
    ),
  };
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.children, this.bottom});
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children
                      .animate(interval: AppMotion.stagger)
                      .fadeIn(duration: AppMotion.slow, curve: AppMotion.curve)
                      .slideY(begin: 0.1, curve: AppMotion.curve),
                ),
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _StepScaffold(
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onStart,
          child: const Text('Get started'),
        ),
      ),
      children: [
        SvgPicture.asset(
          'assets/illustrations/welcome.svg',
          width: 220,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Private by design', style: t.headlineMedium),
        const SizedBox(height: AppSpacing.xl),
        const _Point(
          icon: Icons.phonelink_lock_outlined,
          text: 'No phone number. Your ID is a key that lives on this phone.',
        ),
        const _Point(
          icon: Icons.lock_outline,
          text: 'Messages and calls are end-to-end encrypted.',
        ),
        const _Point(
          icon: Icons.auto_delete_outlined,
          text: 'Chats disappear when you close the app.',
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _NameStep extends StatefulWidget {
  const _NameStep({required this.controller, required this.onNext});
  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  @override
  Widget build(BuildContext context) {
    final valid = widget.controller.text.trim().isNotEmpty;
    final t = Theme.of(context).textTheme;
    return _StepScaffold(
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: valid ? widget.onNext : null,
          child: const Text('Continue'),
        ),
      ),
      children: [
        Text("What's your name?", style: t.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Only people you add will see it.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: widget.controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Your name'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => valid ? widget.onNext() : null,
        ),
      ],
    );
  }
}

class _PinStep extends StatelessWidget {
  const _PinStep({
    required this.title,
    required this.subtitle,
    required this.onComplete,
    this.padKey,
    this.enabled = true,
  });
  final String title;
  final String subtitle;
  final ValueChanged<String> onComplete;
  final GlobalKey<PinPadState>? padKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _StepScaffold(
      children: [
        Text(title, style: t.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(subtitle, style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.xxl),
        PinPad(key: padKey, onComplete: onComplete, enabled: enabled),
      ],
    );
  }
}

class _BiometricsStep extends StatelessWidget {
  const _BiometricsStep({required this.onChoice, required this.busy});
  final ValueChanged<bool> onChoice;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _StepScaffold(
      bottom: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : () => onChoice(true),
              child: const Text('Use fingerprint'),
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => onChoice(false),
            child: const Text('Not now'),
          ),
        ],
      ),
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.fingerprint, size: 56, color: scheme.primary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Unlock with fingerprint?', style: t.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Faster than typing your PIN. You can change this in Settings.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.identity, required this.onContinue});
  final Identity identity;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _StepScaffold(
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onContinue,
          child: const Text('Start chatting'),
        ),
      ),
      children: [
        Text("You're all set, ${identity.name}", style: t.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Friends add you by scanning this code.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        MyCodeCard(identity: identity),
      ],
    );
  }
}
