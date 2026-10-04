import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'brutal_chip.dart';

/// Static warm skeleton block — NO shimmer, NO pulse. Base = surfaceWarm2.
///
/// The default corner is [SiftRadii.rInline] rather than a bare 8 so the inner
/// text lines match the 4pt corner of the card they stand in for. A skeleton is
/// a fill block, not a surface: it gets no edge and no shadow of its own, which
/// is what keeps it reading as "not loaded yet" rather than as a small card.
class SkeletonLoader extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = SiftRadii.rInline,
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
///
/// Hard-edged to match `_SiftCard` exactly, on radius, border weight, border
/// colour and shadow. A skeleton at the old rCard 20 while the real card lands
/// at rControl 4 is a visible pop at the moment the data arrives — and it is a
/// pop on the one screen the user waits longest on, so it reads as a glitch
/// rather than as a load finishing.
class ScreenshotCardSkeleton extends StatelessWidget {
  const ScreenshotCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      clipBehavior: Clip.antiAlias,
      decoration: brutalEdge(
        fill: s.paper,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: SkeletonLoader(
              width: double.infinity,
              height: double.infinity,
              // The image bleeds to the card's edge; the card's own
              // `clipBehavior` does the rounding, so this block must not round
              // itself or a sliver of fill shows in the corner.
              borderRadius: SiftRadii.r0,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: double.infinity, height: 16),
                SizedBox(height: 8),
                SkeletonLoader(width: 96, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
