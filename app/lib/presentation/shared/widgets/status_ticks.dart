import 'package:av_chat/domain/value_objects/message_status.dart';
import 'package:flutter/material.dart';

/// ⏱ sending · ✓✓ delivered · blue ✓✓ read · ⚠ not delivered.
class StatusTicks extends StatelessWidget {
  const StatusTicks(
    this.status, {
    this.color,
    this.onPrimary = false,
    super.key,
  });

  final MessageStatus status;
  final Color? color;

  /// True inside an outgoing (primary-colored) bubble: picks a read color
  /// with enough contrast against it.
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final readColor = switch ((dark, onPrimary)) {
      (false, true) => const Color(0xFF7DD3FC),
      (true, true) => const Color(0xFF0369A1),
      (false, false) => const Color(0xFF0284C7),
      (true, false) => const Color(0xFF38BDF8),
    };
    final (icon, tint, label) = switch (status) {
      MessageStatus.sending => (Icons.schedule, base, 'Sending'),
      MessageStatus.delivered => (Icons.done_all, base, 'Delivered'),
      MessageStatus.read => (Icons.done_all, readColor, 'Read'),
      MessageStatus.failed => (
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
        'Not delivered',
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: Icon(
        icon,
        key: ValueKey(status),
        size: 16,
        color: tint,
        semanticLabel: label,
      ),
    );
  }
}
