import 'package:flutter/animation.dart';

/// Motion tokens: short, ease-out, never in the way.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const stagger = Duration(milliseconds: 80);
  static const Curve curve = Curves.easeOutCubic;
}
