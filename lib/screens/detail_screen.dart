import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../theme/motion_tokens.dart';
import '../widgets/brutal_button.dart';
import '../widgets/brutal_chip.dart';
import '../widgets/brutal_field.dart';
import '../widgets/widgets.dart';

/// Screenshot detail: full-bleed 240pt hero with quiet back/pin
/// circles on a photo scrim, then a serif summary, the flat "What Sift
/// sees" essay, hairline data rows, tags, the warm OCR block, and details.
/// On phone the action bar is pinned at the bottom; at >=840pt it becomes a
/// sticky ~260pt side rail.
class DetailScreen extends StatefulWidget {
  final Screenshot screenshot;

  const DetailScreen({super.key, required this.screenshot});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  static const double _railWidth = 260;
  static const double _breakpoint = 840;

  bool _running = false;
  bool _copied = false;

  bool get _wide => MediaQuery.sizeOf(context).width >= _breakpoint;

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.light,
      ),
      child: Consumer<ScreenshotProvider>(
        builder: (context, provider, _) {
          final scroll = CustomScrollView(
            slivers: [
              _buildHeroSliver(context),
              _buildContentSliver(context),
            ],
          );

          return Scaffold(
            backgroundColor: s.canvas,
            body: _wide
                ? Row(
                    children: [
                      Expanded(child: scroll),
                      _buildSideRail(context, isDark),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: scroll),
                      _buildBottomBar(context, isDark),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildHeroSliver(BuildContext context) {
    final s = AppTheme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: Colors.transparent,
      foregroundColor: s.codeText,
      leading: _QuietCircle(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Back',
        onTap: () => Navigator.pop(context),
      ),
      actions: [
        Consumer<ScreenshotProvider>(
          builder: (context, provider, _) {
            return Row(
              children: [
                _QuietCircle(
                  icon: widget.screenshot.isFavorite
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  tooltip: widget.screenshot.isFavorite ? 'Unpin' : 'Pin',
                  color: widget.screenshot.isFavorite ? s.accent : null,
                  onTap: () {
                    if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
                    context
                        .read<ScreenshotProvider>()
                        .toggleFavorite(widget.screenshot.id);
                  },
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.screenshot.filePath),
              fit: BoxFit.cover,
              cacheWidth: (screenWidth * dpr).round(),
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: s.surfaceWarm2,
                  child: Center(
                    child: Icon(
                      Icons.image_rounded,
                      size: 64,
                      color: s.stone,
                    ),
                  ),
                );
              },
            ),
            Container(color: s.scrimPhoto),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSliver(BuildContext context) {
    final s = AppTheme.of(context);
    final shot = widget.screenshot;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TypeBadge(type: shot.lamType),
                const Spacer(),
                if (shot.actionCompleted) _statusChip(context),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              shot.summary ?? 'Processing…',
              style: SiftType.serifSummary.copyWith(color: s.ink),
            ),
            if (shot.description != null && shot.description!.isNotEmpty) ...[
              const SizedBox(height: 28),
              _sectionLabel(context, 'What Sift sees'),
              const SizedBox(height: 12),
              Text(
                shot.description!,
                style: SiftType.serifBody.copyWith(color: s.ink),
              ),
              if (shot.recognitions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: shot.recognitions
                      .map((r) => _RecognitionChip(label: r))
                      .toList(),
                ),
              ],
            ],
            if (shot.extractedData != null &&
                shot.extractedData!.isNotEmpty) ...[
              const SizedBox(height: 28),
              _sectionLabel(context, 'Extracted data'),
              const SizedBox(height: 4),
              _hairlineRows(
                context,
                shot.extractedData!.entries
                    .map(
                      (e) => (e.key, _formatExtractedValue(e.value)),
                    )
                    .toList(),
              ),
            ],
            Consumer<ScreenshotProvider>(
              builder: (context, provider, _) {
                if (shot.webResults.isEmpty) {
                  if (provider.localOnly) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: _FindOnlineButton(screenshot: shot),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),
                    _sectionLabel(context, 'Found online'),
                    const SizedBox(height: 12),
                    ...shot.webResults.map((r) => _webResultTile(context, r)),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, 'Tags'),
            const SizedBox(height: 12),
            _TagEditor(screenshot: shot),
            if (shot.ocrText != null && shot.ocrText!.isNotEmpty) ...[
              const SizedBox(height: 28),
              _sectionLabel(context, 'Extracted text'),
              const SizedBox(height: 12),
              _buildOcrBlock(context),
            ],
            const SizedBox(height: 28),
            _sectionLabel(context, 'Details'),
            const SizedBox(height: 4),
            _hairlineRows(
              context,
              [
                ('File', shot.fileName),
                ('Scanned', _formatDate(shot.timestamp)),
                if (shot.lamType != null)
                  ('Type', AppTheme.typeLabel(shot.lamType)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context) {
    final s = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, size: 14, color: s.success),
        const SizedBox(width: 4),
        Text(
          'Completed',
          style: SiftType.metaLabel.copyWith(
            fontWeight: FontWeight.w600,
            color: s.success,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final s = AppTheme.of(context);
    return Text(
      label,
      style: SiftType.chromeTitle.copyWith(color: s.ink),
    );
  }

  Widget _hairlineRows(BuildContext context, List<(String, String)> rows) {
    final s = AppTheme.of(context);

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: s.divider, height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    rows[i].$1,
                    style: SiftType.metaLabel.copyWith(
                      fontWeight: FontWeight.w600,
                      color: s.stone,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: SiftType.bodySans.copyWith(
                      color: s.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOcrBlock(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // In scope since the §2.5 reversal: this was the ONE surface the spec
    // explicitly excluded, on the reasoning that a cast shadow on a read-only
    // mono block "would make the text look broken". That was overridden after a
    // device review. The two mechanical concerns behind it were checked and are
    // fine — the mono face and the truncation are untouched, and the 2pt edge is
    // scored against this block's own fill rather than the page, where the old
    // `divider`-family edges were arithmetically blind.
    //
    // `stone` on `codeBg` is 3.45:1 light and 5.74:1 dark, the tightest row in
    // `SiftBrutal.surfaceEdge` and the reason the edge is a token rather than a
    // per-surface guess. The mono text is unchanged on an unchanged fill:
    // 13.06:1 light and 14.20:1 dark.
    return Container(
      width: double.infinity,
      decoration: brutalEdge(
        fill: s.codeBg,
        isDark: isDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            // The OCR copy button was the last Material button in the app and is
            // now a `BrutalButton.outline`, so it carries the full hard edge and
            // gains keyboard activation, a focus ring and button semantics that
            // the Material `TextButton` was only partly providing. It is the
            // `outline` variant rather than the ghost because a ghost's default
            // `ink` label would measure 1.14:1 on this `codeBg` fill in light
            // mode — the ghost has no fill to lift it, so it cannot be used on
            // a near-black slab at all.
            //
            // Height stays 36 and horizontal padding stays `s12`, matching the
            // `minimumSize: Size(0, 36)` / `EdgeInsets.symmetric(horizontal: 12,
            // vertical: 6)` this button had, so the block does not grow. The
            // label keeps `SiftType.metaLabel` rather than `buttonLabel`: it is
            // meta copy and §9 forbids a typography change. The Material
            // `TextButton` this replaced styled its child with `metaLabel`, so
            // 12pt is the restored size, not a new one — `microLabel` here
            // would have been a silent 1pt reduction. It sets no colour of its
            // own, which is what lets `DefaultTextStyle.merge` supply the
            // per-state label — a `codeText` label would be 1.00:1 on the
            // outline variant's `paper` fill.
            //
            // 12pt/1.3 is 15.6dp, still under the 16dp icon, so the row's
            // `height: 36` box does not grow.
            child: BrutalButton.icon(
              variant: BrutalVariant.outline,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: SiftSpacing.s12),
              onPressed: _copyOcr,
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
              ),
              label: Text(
                _copied ? 'Copied' : 'Copy',
                style: SiftType.metaLabel.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              widget.screenshot.ocrText!,
              style: SiftType.ocrMono.copyWith(color: s.codeText),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyOcr() async {
    await Clipboard.setData(
      ClipboardData(text: widget.screenshot.ocrText ?? ''),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    await Future<void>.delayed(MotionTokens.standard);
    if (mounted) setState(() => _copied = false);
  }

  Widget _webResultTile(BuildContext context, Map<String, String> result) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = result['url'] ?? '';
    final title = result['title'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openUrl(url),
          borderRadius: BorderRadius.circular(SiftRadii.rControl),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: brutalEdge(
              fill: s.paper,
              isDark: isDark,
            ),
            child: Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 20, color: s.graphite),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: SiftType.bodySans.copyWith(
                          fontWeight: FontWeight.w600,
                          color: s.ink,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        url,
                        style: SiftType.metaLabel.copyWith(color: s.stone),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: s.stone),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('Could not open $url');
    } catch (e) {
      debugPrint('Could not open URL: $e');
    }
  }

  Widget _buildBottomBar(BuildContext context, bool isDark) {
    final s = AppTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: s.canvas,
        border: Border(
          top: BorderSide(
            color: s.divider,
            width: AppTheme.hairline(isDark),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              Expanded(child: _buildPrimaryAction(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideRail(BuildContext context, bool isDark) {
    final s = AppTheme.of(context);

    return Container(
      width: _railWidth,
      decoration: BoxDecoration(
        color: s.canvas,
        border: Border(
          left: BorderSide(
            color: s.divider,
            width: AppTheme.hairline(isDark),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPrimaryAction(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    final s = AppTheme.of(context);
    final shot = widget.screenshot;

    if (shot.actionCompleted) {
      return const BrutalButton.icon(
        onPressed: null,
        icon: Icon(Icons.check_rounded, size: 20),
        label: Text('Completed'),
      );
    }

    final actionType = shot.actionType;
    final hasAction = shot.suggestedAction != null &&
        shot.suggestedAction!.isNotEmpty &&
        actionType != null &&
        actionType.isNotEmpty &&
        actionType != 'none';
    if (!hasAction) {
      return const _NoActionLabel();
    }

    final (icon, label) = _actionFor(actionType);
    return BrutalButton.icon(
      onPressed: _running ? () {} : _runAction,
      icon: _running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: s.onAccent,
              ),
            )
          : Icon(icon, size: 20),
      label: Text(_running ? 'Working…' : label),
    );
  }

  Future<void> _runAction() async {
    if (_running) return;
    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    setState(() => _running = true);
    await context
        .read<ScreenshotProvider>()
        .runSuggestedAction(widget.screenshot);
    if (!mounted) return;
    setState(() => _running = false);
  }

  (IconData, String) _actionFor(String? actionType) {
    switch (actionType) {
      case 'create_reminder':
        return (Icons.alarm_rounded, 'Create reminder');
      case 'create_shopping_list':
        return (Icons.shopping_cart_rounded, 'Add to shopping list');
      case 'create_task':
        return (Icons.task_alt_rounded, 'Create task');
      case 'add_calendar':
        return (Icons.event_rounded, 'Add to calendar');
      default:
        return (Icons.bolt_rounded, 'Run action');
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year} at '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatExtractedValue(dynamic value) {
    if (value == null) return '';
    String formatted;
    if (value is String) {
      formatted = value;
    } else if (value is num || value is bool) {
      formatted = value.toString();
    } else if (value is List || value is Map) {
      formatted = jsonEncode(value);
    } else {
      formatted = value.toString();
    }
    if (formatted.length > 200) {
      formatted = '${formatted.substring(0, 200)}…';
    }
    return formatted;
  }
}

/// Quiet, non-interactive label shown in the pinned action bar when a
/// screenshot has no suggested action. Stone meta text, no tap target.
class _NoActionLabel extends StatelessWidget {
  const _NoActionLabel();

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      width: double.infinity,
      height: 40,
      alignment: Alignment.center,
      child: Text(
        'No suggested action',
        style: SiftType.metaLabel.copyWith(
          fontWeight: FontWeight.w500,
          color: s.stone,
        ),
      ),
    );
  }
}

/// 36pt quiet circle that floats on the photo scrim.
class _QuietCircle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _QuietCircle({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: s.scrimPhoto,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color ?? s.codeText),
            ),
          ),
        ),
      ),
    );
  }
}

/// A recognition term from the on-device labeler. Same class as `TypeBadge` and
/// the same [brutalEdge] geometry, hard-edged since the §2.5 reversal — it sits
/// a few lines below `TypeBadge` on this screen, and leaving one of the two a
/// warm 999 pill would have been visibly arbitrary. Not a control: no focus
/// node, no press, and no cast shadow, for the reason `TypeBadge` has none.
class _RecognitionChip extends StatelessWidget {
  final String label;

  const _RecognitionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: brutalEdge(
        fill: s.surfaceWarm1,
        isDark: Theme.of(context).brightness == Brightness.dark,
        shadow: SiftBrutal.none,
      ),
      child: Text(
        label,
        style: SiftType.chipLabel.copyWith(color: s.ink),
      ),
    );
  }
}

class _TagEditor extends StatefulWidget {
  final Screenshot screenshot;

  const _TagEditor({required this.screenshot});

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      _controller.clear();
      return;
    }
    if (MotionTokens.canHaptic) HapticFeedback.selectionClick();
    final ok = await context
        .read<ScreenshotProvider>()
        .addTag(widget.screenshot.id, text);
    if (!mounted) return;
    if (ok) {
      _controller.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t save tag')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.screenshot.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.screenshot.tags
                .map(
                  (tag) => TagChip(
                    label: tag,
                    onDeleted: () {
                      if (MotionTokens.canHaptic) {
                        HapticFeedback.selectionClick();
                      }
                      context
                          .read<ScreenshotProvider>()
                          .removeTag(widget.screenshot.id, tag);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: BrutalField(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  maxLength: 50,
                  onSubmitted: (_) => _submit(),
                  style: SiftType.bodySans.copyWith(color: s.ink),
                  decoration: InputDecoration(
                    hintText: 'Add a tag…',
                    counterText: '',
                    hintStyle: SiftType.bodySans.copyWith(
                      fontSize: 15,
                      color: s.stone,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _AddCircle(onPressed: _submit),
          ],
        ),
      ],
    );
  }
}

/// 40pt accentDeep circle for adding a tag.
class _AddCircle extends StatefulWidget {
  final VoidCallback onPressed;

  const _AddCircle({required this.onPressed});

  @override
  State<_AddCircle> createState() => _AddCircleState();
}

class _AddCircleState extends State<_AddCircle> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (MotionTokens.enabled) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: MotionTokens.press,
        curve: MotionTokens.easeOutCubic,
        child: Container(
          width: SiftSpacing.sendBtn,
          height: SiftSpacing.sendBtn,
          decoration: BoxDecoration(
            color: s.accentDeep,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_rounded, size: 20, color: s.onAccent),
        ),
      ),
    );
  }
}

class _FindOnlineButton extends StatefulWidget {
  final Screenshot screenshot;

  const _FindOnlineButton({required this.screenshot});

  @override
  State<_FindOnlineButton> createState() => _FindOnlineButtonState();
}

class _FindOnlineButtonState extends State<_FindOnlineButton> {
  bool _running = false;

  Future<void> _find() async {
    if (_running) return;
    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    setState(() => _running = true);
    await context.read<ScreenshotProvider>().findOnline(widget.screenshot);
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return BrutalButton.icon(
      variant: BrutalVariant.outline,
      expand: true,
      onPressed: _running ? () {} : _find,
      icon: _running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: s.accent),
            )
          : const Icon(Icons.travel_explore_rounded, size: 20),
      label: const Text('Find online'),
    );
  }
}
