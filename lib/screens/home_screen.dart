import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/screenshot_provider.dart';
import '../models/screenshot.dart';
import 'detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScreenSort'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: Consumer<ScreenshotProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.screenshots.isEmpty) {
            return _buildEmptyState(context);
          }

          return _buildScreenshotList(context, provider);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickScreenshot(context),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan Screenshot'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.screenshot_monitor,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No screenshots yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Take a screenshot and let AI understand it\nand take action for you',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _pickScreenshot(context),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Your First Screenshot'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotList(BuildContext context, ScreenshotProvider provider) {
    return CustomScrollView(
      slivers: [
        // Stats bar
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStatChip(
                  context,
                  '${provider.screenshots.length}',
                  'Total',
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  '${provider.screenshots.where((s) => s.actionCompleted).length}',
                  'Actions',
                  Colors.green,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  '${provider.screenshots.where((s) => s.lamType == 'flight').length}',
                  '✈️ Flights',
                  Colors.purple,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  context,
                  '${provider.screenshots.where((s) => s.lamType == 'recipe').length}',
                  '🍳 Recipes',
                  Colors.orange,
                ),
              ],
            ),
          ),
        ),

        // Processing status
        if (provider.processingStatus.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.processingStatus,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: provider.clearStatus,
                  ),
                ],
              ),
            ),
          ),

        // Screenshots list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final screenshot = provider.screenshots[index];
              return _buildScreenshotCard(context, screenshot, provider);
            },
            childCount: provider.screenshots.length,
          ),
        ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildStatChip(BuildContext context, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotCard(BuildContext context, Screenshot screenshot, ScreenshotProvider provider) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetailScreen(screenshot: screenshot),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(screenshot.filePath),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          screenshot.typeEmoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            screenshot.summary ?? 'Processing...',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (screenshot.confidence != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: screenshot.confidence! >= 0.7
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(screenshot.confidence! * 100).toInt()}% sure',
                              style: TextStyle(
                                fontSize: 10,
                                color: screenshot.confidence! >= 0.7
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (screenshot.actionCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '✓ Done',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (screenshot.actionResult != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        screenshot.actionResult!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => provider.deleteScreenshot(screenshot.id),
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickScreenshot(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !context.mounted) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null && context.mounted) {
      final provider = context.read<ScreenshotProvider>();
      await provider.processScreenshot(pickedFile.path);
    }
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About ScreenSort'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Screenshot → AI understands → Takes action',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('ScreenSort uses a Large Action Model (LAM) to:'),
            SizedBox(height: 8),
            Text('• Understand what you\'re looking at'),
            Text('• Extract key information'),
            Text('• Take action (calendar, reminders, shopping lists)'),
            SizedBox(height: 16),
            Text(
              'All processing happens on-device. Your screenshots never leave your phone.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
