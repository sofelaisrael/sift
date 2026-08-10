import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import 'sift_mark.dart';

/// Neutral recognition type badge. Label differentiates, never color.
/// Full pill, badgeBg/badgeText tokens.
class TypeBadge extends StatelessWidget {
  final String? type;
  final bool compact;

  const TypeBadge({super.key, required this.type, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final label = AppTheme.typeLabel(type);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: s.badgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: SiftType.microLabel.copyWith(
          fontWeight: FontWeight.w600,
          color: s.badgeText,
        ),
      ),
    );
  }
}

/// User-added tag chip. Hairline pill with optional delete affordance.
class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onDeleted;
  final bool compact;

  const TagChip({
    super.key,
    required this.label,
    this.onDeleted,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 3 : 5,
        compact ? 8 : (onDeleted != null ? 6 : 10),
        compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.tagBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: SiftType.microLabel.copyWith(
              fontWeight: FontWeight.w600,
              color: s.tagText,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 2),
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: InkWell(
                  onTap: onDeleted,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: s.stone,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulsing Sift mark — the only idle loop besides the streaming caret.
/// 1.0 -> 1.15 over 1200ms (easeOutCubic 45% / easeInCubic 55%). Static
/// (scale 1.0) when reduced motion is on.
class PulsingMark extends StatefulWidget {
  final double size;
  final Color? color;
  final double toScale;

  const PulsingMark({
    super.key,
    required this.size,
    this.color,
    this.toScale = 1.15,
  });

  @override
  State<PulsingMark> createState() => _PulsingMarkState();
}

class _PulsingMarkState extends State<PulsingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.pulseCycle,
    );
    if (MotionTokens.enabled) {
      _scale = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: widget.toScale).chain(
            CurveTween(curve: MotionTokens.easeOutCubic),
          ),
          weight: 45,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: widget.toScale, end: 1.0).chain(
            CurveTween(curve: MotionTokens.easeInCubic),
          ),
          weight: 55,
        ),
      ]).animate(_controller);
      _controller.repeat();
    } else {
      _scale = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(scale: _scale.value, child: child);
      },
      child: SiftMark(size: widget.size, color: widget.color),
    );
  }
}

/// Flat processing banner: surfaceWarm2 + pulsing mark. No gradient,
/// no spinner, no shimmer.
class ProcessingBanner extends StatefulWidget {
  final String message;
  final VoidCallback? onDismiss;

  const ProcessingBanner({
    super.key,
    required this.message,
    this.onDismiss,
  });

  @override
  State<ProcessingBanner> createState() => _ProcessingBannerState();
}

class _ProcessingBannerState extends State<ProcessingBanner> {
  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s.surfaceWarm2,
        borderRadius: BorderRadius.circular(SiftRadii.rThumb),
      ),
      child: Row(
        children: [
          const PulsingMark(size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.message,
              style: SiftType.bodySansMd.copyWith(
                fontWeight: FontWeight.w500,
                color: s.ink,
              ),
            ),
          ),
          if (widget.onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: s.stone,
            ),
        ],
      ),
    );
  }
}

/// Empty library state: mark 40 + serif headline + quiet line + CTA.
class EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback? onAsk;

  const EmptyState({super.key, required this.onScan, this.onAsk});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SiftMark(size: 40),
            const SizedBox(height: 28),
            Text(
              'Nothing saved yet',
              textAlign: TextAlign.center,
              style: SiftType.serifDisplay.copyWith(color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a screenshot and Sift will remember it for you.',
              textAlign: TextAlign.center,
              style: SiftType.bodySans.copyWith(
                color: s.graphite,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text('Add a screenshot'),
            ),
            if (onAsk != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onAsk,
                child: Text(
                  'Ask your memory instead',
                  style: SiftType.buttonLabel.copyWith(
                    color: s.stone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
