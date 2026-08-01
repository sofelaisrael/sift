import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/screenshot_provider.dart';
import '../models/screenshot.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../widgets/bottom_sheet.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';
import 'actions_history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<ScreenshotProvider>(
          builder: (context, provider, _) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(context),
                ),
                if (provider.screenshots.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildStats(context, provider),
                  ),
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
                if (provider.screenshots.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateHolder(),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Text(
                        'Recent',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final screenshot = provider.screenshots[index];
                        return ScreenshotCard(
                          screenshot: screenshot,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(screenshot: screenshot),
                            ),
                          ),
                          onDelete: () => provider.deleteScreenshot(screenshot.id),
                        );
                      },
                      childCount: provider.screenshots.length,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: 120),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickScreenshot(context),
        icon: const Icon(Icons.camera_alt_rounded, size: 20),
        label: const Text(
          'Scan',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ScreenSort',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                ),
                Text(
                  'AI-powered screenshot actions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openActionsHistory(context),
            icon: Icon(
              Icons.history_rounded,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: Icon(
              Icons.settings_rounded,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, ScreenshotProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          StatCard(
            value: '${provider.screenshots.length}',
            label: 'Total',
            color: AppTheme.primary,
            icon: Icons.screenshot_rounded,
          ),
          const SizedBox(width: 8),
          StatCard(
            value: '${provider.screenshots.where((s) => s.actionCompleted).length}',
            label: 'Actions',
            color: AppTheme.success,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 8),
          StatCard(
            value: '${provider.screenshots.where((s) => s.lamType == 'flight').length}',
            label: 'Flights',
            color: AppTheme.info,
            icon: Icons.flight_rounded,
          ),
          const SizedBox(width: 8),
          StatCard(
            value: '${provider.screenshots.where((s) => s.lamType == 'recipe').length}',
            label: 'Recipes',
            color: AppTheme.error,
            icon: Icons.restaurant_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, ScreenshotProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 20, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.error!,
              style: const TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: provider.clearError,
            color: AppTheme.error,
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

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openActionsHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActionsHistoryScreen()),
    );
  }
}

class EmptyStateHolder extends StatelessWidget {
  const EmptyStateHolder({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      onScan: () async {
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
      },
    );
  }
}

class ScreenshotCard extends StatelessWidget {
  final Screenshot screenshot;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ScreenshotCard({
    super.key,
    required this.screenshot,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(screenshot.filePath),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.typeColorLight(screenshot.lamType),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.image_rounded,
                          color: AppTheme.typeColor(screenshot.lamType),
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        screenshot.summary ?? 'Processing...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TypeBadge(type: screenshot.lamType, compact: true),
                          const SizedBox(width: 6),
                          if (screenshot.confidence != null)
                            ConfidenceBadge(confidence: screenshot.confidence!),
                          const SizedBox(width: 6),
                          if (screenshot.actionCompleted)
                            ActionBadge(
                              actionType: screenshot.actionType,
                              completed: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white24 : Colors.black26,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
