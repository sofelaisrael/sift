import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative-luminance contrast, by the method DESIGN-BRUTALIST.md §7.1
/// uses for every figure in the spec.
///
/// This is a test helper, not a token: putting it in one place is what lets the
/// chip and switch tests assert the spec's own arithmetic instead of restating
/// the ratios as magic numbers that nobody can check.
double wcagLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Contrast ratio between two opaque colours. Returns 1.0 for identical
/// colours, which is the point: an invisible boundary is a ratio of one.
double wcagContrast(Color a, Color b) {
  final la = wcagLuminance(a);
  final lb = wcagLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG 2.1 SC 1.4.11 — the 3:1 floor for a UI component boundary.
const double kNonTextContrast = 3.0;
