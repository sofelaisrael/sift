import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import '../widgets/widgets.dart';
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
            return CustomScrollView(
              slivers: [
                _AskBarDelegateHeader(
                  scrolled: _scrolled,
                  onAsk: widget.onAsk,
                  onCapture: () => _pickScreenshot(context),
                ),
                _buildBrandRow(context, provider),
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
                if (provider.visibleScreenshots.isEmpty)
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

    final groups = <String, List<Screenshot>>{};
    for (final s in provider.visibleScreenshots) {
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
                      onTap: () => _openDetail(context, screenshot),
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
                    onTap: () => _openDetail(context, screenshot),
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

  const _SiftCard({required this.screenshot, required this.onTap});

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
        border: Border.all(color: s.divider),
        boxShadow: SiftElevation.card(isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
                              color:
                                  screenshot.isFavorite ? s.accent : s.codeText,
                            ),
                          ),
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
