import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/screenshot.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import 'sift_mark.dart';
import 'widgets.dart' show PulsingMark;

String formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// User message: soft pill (surfaceWarm1, full capsule, right-aligned,
/// max 80% width, bodySans ink). Slides up 300ms on entrance.
class UserPill extends StatefulWidget {
  final String text;

  const UserPill({super.key, required this.text});

  @override
  State<UserPill> createState() => _UserPillState();
}

class _UserPillState extends State<UserPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.emphasis,
    );
    _slide = CurvedAnimation(parent: _controller, curve: MotionTokens.easeOutCubic);
    if (MotionTokens.enabled) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;

    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) {
          return Opacity(
            opacity: _slide.value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - _slide.value)),
              child: child,
            ),
          );
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: s.surfaceWarm1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.text,
            style: SiftType.bodySans.copyWith(color: s.ink),
          ),
        ),
      ),
    );
  }
}

/// Perplexity-style evidence strip. 48px square thumbnails (r12, hairline,
/// cover) with 8pt gaps, max 5 visible plus a "+N" overflow square. Caption
/// "Read from N screenshots" with N in accent tabular; " · partial match"
/// warning suffix. Thumbs stagger in 60ms apart; tapping opens Detail.
class EvidenceStrip extends StatefulWidget {
  final List<Screenshot> sources;
  final ValueChanged<Screenshot>? onOpen;
  final Widget Function(Screenshot screenshot, int index)? thumbBuilder;
  final bool partial;

  const EvidenceStrip({
    super.key,
    required this.sources,
    this.onOpen,
    this.thumbBuilder,
    this.partial = false,
  });

  @override
  State<EvidenceStrip> createState() => _EvidenceStripState();
}

