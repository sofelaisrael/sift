import 'dart:io';
import 'package:flutter/material.dart';
import '../models/screenshot.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class DetailScreen extends StatelessWidget {
  final Screenshot screenshot;

  const DetailScreen({super.key, required this.screenshot});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = AppTheme.typeColor(screenshot.lamType);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image with app bar
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.black45 : Colors.white70,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black45 : Colors.white70,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share_rounded),
                  onPressed: () {},
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                child: Image.file(
                  File(screenshot.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: typeColor.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.image_rounded,
                        size: 64,
                        color: typeColor,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge and confidence row
                  Row(
                    children: [
                      TypeBadge(type: screenshot.lamType),
                      const Spacer(),
                      if (screenshot.confidence != null)
                        ConfidenceBadge(confidence: screenshot.confidence!),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Summary
                  Text(
                    screenshot.summary ?? 'Processing...',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.3,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // What SIFT sees — deeper scene/context understanding
                  if (screenshot.description != null &&
                      screenshot.description!.isNotEmpty) ...[
                    _buildSectionHeader(context, 'What SIFT sees', Icons.visibility_rounded),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.06),
                            AppTheme.accent.withValues(alpha: 0.04),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        screenshot.description!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    if (screenshot.recognitions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTagChips(screenshot.recognitions, AppTheme.info, Icons.star_rounded),
                    ],
                    if (screenshot.objects.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildTagChips(screenshot.objects, AppTheme.primary, Icons.category_rounded),
                    ],
                    const SizedBox(height: 24),
                  ],

                  // Action card
                  if (screenshot.actionType != null && screenshot.actionType != 'none') ...[
                    _buildActionCard(context, isDark),
                    const SizedBox(height: 24),
                  ],

                  // Extracted text
                  if (screenshot.ocrText != null && screenshot.ocrText!.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Extracted Text', Icons.text_fields_rounded),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
                        ),
                      ),
                      child: SelectableText(
                        screenshot.ocrText!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // File info
                  _buildSectionHeader(context, 'Details', Icons.info_outline_rounded),
                  const SizedBox(height: 12),
                  _buildInfoCard(context, isDark, [
                    _InfoRow('File', screenshot.fileName),
                    _InfoRow('Scanned', _formatDate(screenshot.timestamp)),
                    if (screenshot.lamType != null)
                      _InfoRow('Type', AppTheme.typeLabel(screenshot.lamType)),
                  ]),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, bool isDark) {
    final completed = screenshot.actionCompleted;
    final actionColor = completed ? AppTheme.success : AppTheme.info;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            actionColor.withValues(alpha: 0.08),
            actionColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: actionColor.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              completed ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
              color: actionColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getActionDisplayName(screenshot.actionType!),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: actionColor,
                  ),
                ),
                if (screenshot.actionResult != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    screenshot.actionResult!,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: actionColor.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
        ),
      ],
    );
  }

  Widget _buildTagChips(List<String> tags, Color color, IconData icon) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                tag,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoCard(BuildContext context, bool isDark, List<_InfoRow> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
        ),
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month]} ${date.day}, ${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
}
