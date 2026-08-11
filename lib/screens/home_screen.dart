import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../services/ingest_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/widgets.dart';
import '../widgets/ingest_banner.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/privacy_gate.dart';
import 'detail_screen.dart';
import 'actions_history_screen.dart';

/// The Library tab. Pinned flat Ask bar (field + accent camera circle),
/// wordmark + one quiet sentence, flat banners, time-grouped 16:9 cards,
/// and serif empty states. 2-column grid at >=600pt, 3-column at >=1000pt.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onAsk;

  const HomeScreen({super.key, this.onAsk});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _scrolled = false;
  String? _activeTag;
  final Set<String> _selected = {};
  bool _wasIngesting = false;

  bool get _selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final scrolled = notification.metrics.pixels > 8;
          if (scrolled != _scrolled) {
            setState(() => _scrolled = scrolled);
          }
          return false;
        },
        child: Consumer<ScreenshotProvider>(
          builder: (context, provider, _) {
            final ingest = context.watch<IngestService>();

            // One "finished" toast per pass, fired on the running→done edge.
            if (ingest.isIngesting) {
              _wasIngesting = true;
            } else if (_wasIngesting) {
              _wasIngesting = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Library indexed — ${ingest.processedCount} screenshots remembered',
                      ),
                    ),
                  );
                }
              });
            }

            final filterHasNoHits =
                _activeTag != null && provider.byTag(_activeTag!).isEmpty;

            return Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    _AskBarDelegateHeader(
                      scrolled: _scrolled,
                      onAsk: widget.onAsk,
                      onCapture: () => _pickScreenshot(context),
                    ),
                    _buildBrandRow(context, provider),
                    if (provider.tags.isNotEmpty)
                      _buildTagChips(context, provider),
                    if (ingest.isIngesting)
                      SliverToBoxAdapter(child: IngestBanner(ingest: ingest)),
                    if (provider.processingStatus.isNotEmpty)
                      SliverToBoxAdapter(
                        child: ProcessingBanner(
                          message: provider.processingStatus,
                          onDismiss: provider.clearStatus,
                        ),
                      ),
                    if (provider.error != null)
                      SliverToBoxAdapter(
                        child: _buildErrorBanner(context, provider),
                      ),
                    if (filterHasNoHits)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _TagFilterEmptyState(
                          tag: _activeTag!,
                          onClear: () => setState(() => _activeTag = null),
                        ),
                      )
                    else if (provider.visibleScreenshots.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: provider.showFavoritesOnly &&
                                provider.screenshots.isNotEmpty
                            ? const _FavoritesEmptyState()
                            : EmptyState(
                                onScan: () => _pickScreenshot(context),
                                onAsk: widget.onAsk,
                              ),
                      )
                    else
                      ..._buildGroupSlivers(context, provider),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
                if (_selecting)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: _buildBatchBar(context),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildGroupSlivers(
    BuildContext context,
    ScreenshotProvider provider,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final source = _activeTag == null
        ? provider.visibleScreenshots
        : provider.byTag(_activeTag!);

    final groups = <String, List<Screenshot>>{};
    for (final s in source) {
      final day =
          DateTime(s.timestamp.year, s.timestamp.month, s.timestamp.day);
      String key;
      if (day == today) {
        key = 'Today';
      } else if (day == yesterday) {
        key = 'Yesterday';
      } else {
        key = 'Earlier';
      }
      groups.putIfAbsent(key, () => []).add(s);
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 3 : (width >= 600 ? 2 : 1);

    final order = ['Today', 'Yesterday', 'Earlier'];
    final slivers = <Widget>[];
    for (final key in order) {
      final items = groups[key];
      if (items == null || items.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(child: _TimeGroupHeader(label: key)),
      );
      if (columns == 1) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final screenshot = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SiftCard(
                      screenshot: screenshot,
                      selecting: _selecting,
                      selected: _selected.contains(screenshot.id),
                      onTap: () => _onCardTap(context, screenshot),
                      onLongPress: _selecting
                          ? null
                          : () => _startSelection(screenshot),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        );
      } else {
        final cardWidth =
            (width - 40 - SiftSpacing.s12 * (columns - 1)) / columns;
        final imageHeight = cardWidth * 9 / 16;
        final mainAxisExtent = imageHeight + 150;
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: SiftSpacing.s12,
                crossAxisSpacing: SiftSpacing.s12,
                mainAxisExtent: mainAxisExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final screenshot = items[index];
                  return _SiftCard(
                    screenshot: screenshot,
                    selecting: _selecting,
                    selected: _selected.contains(screenshot.id),
                    onTap: () => _onCardTap(context, screenshot),
                    onLongPress: _selecting
                        ? null
                        : () => _startSelection(screenshot),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        );
      }
    }
    return slivers;
  }

  Widget _buildBrandRow(BuildContext context, ScreenshotProvider provider) {
    final s = AppTheme.of(context);
    final count = provider.screenshots.length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sift',
                    style: SiftType.serifTitle.copyWith(color: s.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count == 1
                        ? '1 screenshot remembered'
                        : '$count screenshots remembered',
                    style: SiftType.bodySansMd.copyWith(
                      color: s.graphite,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip:
                  provider.showFavoritesOnly ? 'Show all' : 'Show pinned only',
              onPressed: () {
                if (MotionTokens.canHaptic) HapticFeedback.lightImpact();
                context
                    .read<ScreenshotProvider>()
                    .setShowFavoritesOnly(!provider.showFavoritesOnly);
              },
              icon: Icon(
                provider.showFavoritesOnly
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                color: provider.showFavoritesOnly ? s.accent : s.stone,
              ),
            ),
            IconButton(
              tooltip: 'Actions history',
              onPressed: () => _openActionsHistory(context),
              icon: Icon(Icons.history_rounded, color: s.stone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, ScreenshotProvider provider) {
    final s = AppTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s.errorSoft,
        borderRadius: BorderRadius.circular(SiftRadii.rThumb),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: s.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.error!,
              style: SiftType.bodySansMd.copyWith(
                color: s.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: provider.clearError,
            color: s.stone,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScreenshot(BuildContext context) async {
    final ok = await showPrivacyConsentIfNeeded(context);
    if (!ok || !context.mounted) return;

    PremiumBottomSheet.show(
      context,
      onCamera: () async {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: ImageSource.camera);
        if (pickedFile != null && context.mounted) {
          final provider = context.read<ScreenshotProvider>();
          await provider.processScreenshot(pickedFile.path);
        }
      },
      onGallery: () async {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: ImageSource.gallery);
        if (pickedFile != null && context.mounted) {
          final provider = context.read<ScreenshotProvider>();
          await provider.processScreenshot(pickedFile.path);
        }
      },
    );
  }

  void _openActionsHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActionsHistoryScreen()),
    );
  }

  void _openDetail(BuildContext context, Screenshot screenshot) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: MotionTokens.emphasis,
        reverseTransitionDuration: MotionTokens.standard,
        pageBuilder: (context, animation, secondaryAnimation) =>
            DetailScreen(screenshot: screenshot),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: MotionTokens.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _onCardTap(BuildContext context, Screenshot screenshot) {
    if (_selecting) {
      setState(() {
        if (_selected.contains(screenshot.id)) {
          _selected.remove(screenshot.id);
        } else {
          _selected.add(screenshot.id);
        }
      });
      return;
    }
    _openDetail(context, screenshot);
  }

  void _startSelection(Screenshot screenshot) {
    if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
    setState(() => _selected.add(screenshot.id));
  }

  Widget _buildTagChips(
    BuildContext context,
    ScreenshotProvider provider,
  ) {
    final tags = provider.tags.toList()..sort();

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            _filterChip(
              context,
              label: 'All',
              active: _activeTag == null,
              onTap: () {
                if (_activeTag != null) setState(() => _activeTag = null);
              },
            ),
            for (final tag in tags) ...[
              const SizedBox(width: 8),
              _filterChip(
                context,
                label: tag,
                active: _activeTag == tag,
                onTap: () {
                  setState(() {
                    _activeTag = _activeTag == tag ? null : tag;
                    _selected.clear();
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (MotionTokens.canHaptic) HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: MotionTokens.standard,
            curve: MotionTokens.easeOutCubic,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? s.accentSoft : s.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? s.accent : s.divider,
                width: active ? 1 : AppTheme.hairline(isDark),
              ),
            ),
            child: Text(
              label,
              style: SiftType.chipLabel.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? s.accentDeep : s.tagText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBatchBar(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: BorderRadius.circular(SiftRadii.rField),
        border: Border.all(
          color: s.divider,
          width: AppTheme.hairline(isDark),
        ),
        boxShadow: isDark ? SiftElevation.l4Dark : SiftElevation.l3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                _selected.length == 1
                    ? '1 selected'
                    : '${_selected.length} selected',
                style: SiftType.bodySansMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: s.ink,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(_selected.clear),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _batchHide(context),
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Hide'),
          ),
        ],
      ),
    );
  }

  Future<void> _batchHide(BuildContext context) async {
    final provider = context.read<ScreenshotProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;
    for (final id in List.of(_selected)) {
      final matches = provider.screenshots.where((s) => s.id == id);
      if (matches.isNotEmpty) {
        await provider.hideScreenshot(matches.first.filePath);
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? 'Hidden 1 screenshot from Sift'
              : 'Hidden $count screenshots from Sift',
        ),
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.push_pin_outlined, size: 40, color: s.stone),
            const SizedBox(height: 28),
            Text(
              'No pinned screenshots yet',
              textAlign: TextAlign.center,
              style: SiftType.serifDisplay.copyWith(color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the pin on any screenshot to keep it here.',
              textAlign: TextAlign.center,
              style: SiftType.bodySans.copyWith(
                color: s.graphite,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => context
                  .read<ScreenshotProvider>()
                  .setShowFavoritesOnly(false),
              child: const Text('Show all screenshots'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tag filter with no matches: quiet label-off state with a "Show all" exit.
class _TagFilterEmptyState extends StatelessWidget {
  final String tag;
  final VoidCallback onClear;

  const _TagFilterEmptyState({required this.tag, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_off_outlined, size: 40, color: s.stone),
            const SizedBox(height: 28),
            Text(
              'Nothing tagged "$tag"',
              textAlign: TextAlign.center,
              style: SiftType.serifDisplay.copyWith(color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Screenshots carrying this tag will appear here.',
              textAlign: TextAlign.center,
              style: SiftType.bodySans.copyWith(
                color: s.graphite,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: onClear,
              child: const Text('Show all screenshots'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned flat Ask bar: paper field (r16, hairline) + accentDeep camera
/// circle. Lifts a warm shadow once the user scrolls past 8px.
class _AskBarDelegateHeader extends StatelessWidget {
  final bool scrolled;
  final VoidCallback? onAsk;
  final VoidCallback onCapture;

  const _AskBarDelegateHeader({
    required this.scrolled,
    required this.onAsk,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _AskBarDelegate(
          scrolled: scrolled, onAsk: onAsk, onCapture: onCapture),
    );
  }
}

class _AskBarDelegate extends SliverPersistentHeaderDelegate {
  final bool scrolled;
  final VoidCallback? onAsk;
  final VoidCallback onCapture;

  _AskBarDelegate({
    required this.scrolled,
    required this.onAsk,
    required this.onCapture,
  });

  @override
  double get minExtent => 76;

  @override
  double get maxExtent => 76;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: MotionTokens.easeOutCubic,
        decoration: BoxDecoration(
          color: s.paper,
          borderRadius: BorderRadius.circular(SiftRadii.rField),
          border: Border.all(
            color: s.divider,
            width: AppTheme.hairline(isDark),
          ),
          boxShadow: scrolled && !isDark ? SiftElevation.l2 : null,
        ),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAsk,
                  borderRadius: BorderRadius.circular(SiftRadii.rField),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: s.paper,
                      borderRadius: BorderRadius.circular(SiftRadii.rField),
                      border: Border.all(
                        color: s.divider,
                        width: AppTheme.hairline(isDark),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: s.stone,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ask about anything you\'ve saved…',
                          style: SiftType.bodySans.copyWith(
                            fontSize: 15,
                            color: s.stone,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _CameraCircle(onTap: onCapture),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AskBarDelegate oldDelegate) {
    return oldDelegate.scrolled != scrolled ||
        oldDelegate.onAsk != onAsk ||
        oldDelegate.onCapture != onCapture;
  }
}

/// 40pt accentDeep camera circle — the only capture affordance (no FAB).
class _CameraCircle extends StatefulWidget {
  final VoidCallback onTap;

  const _CameraCircle({required this.onTap});

  @override
  State<_CameraCircle> createState() => _CameraCircleState();
}

class _CameraCircleState extends State<_CameraCircle> {
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
        if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
        widget.onTap();
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
          child: Icon(Icons.camera_alt_rounded, size: 20, color: s.onAccent),
        ),
      ),
    );
  }
}

class _TimeGroupHeader extends StatelessWidget {
  final String label;

  const _TimeGroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label,
        style: SiftType.microLabel.copyWith(
          color: s.stone,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SiftCard extends StatelessWidget {
  final Screenshot screenshot;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  const _SiftCard({
    required this.screenshot,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: BorderRadius.circular(SiftRadii.rCard),
        border: Border.all(
          color: selecting && selected ? s.accent : s.divider,
          width: selecting && selected ? 1.5 : 1,
        ),
        boxShadow: SiftElevation.card(isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Image.file(
                          File(screenshot.filePath),
                          fit: BoxFit.cover,
                          cacheWidth: (constraints.maxWidth * dpr).round(),
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: s.surfaceWarm2,
                              child: Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 32,
                                  color: s.stone,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Container(color: s.scrimPhoto),
                    if (selecting && !selected)
                      Container(color: s.barrier),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: s.scrimPhoto,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _formatTime(screenshot.timestamp),
                          style: SiftType.microLabel.copyWith(
                            fontWeight: FontWeight.w600,
                            color: s.codeText,
                          ),
                        ),
                      ),
                    ),
                    if (!selecting)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              if (MotionTokens.canHaptic) {
                                HapticFeedback.selectionClick();
                              }
                              context
                                  .read<ScreenshotProvider>()
                                  .toggleFavorite(screenshot.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: s.scrimPhoto,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                screenshot.isFavorite
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                size: 16,
                                color: screenshot.isFavorite
                                    ? s.accent
                                    : s.codeText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selecting && selected)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: s.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: s.onAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      screenshot.summary ?? 'Processing…',
                      style: SiftType.serifSummary.copyWith(color: s.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TypeBadge(type: screenshot.lamType, compact: true),
                        if (screenshot.tags.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...screenshot.tags.take(3).map(
                                      (tag) => TagChip(
                                        label: tag,
                                        compact: true,
                                      ),
                                    ),
                                if (screenshot.tags.length > 3)
                                  TagChip(
                                    label: '+${screenshot.tags.length - 3}',
                                    compact: true,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
