import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Illustration + title + hint for a list with nothing to show.
/// Elements ease in one after another.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.illustration,
    required this.title,
    required this.message,
    super.key,
  });

  /// Path of an SVG under `assets/illustrations/`.
  final String illustration;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              [
                    SvgPicture.asset(
                      illustration,
                      width: 200,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ]
                  .animate(interval: AppMotion.stagger)
                  .fadeIn(duration: AppMotion.slow, curve: AppMotion.curve)
                  .slideY(
                    begin: 0.15,
                    duration: AppMotion.slow,
                    curve: AppMotion.curve,
                  ),
        ),
      ),
    );
  }
}
