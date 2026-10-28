import 'package:av_chat/presentation/shared/format.dart';
import 'package:av_chat/presentation/shared/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Initials on a color picked from the AV-ID, with optional online dot.
class AvAvatar extends StatelessWidget {
  const AvAvatar({
    required this.seed,
    required this.name,
    this.radius = 24,
    this.online,
    this.icon,
    super.key,
  });

  /// Usually the AV-ID or group id: same person, same color everywhere.
  final String seed;
  final String name;
  final double radius;

  /// Null hides the dot.
  final bool? online;
  final IconData? icon;

  static const _palette = [
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF0891B2),
    Color(0xFF9333EA),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[seed.hashCode.abs() % _palette.length];
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox.square(
      dimension: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: color.withValues(alpha: 0.18),
            child: icon != null
                ? Icon(icon, color: color, size: radius)
                : Text(
                    Format.initials(name),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: radius * 0.7,
                    ),
                  ),
          ),
          if (online != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: radius * 0.55,
                height: radius * 0.55,
                decoration: BoxDecoration(
                  color: online! ? AppColors.online : AppColors.offline,
                  shape: BoxShape.circle,
                  border: Border.all(color: surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
