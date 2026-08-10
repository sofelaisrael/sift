import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Static warm skeleton block — NO shimmer, NO pulse. Base = surfaceWarm2.
class SkeletonLoader extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: s.surfaceWarm2,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Layout-matched library card: full-bleed 16:9 image + two text lines.
class ScreenshotCardSkeleton extends StatelessWidget {
  const ScreenshotCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: BorderRadius.circular(SiftRadii.rCard),
        border: Border.all(color: s.divider),
        boxShadow: SiftElevation.card(
          Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: SkeletonLoader(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(
                  width: double.infinity,
                  height: 16,
                  borderRadius: 4,
                ),
                SizedBox(height: 8),
                SkeletonLoader(width: 96, height: 12, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
