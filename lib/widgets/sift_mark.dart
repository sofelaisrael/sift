import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Sift brand mark: three stacked rounded bars, decreasing in width,
/// ember-filled. Pure Containers — no assets, no gradients.
class SiftMark extends StatelessWidget {
  final double size;
  final Color? color;

  const SiftMark({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final markColor = color ?? AppTheme.emberMain;

    // 28/20/12 wide, 6 tall, radius 3, 4px gap — scaled to [size].
    final scale = size / 28.0;
    final barHeight = 6.0 * scale;
    final gap = 4.0 * scale;
    final radius = BorderRadius.circular(3.0 * scale);

    final bars = [
      SizedBox(width: 28.0 * scale, height: barHeight),
      SizedBox(width: 20.0 * scale, height: barHeight),
      SizedBox(width: 12.0 * scale, height: barHeight),
    ];

    return Semantics(
      label: 'Sift',
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < bars.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                Container(
                  width: bars[i].width,
                  height: bars[i].height,
                  decoration: BoxDecoration(
                    color: markColor,
                    borderRadius: radius,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
