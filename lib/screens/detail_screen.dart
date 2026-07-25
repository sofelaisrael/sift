import 'dart:io';
import 'package:flutter/material.dart';
import '../models/screenshot.dart';

class DetailScreen extends StatelessWidget {
  final Screenshot screenshot;

  const DetailScreen({super.key, required this.screenshot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(screenshot.typeEmoji),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Share functionality
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Screenshot preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(screenshot.filePath),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    height: 200,
                    color: Colors.grey[200],
                    child: const Icon(Icons.image, size: 64),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Summary
            Row(
              children: [
                Text(
                  screenshot.typeEmoji,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    screenshot.summary ?? 'Processing...',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Confidence
            if (screenshot.confidence != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: screenshot.confidence! >= 0.7
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      screenshot.confidence! >= 0.7
                          ? Icons.check_circle
                          : Icons.warning,
                      color: screenshot.confidence! >= 0.7
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AI is ${(screenshot.confidence! * 100).toInt()}% confident',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: screenshot.confidence! >= 0.7
                            ? Colors.green[700]
                            : Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Action status
            if (screenshot.actionType != null && screenshot.actionType != 'none') ...[
              Text(
                'Action Taken',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: screenshot.actionCompleted
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      screenshot.actionCompleted
                          ? Icons.check_circle
                          : Icons.pending,
                      color: screenshot.actionCompleted
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getActionDisplayName(screenshot.actionType!),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (screenshot.actionResult != null)
                            Text(
                              screenshot.actionResult!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // OCR Text
            if (screenshot.ocrText != null) ...[
              Text(
                'Extracted Text',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  screenshot.ocrText!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // File info
            Text(
              'File Info',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(context, 'File', screenshot.fileName),
            _buildInfoRow(context, 'Scanned', _formatDate(screenshot.timestamp)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _getActionDisplayName(String actionType) {
    switch (actionType) {
      case 'add_calendar':
        return '📅 Added to Calendar';
      case 'create_reminder':
        return '⏰ Reminder Created';
      case 'create_shopping_list':
        return '🛒 Shopping List Created';
      case 'create_task':
        return '✅ Task Created';
      default:
        return actionType;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
