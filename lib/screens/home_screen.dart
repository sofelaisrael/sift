import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../widgets/bottom_sheet.dart';
import 'detail_screen.dart';
import 'actions_history_screen.dart';

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
          final scrolled = notification.metrics.pixels > 4;
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
                    child:
                        provider.showFavoritesOnly &&
                            provider.screenshots.isNotEmpty
                        ? const _FavoritesEmptyState()
                        : EmptyState(
                            onScan: () => _pickScreenshot(context),
                            onAsk: widget.onAsk,
                          ),
                  )
                else
                  ..._buildGroupSlivers(context, provider),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 96),
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

    final groups = <String, List<Screenshot>>{};
    for (final s in provider.visibleScreenshots) {
      final day = DateTime(s.timestamp.year, s.timestamp.month, s.timestamp.day);
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

    final order = ['Today', 'Yesterday', 'Earlier'];
    final slivers = <Widget>[];
    var cardIndex = 0;
    for (final key in order) {
      final items = groups[key];
      if (items == null || items.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: _TimeGroupHeader(label: key, count: items.length),
        ),
      );
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final screenshot = items[index];
              final i = cardIndex++;
              return _CardEntrance(
                index: i,
                child: _SiftCard(
                  screenshot: screenshot,
                  onTap: () => _openDetail(context, screenshot),
                ),
              );
            },
            childCount: items.length,
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _buildBrandRow(BuildContext context, ScreenshotProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ash = isDark ? AppTheme.ashDark : AppTheme.ashLight;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppTheme.gutter, 16, AppTheme.gutter, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sift',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  Text(
                    'Your screenshots, searchable.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: provider.showFavoritesOnly
                  ? 'Show all'
                  : 'Show pinned only',
              onPressed: () => context
                  .read<ScreenshotProvider>()
                  .setShowFavoritesOnly(!provider.showFavoritesOnly),
              icon: Icon(
                provider.showFavoritesOnly
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                color: provider.showFavoritesOnly
                    ? AppTheme.emberMain
                    : ash,
              ),
            ),
            IconButton(
              onPressed: () => _openActionsHistory(context),
              icon: Icon(
                Icons.history_rounded,
                color: ash,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, ScreenshotProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorColor = isDark ? AppTheme.errorDark : AppTheme.errorLight;

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
          Icon(Icons.error_outline_rounded, size: 20, color: errorColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: errorColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: provider.clearError,
            color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScreenshot(BuildContext context) async {
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
        transitionDuration: Motion.emphasis,
        reverseTransitionDuration: Motion.standard,
        pageBuilder: (context, animation, secondaryAnimation) =>
            DetailScreen(screenshot: screenshot),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
                borderRadius: BorderRadius.circular(AppTheme.r2xl),
                border: Border.all(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
                boxShadow: AppTheme.raisedShadow(isDark),
              ),
              child: Icon(
                Icons.push_pin_rounded,
                size: 36,
                color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'No pinned screenshots yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the pin on any screenshot to keep it here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context
                  .read<ScreenshotProvider>()
                  .setShowFavoritesOnly(false),
              icon: const Icon(Icons.grid_view_rounded, size: 20),
              label: const Text(
                'Show all screenshots',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      delegate: _AskBarDelegate(scrolled: scrolled, onAsk: onAsk, onCapture: onCapture),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isDark
              ? (scrolled ? AppTheme.raisedDark : AppTheme.surfaceDark)
              : (scrolled ? AppTheme.raisedLight : AppTheme.surfaceLight),
          borderRadius: BorderRadius.circular(AppTheme.r2xl),
          border: Border.all(
            color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
          ),
          boxShadow: scrolled ? AppTheme.raisedShadow(isDark) : null,
        ),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAsk,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      border: Border.all(
                        color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ask your memory…',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.emberMain,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCapture,
                child: const SizedBox(
                  width: AppTheme.sendBtn,
                  height: AppTheme.sendBtn,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: AppTheme.emberInk,
                    size: 20,
                  ),
                ),
              ),
            ),
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

class _TimeGroupHeader extends StatelessWidget {
  final String label;
  final int count;

  const _TimeGroupHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ash = isDark ? AppTheme.ashDark : AppTheme.ashLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ash,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(width: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.94, end: 1.0),
            duration: Motion.emphasis,
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.emberMain,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(AppTheme.rXl),
          border: Border.all(
            color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Image.file(
                            File(screenshot.filePath),
                            fit: BoxFit.cover,
                            cacheWidth:
                                (constraints.maxWidth * dpr).round(),
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: isDark
                                    ? AppTheme.surfaceContainerDark
                                    : AppTheme.surfaceContainerLight,
                                child: Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    size: 32,
                                    color: isDark
                                        ? AppTheme.ashDark
                                        : AppTheme.ashLight,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.surfaceDark
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.hairDark
                                : AppTheme.hairLight,
                          ),
                        ),
                        child: Text(
                          _formatTime(screenshot.timestamp),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emberMain,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (Motion.enabled) {
                              HapticFeedback.selectionClick();
                            }
                            context
                                .read<ScreenshotProvider>()
                                .toggleFavorite(screenshot.id);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.surfaceDark
                                  : AppTheme.surfaceLight,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppTheme.hairDark
                                    : AppTheme.hairLight,
                              ),
                            ),
                            child: Icon(
                              screenshot.isFavorite
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 16,
                              color: screenshot.isFavorite
                                  ? AppTheme.emberMain
                                  : (isDark
                                        ? AppTheme.ashDark
                                        : AppTheme.ashLight),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        screenshot.summary ?? 'Processing…',
                        style: Theme.of(context).textTheme.headlineSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      TypeBadge(type: screenshot.lamType),
                      if (screenshot.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
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
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

class _CardEntrance extends StatefulWidget {
  final int index;
  final Widget child;

  const _CardEntrance({required this.index, required this.child});

  @override
  State<_CardEntrance> createState() => _CardEntranceState();
}

class _CardEntranceState extends State<_CardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.emphasis,
    );
    if (Motion.enabled) {
      final delay = Duration(
        milliseconds: (widget.index.clamp(0, 5) * 60),
      );
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final curved = CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        );
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