class _EvidenceStripState extends State<EvidenceStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    if (MotionTokens.enabled) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final shown = widget.sources.take(5).toList();
    final overflow = widget.sources.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _buildThumb(context, shown[i], i),
              ],
              if (overflow > 0) ...[
                const SizedBox(width: 8),
                _FadeIn(
                  controller: _controller,
                  index: shown.length,
                  child: Container(
                    width: SiftSpacing.thumb,
                    height: SiftSpacing.thumb,
                    decoration: BoxDecoration(
                      color: s.surfaceWarm2,
                      borderRadius: BorderRadius.circular(SiftRadii.rThumb),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$overflow',
                      style: SiftType.chipLabel.copyWith(
                        color: s.stone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: SiftType.metaLabel.copyWith(color: s.stone),
            children: [
              const TextSpan(text: 'Read from '),
              TextSpan(
                text: '${widget.sources.length}',
                style: SiftType.metaLabel.copyWith(
                  color: s.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: widget.sources.length == 1
                    ? ' screenshot'
                    : ' screenshots',
              ),
              if (widget.partial)
                TextSpan(
                  text: ' · partial match',
                  style: SiftType.metaLabel.copyWith(color: s.warning),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumb(BuildContext context, Screenshot screenshot, int index) {
    return _FadeIn(
      controller: _controller,
      index: index,
      child: InkWell(
        onTap: widget.onOpen == null
            ? null
            : () {
                if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
                widget.onOpen!(screenshot);
              },
        borderRadius: BorderRadius.circular(SiftRadii.rThumb),
        child: widget.thumbBuilder?.call(screenshot, index) ??
            _defaultThumb(context, screenshot),
      ),
    );
  }

  Widget _defaultThumb(BuildContext context, Screenshot screenshot) {
    final s = AppTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SiftRadii.rThumb),
      child: Container(
        width: SiftSpacing.thumb,
        height: SiftSpacing.thumb,
        decoration: BoxDecoration(
          border: Border.all(color: s.divider),
        ),
        child: Image.file(
          File(screenshot.filePath),
          fit: BoxFit.cover,
          cacheWidth: 96,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: s.surfaceWarm2,
              child: Icon(Icons.image_outlined, size: 18, color: s.stone),
            );
          },
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Widget child;

  const _FadeIn({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final interval = Interval(
      index * 0.06,
      0.35 + index * 0.06,
      curve: MotionTokens.easeOutCubic,
    );
    final curved = CurvedAnimation(parent: controller, curve: interval);

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Assistant essay block. Flat — no container. Sender row (mark 16 + "Sift"
/// graphite + time), serifBody text, word-by-word streaming through ONE
/// Text.rich with an 8x18 accent caret, then Regenerate + copy actions.
class EssayBlock extends StatefulWidget {
  final String text;
  final DateTime? timestamp;
  final bool stream;
  final bool showActions;
  final VoidCallback? onRegenerate;

  const EssayBlock({
    super.key,
    required this.text,
    this.timestamp,
    this.stream = false,
    this.showActions = true,
    this.onRegenerate,
  });

  @override
  State<EssayBlock> createState() => _EssayBlockState();
}

class _EssayBlockState extends State<EssayBlock>
    with TickerProviderStateMixin {
  late final List<String> _words;
  late final AnimationController _trailing;
  late final AnimationController _caret;
  late final AnimationController _caretFade;
  Timer? _timer;
  bool _streaming = false;
  bool _copied = false;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(' ');
    _trailing = AnimationController(vsync: this, duration: MotionTokens.wordTick);
    _caret = AnimationController(vsync: this, duration: MotionTokens.caretCycle);
    _caretFade = AnimationController(vsync: this, duration: MotionTokens.standard);

    if (widget.stream && MotionTokens.enabled) {
      _streaming = true;
      _shown = 1;
      _trailing.forward();
      _caret.repeat(reverse: true);
      _timer = Timer.periodic(MotionTokens.wordTick, (_) {
        if (!mounted) return;
        setState(() {
          if (_shown < _words.length) {
            _shown++;
            _trailing.forward(from: 0);
            _caret.forward(from: 0);
          } else {
            _finishStreaming();
          }
        });
      });
    } else {
      _shown = _words.length;
    }
  }

  void _finishStreaming() {
    _timer?.cancel();
    _timer = null;
    _streaming = false;
    _caret.stop();
    _caretFade.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _trailing.dispose();
    _caret.dispose();
    _caretFade.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!context.mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    await Future<void>.delayed(MotionTokens.standard);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final showCaret =
        widget.stream && MotionTokens.enabled && (_streaming || _caretFade.isAnimating);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SiftMark(size: 16, color: s.accent),
            const SizedBox(width: 6),
            Text(
              'Sift',
              style: SiftType.chipLabel.copyWith(
                color: s.graphite,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.timestamp != null) ...[
              const SizedBox(width: 8),
              Text(
                formatClock(widget.timestamp!),
                style: SiftType.metaLabel.copyWith(color: s.stone),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: Listenable.merge([_trailing, _caretFade]),
          builder: (context, child) {
            final visible = _words.take(_shown).toList();
            final trailingAlpha = 0.25 + 0.75 * _trailing.value;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: SiftType.serifBody.copyWith(color: s.ink),
                      children: [
                        for (var i = 0; i < visible.length; i++)
                          TextSpan(
                            text: i == visible.length - 1 &&
                                    _streaming
                                ? visible[i]
                                : '${visible[i]} ',
                            style: i == visible.length - 1 && _streaming
                                ? TextStyle(
                                    color: s.ink.withValues(alpha: trailingAlpha),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                if (showCaret) ...[
                  const SizedBox(width: 2),
                  _StreamingCaret(
                    blink: _caret,
                    fade: _caretFade,
                    streaming: _streaming,
                    color: s.accent,
                  ),
                ],
              ],
            );
          },
        ),
        if (widget.showActions && _shown == _words.length && !_streaming) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              if (widget.onRegenerate != null) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
                    widget.onRegenerate!();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Regenerate'),
                ),
                const SizedBox(width: 8),
              ],
              TextButton.icon(
                onPressed: () => _copy(context),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StreamingCaret extends StatelessWidget {
  final Animation<double> blink;
  final Animation<double> fade;
  final bool streaming;
  final Color color;

  const _StreamingCaret({
    required this.blink,
    required this.fade,
    required this.streaming,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([blink, fade]),
      builder: (context, child) {
        final opacity = streaming
            ? 0.3 + 0.7 * blink.value
            : 1.0 - fade.value;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Container(
            width: 8,
            height: 18,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}

/// Flat typing row: pulsing mark 14 + "Looking through your screenshots…".
/// Static when reduced motion is on.
class TypingRow extends StatelessWidget {
  const TypingRow({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Row(
      children: [
        const PulsingMark(size: 14),
        const SizedBox(width: 10),
        Text(
          'Looking through your screenshots…',
          style: SiftType.bodySansMd.copyWith(
            fontSize: 14,
            color: s.stone,
          ),
        ),
      ],
    );
  }
}
