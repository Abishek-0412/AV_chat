import 'dart:async';
import 'dart:math' as math;

import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six dots plus a numeric keypad. Calls [onComplete] at [length] digits.
class PinPad extends StatefulWidget {
  const PinPad({
    required this.onComplete,
    this.length = 6,
    this.trailing,
    this.enabled = true,
    super.key,
  });

  final int length;
  final ValueChanged<String> onComplete;

  /// Optional key in the bottom-left slot (e.g. fingerprint).
  final Widget? trailing;
  final bool enabled;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  var _pin = '';
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// Clears the entry and shakes the dots (wrong PIN).
  void reject() {
    unawaited(HapticFeedback.heavyImpact());
    setState(() => _pin = '');
    unawaited(_shake.forward(from: 0));
  }

  void clear() => setState(() => _pin = '');

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _tap(String digit) {
    if (!widget.enabled || _pin.length >= widget.length) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _pin += digit);
    if (_pin.length == widget.length) widget.onComplete(_pin);
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Semantics(
            label: '${_pin.length} of ${widget.length} digits entered',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? scheme.primary : null,
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) _Key(label: d, onTap: () => _tap(d)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(dimension: 80, child: widget.trailing),
            _Key(label: '0', onTap: () => _tap('0')),
            SizedBox.square(
              dimension: 80,
              child: IconButton(
                onPressed: _back,
                icon: const Icon(Icons.backspace_outlined),
                tooltip: 'Delete',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: SizedBox.square(
        dimension: 72,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(label, style: theme.textTheme.headlineSmall),
            ),
          ),
        ),
      ),
    );
  }
}
