import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Motion tokens for "Warm Paper Recall". All durations collapse to zero,
/// curves go linear, loops stop, and haptics are skipped when the system
/// requests reduced motion. The MaterialApp builder is the single place
/// where [reduced] is set.
abstract final class MotionTokens {
  MotionTokens._();

  /// Set from the MaterialApp builder when a reduced-motion preference is
  /// active. Mirrors MediaQuery.disableAnimationsOf at the root.
  static bool reduced = false;

  /// Mirrors the Behavior > haptics setting (default on). Kept in sync by
  /// the Settings screen.
  static bool hapticsEnabled = true;

  static bool get enabled => !reduced;

  static bool get canHaptic => enabled && hapticsEnabled;

  // Durations — every interaction settles under 500ms (500 celebration cap).
  static Duration get press =>
      reduced ? Duration.zero : const Duration(milliseconds: 60);
  static Duration get pressRelease =>
      reduced ? Duration.zero : const Duration(milliseconds: 140);
  static Duration get standard =>
      reduced ? Duration.zero : const Duration(milliseconds: 200);
  static Duration get emphasis =>
      reduced ? Duration.zero : const Duration(milliseconds: 300);
  static Duration get celebration =>
      reduced ? Duration.zero : const Duration(milliseconds: 500);
  static Duration get dismiss =>
      reduced ? Duration.zero : const Duration(milliseconds: 150);

  // Loop cadences — call sites must gate the loop on [enabled].
  static const Duration wordTick = Duration(milliseconds: 80);
  static const Duration caretCycle = Duration(milliseconds: 600);
  static const Duration pulseCycle = Duration(milliseconds: 1200);

  // Curves.
  static const Curve easeOutCubic = Curves.easeOutCubic;
  static const Curve easeInCubic = Curves.easeInCubic;
  static const Curve linear = Curves.linear;
  static const Curve easeInOutSine = Curves.easeInOutSine;
  static const Curve easeOutBack = Curves.easeOutBack;

  /// easeOutBack with the overshoot amplitude capped at 1.06 so pulses never
  /// bounce beyond the 4pt rhythm.
  static Curve get easeOutBackCapped =>
      const _EaseOutBackCapped(amplitude: 1.06);
}

/// easeOutBack with a capped overshoot amplitude.
class _EaseOutBackCapped extends Curve {
  final double amplitude;

  const _EaseOutBackCapped({required this.amplitude});

  @override
  double transformInternal(double t) {
    final c1 = amplitude - 1.0;
    final c3 = c1 + 1.0;
    final u = t - 1.0;
    return 1.0 + c3 * math.pow(u, 3).toDouble() + c1 * math.pow(u, 2).toDouble();
  }
}
