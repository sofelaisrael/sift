import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Sift brand mark: a 6-petal asterisk-meets-star, hand-drawn with a
/// CustomPainter — never Icons.auto_awesome or Icons.asterisk.
///
/// At large sizes (>= 56) the mark switches to a high-fidelity filled
/// quadratic variant; smaller sizes render clean stroked petals.
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
          painter: SiftMarkPainter(
            color: markColor,
            filled: size >= 56,
          ),
        ),
      ),
    );
  }
}

/// Paints the mark. Petals radiate at -90deg + k*60deg with tip radius
/// 0.45s and stroke width 0.16s; a hub circle of 0.09s anchors the center.
class SiftMarkPainter extends CustomPainter {
  final Color color;
  final bool filled;

  const SiftMarkPainter({required this.color, this.filled = false});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final tip = s * 0.45;
    final hub = s * 0.09;

    if (filled) {
      _paintFilled(canvas, center, tip, hub, s);
    } else {
      _paintStroked(canvas, center, tip, hub, s);
    }
  }

  void _paintStroked(Canvas canvas, Offset center, double tip, double hub, double s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var k = 0; k < 6; k++) {
      final angle = -math.pi / 2 + k * math.pi / 3;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center, center + dir * tip, paint);
    }
    canvas.drawCircle(center, hub, Paint()..color = color);
  }

  void _paintFilled(Canvas canvas, Offset center, double tip, double hub, double s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final halfW = s * 0.16 * 0.62;
    final inner = hub * 0.9;
    final waist = tip * 0.45;

    for (var k = 0; k < 6; k++) {
      final angle = -math.pi / 2 + k * math.pi / 3;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final perp = Offset(-dir.dy, dir.dx);

      final baseIn = center + dir * inner;
      final baseOut = center + dir * (inner + halfW * 0.3);
      final tipPoint = center + dir * tip;
      final cw = center + dir * waist;

      final path = Path()
        ..moveTo(
          baseIn.dx - perp.dx * halfW * 0.45,
          baseIn.dy - perp.dy * halfW * 0.45,
        )
        ..quadraticBezierTo(
          cw.dx - perp.dx * halfW,
          cw.dy - perp.dy * halfW,
          tipPoint.dx,
          tipPoint.dy,
        )
        ..quadraticBezierTo(
          cw.dx + perp.dx * halfW,
          cw.dy + perp.dy * halfW,
          baseOut.dx + perp.dx * halfW * 0.45,
          baseOut.dy + perp.dy * halfW * 0.45,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(center, hub, paint);
  }

  @override
  bool shouldRepaint(covariant SiftMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}
