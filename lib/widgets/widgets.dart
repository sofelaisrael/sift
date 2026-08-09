import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'sift_mark.dart';

/// Single neutral recognition tag. Label differentiates, never color.
class TypeBadge extends StatelessWidget {
  final String? type;
  final bool compact;

  const TypeBadge({super.key, required this.type, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = AppTheme.typeLabel(type);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.tagFillDark : AppTheme.tagFillLight,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.tagTextDark : AppTheme.tagTextLight,
        ),
      ),
    );
  }
}

/// User-added tag chip. Optional delete affordance with a 40px hit target.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 3 : 5,
        compact ? 8 : (onDeleted != null ? 6 : 10),
        compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? (compact
                  ? AppTheme.surfaceContainerDark
                  : AppTheme.surfaceDark)
            : (compact
                  ? AppTheme.surfaceContainerLight
                  : AppTheme.surfaceLight),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.emberMain,
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
                      color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
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

/// Flat processing banner with the Sift mark pulsing. No gradient, no spinner.
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

class _ProcessingBannerState extends State<ProcessingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (Motion.enabled) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.4, end: 1.0).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOutSine),
            ),
            child: const SiftMark(size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          if (widget.onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
            ),
        ],
      ),
    );
  }
}

/// Empty library state: porcelain tile with the Sift mark and ghost card
/// outlines behind it.
class EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback? onAsk;

  const EmptyState({super.key, required this.onScan, this.onAsk});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _ghostCard(context, isDark, -7),
                  _ghostCard(context, isDark, 6),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
                      borderRadius: BorderRadius.circular(AppTheme.r2xl),
                      border: Border.all(
                        color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                      ),
                      boxShadow: AppTheme.raisedShadow(isDark),
                    ),
                    child: const Center(
                      child: SiftMark(size: 48),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Nothing saved yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a screenshot and Sift will\nremember it for you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text(
                'Scan Screenshot',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
            ),
            if (onAsk != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onAsk,
                child: Text(
                  'Ask your memory instead',
                  style: TextStyle(
                    color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
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

  Widget _ghostCard(BuildContext context, bool isDark, double angle) {
    return Transform.rotate(
      angle: angle * 3.14159 / 180,
      child: Opacity(
        opacity: 0.45,
        child: Container(
          width: 168,
          height: 104,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.rXl),
            border: Border.all(
              color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
            ),
          ),
        ),
      ),
    );
  }
}
