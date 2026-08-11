import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ingest_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import 'widgets.dart';

/// Live bulk-ingest banner: pulsing mark + indexed-so-far count, an ETA line
/// once a rate is measurable, and pause/resume. Rebuilds off the
/// [IngestService] notifier, so a long pass never drives `setState` storms
/// through the provider.
class IngestBanner extends StatelessWidget {
  final IngestService ingest;

  const IngestBanner({super.key, required this.ingest});

  static String _formatEta(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds < 60) return '${totalSeconds}s left';
    final minutes = (totalSeconds / 60).ceil();
    return 'about $minutes min left';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    final count = ingest.processedCount;
    final digest = count == 0
        ? 'Finding screenshots…'
        : '$count indexed so far';
    final eta = ingest.estimatedRemaining;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ingest.paused ? s.surfaceWarm1 : s.surfaceWarm2,
        borderRadius: BorderRadius.circular(SiftRadii.rThumb),
      ),
      child: Row(
        children: [
          ingest.paused
              ? Icon(Icons.pause_rounded, size: 18, color: s.stone)
              : const PulsingMark(size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingest.paused ? 'Library index paused' : 'Indexing your library',
                  style: SiftType.bodySansMd.copyWith(
                    fontWeight: FontWeight.w600,
                    color: s.ink,
                  ),
                ),
                Text(
                  ingest.paused
                      ? '$count indexed · tap resume to continue'
                      : (eta == null && count > 0)
                          ? digest
                          : eta == null
                              ? digest
                              : '$digest · ${_formatEta(eta)}',
                  style: SiftType.bodySansMd.copyWith(
                    fontSize: 13,
                    color: s.graphite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: ingest.paused ? 'Resume' : 'Pause',
            onPressed: () {
              if (MotionTokens.canHaptic) HapticFeedback.selectionClick();
              if (ingest.paused) {
                ingest.resume();
              } else {
                ingest.pause();
              }
            },
            icon: Icon(
              ingest.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
              color: s.ink,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}