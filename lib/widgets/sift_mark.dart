import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Sift brand mark: a stylized funnel/filter shape — three stacked
/// curved layers that taper downward, suggesting sifting through content.
/// Replaces the previous 6-petal asterisk-star with a more distinctive mark
/// that directly represents what the app does.
class SiftMark extends StatelessWidget {
  final double size;
  final Color? color;

  const SiftMark({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final markColor = color ?? AppTheme.of(context).accent;
    return Semantics(
      label: 'Sift',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: SiftMarkPainter(color: markColor),
        ),
      ),
    );
  }
}

/// Paints the mark: three stacked curved layers tapering downward.
///
/// The shape evokes a sieve/filter — material enters wide at the top and
/// is refined as it passes through each layer. The curves create an organic,
/// warm feel consistent with the paper canvas design DNA.
///
/// At small sizes the curves render as clean strokes; at large sizes (>=56)
/// they render as filled shapes with subtle depth.
class SiftMarkPainter extends CustomPainter {
  final Color color;

  const SiftMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;

    // Three layers: top (widest), middle, bottom (narrowest).
    // Each layer is a curved band that tapers inward.
    final layers = [
      _LayerConfig(
        y: size.height * 0.18,
        width: s * 0.82,
        height: s * 0.22,
        curveDepth: s * 0.06,
      ),
      _LayerConfig(
        y: size.height * 0.42,
        width: s * 0.62,
        height: s * 0.22,
        curveDepth: s * 0.05,
      ),
      _LayerConfig(
        y: size.height * 0.64,
        width: s * 0.42,
        height: s * 0.20,
        curveDepth: s * 0.04,
      ),
    ];

    for (final layer in layers) {
      _drawLayer(canvas, cx, layer, s);
    }

    // Small hub circle at the bottom — the "sifted" result.
    final hubRadius = s * 0.06;
    final hubY = size.height * 0.88;
    canvas.drawCircle(
      Offset(cx, hubY),
      hubRadius,
      Paint()..color = color,
    );
  }

  void _drawLayer(Canvas canvas, double cx, _LayerConfig layer, double s) {
    final halfW = layer.width / 2;
    final top = layer.y;
    final mid = top + layer.height / 2;
    final bottom = top + layer.height;

    // Each layer is a rounded rectangle with curved top and bottom edges,
    // creating the tapered sieve effect.
    final path = Path()
      ..moveTo(cx - halfW, top)
      // Top edge curves inward slightly
      ..quadraticBezierTo(cx, top - layer.curveDepth, cx + halfW, top)
      // Right edge
      ..lineTo(cx + halfW * 0.85, bottom)
      // Bottom edge curves inward
      ..quadraticBezierTo(cx, bottom + layer.curveDepth, cx - halfW * 0.85, bottom)
      // Left edge
      ..lineTo(cx - halfW, top)
      ..close();

    // Slight opacity gradient: top layer most opaque, bottom least.
    final opacity = 1.0 - (layer.y / (s * 1.2)) * 0.3;
    final paint = Paint()
      ..color = color.withOpacity(opacity.clamp(0.5, 1.0))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SiftMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LayerConfig {
  final double y;
  final double width;
  final double height;
  final double curveDepth;

  const _LayerConfig({
    required this.y,
    required this.width,
    required this.height,
    required this.curveDepth,
  });
}
