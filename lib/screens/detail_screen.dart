import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/screenshot.dart';
import '../providers/screenshot_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class DetailScreen extends StatelessWidget {
  final Screenshot screenshot;

  const DetailScreen({super.key, required this.screenshot});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            stretch: true,
            backgroundColor: isDark ? AppTheme.bgDark : AppTheme.bgLight,
            leading: _circleButton(
              context,
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
            ),
            actions: [
              Consumer<ScreenshotProvider>(
                builder: (context, provider, _) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        _circleButton(
                          context,
                          icon: screenshot.isFavorite
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: screenshot.isFavorite
                              ? AppTheme.emberMain
                              : (isDark
                                    ? AppTheme.ashDark
                                    : AppTheme.ashLight),
                          onTap: () {
                            if (Motion.enabled) HapticFeedback.mediumImpact();
                            context
                                .read<ScreenshotProvider>()
                                .toggleFavorite(screenshot.id);
                          },
                        ),
                        _circleButton(
                          context,
                          icon: Icons.share_rounded,
                          onTap: () {
                            if (Motion.enabled) HapticFeedback.mediumImpact();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Image.file(
                File(screenshot.filePath),
                fit: BoxFit.cover,
                cacheWidth: (screenWidth * dpr).round(),
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: scheme.surfaceContainer,
                    child: Center(
                      child: Icon(
                        Icons.image_rounded,
                        size: 64,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Consumer<ScreenshotProvider>(
                    builder: (context, provider, _) {
                      return Row(
                        children: [
                          TypeBadge(type: screenshot.lamType),
                          const Spacer(),
                          if (screenshot.actionCompleted)
                            _actionStatus(context),
                        ],
                      );
                    },
                  ),
                  if (screenshot.actionType != null &&
                      screenshot.actionType != 'none') ...[
                    const SizedBox(height: 16),
                    Consumer<ScreenshotProvider>(
                      builder: (context, provider, _) {
                        if (provider.localOnly) {
                          return const SizedBox.shrink();
                        }
                        return _ManualActionButton(
                          screenshot: screenshot,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    screenshot.summary ?? 'Processing…',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          height: 1.1,
                        ),
                  ),
                  if (screenshot.description != null &&
                      screenshot.description!.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'What SIFT sees',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppTheme.rXl),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            screenshot.description!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (screenshot.recognitions.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: screenshot.recognitions
                                  .map((r) => _neutralChip(context, r))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Consumer<ScreenshotProvider>(
                    builder: (context, provider, _) {
                      if (screenshot.webResults.isEmpty) {
                        if (provider.localOnly) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: _FindOnlineButton(screenshot: screenshot),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 28),
                          Text(
                            'Found online',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          ...screenshot.webResults
                              .map((r) => _webResultTile(context, r)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  _TagEditor(screenshot: screenshot),
                  if (screenshot.ocrText != null &&
                      screenshot.ocrText!.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Extracted Text',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(AppTheme.rXl),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: SelectableText(
                        screenshot.ocrText!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.6,
                          color: isDark ? AppTheme.inkDark : AppTheme.inkLight,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Details',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(context, [
                    _InfoRow('File', screenshot.fileName),
                    _InfoRow('Scanned', _formatDate(screenshot.timestamp)),
                    if (screenshot.lamType != null)
                      _InfoRow('Type', AppTheme.typeLabel(screenshot.lamType)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  Widget _circleButton(BuildContext context,
      {required IconData icon, required VoidCallback onTap, Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IconButton(
        icon: Icon(icon, size: 22),
        onPressed: onTap,
        color: color ?? (isDark ? AppTheme.inkDark : AppTheme.inkLight),
      ),
    );
  }

  Widget _actionStatus(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(
          color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_rounded,
            size: 14,
            color: isDark ? AppTheme.successDark : AppTheme.successLight,
          ),
          const SizedBox(width: 4),
          Text(
            'Completed',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.successDark : AppTheme.successLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _neutralChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.tagFillDark : AppTheme.tagFillLight,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.tagTextDark : AppTheme.tagTextLight,
            ),
      ),
    );
  }

  Widget _webResultTile(BuildContext context, Map<String, String> result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = result['url'] ?? '';
    final title = result['title'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openUrl(url),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: Container(
            width: double.infinity,
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
                Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        url,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                ),
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
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) debugPrint('Could not open $url');
    } catch (e) {
      debugPrint('Could not open URL: $e');
    }
  }

  Widget _buildInfoCard(BuildContext context, List<_InfoRow> rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    row.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
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

  Widget _buildActionBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, label) = _action(screenshot.actionType);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (Motion.enabled) HapticFeedback.mediumImpact();
                  },
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  if (Motion.enabled) HapticFeedback.mediumImpact();
                },
                child: const Text('Share'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String) _action(String? actionType) {
    switch (actionType) {
      case 'create_reminder':
        return (Icons.alarm_rounded, 'Create Reminder');
      case 'create_shopping_list':
        return (Icons.shopping_cart_rounded, 'Add to Shopping List');
      case 'create_task':
        return (Icons.task_alt_rounded, 'Create Task');
      case 'add_calendar':
        return (Icons.event_rounded, 'Add to Calendar');
      default:
        return (Icons.event_rounded, 'Add to Calendar');
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month]} ${date.day}, ${date.year} at '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
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
    if (Motion.enabled) HapticFeedback.selectionClick();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer<ScreenshotProvider>(
          builder: (context, provider, _) {
            if (widget.screenshot.tags.isEmpty) {
              return const SizedBox.shrink();
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.screenshot.tags
                  .map(
                    (tag) => TagChip(
                      label: tag,
                      onDeleted: () {
                        if (Motion.enabled) {
                          HapticFeedback.selectionClick();
                        }
                        context
                            .read<ScreenshotProvider>()
                            .removeTag(widget.screenshot.id, tag);
                      },
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(
                    color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  maxLength: 50,
                  onSubmitted: (_) => _submit(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Add a tag…',
                    counterText: '',
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
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
            _TagAddButton(onPressed: _submit),
          ],
        ),
      ],
    );
  }
}

class _TagAddButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _TagAddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.emberMain,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.add_rounded,
            color: AppTheme.emberInk,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ManualActionButton extends StatefulWidget {
  final Screenshot screenshot;

  const _ManualActionButton({required this.screenshot});

  @override
  State<_ManualActionButton> createState() => _ManualActionButtonState();
}

class _ManualActionButtonState extends State<_ManualActionButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    if (Motion.enabled) HapticFeedback.mediumImpact();
    setState(() => _running = true);
    await context
        .read<ScreenshotProvider>()
        .runSuggestedAction(widget.screenshot);
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_actionIcon(widget.screenshot.actionType), size: 20),
            label: Text(_actionLabel(widget.screenshot.actionType)),
          ),
        ),
        if (widget.screenshot.actionResult != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.screenshot.actionResult!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                ),
          ),
        ],
      ],
    );
  }

  String _actionLabel(String? type) {
    switch (type) {
      case 'add_calendar':
        return 'Add to Calendar';
      case 'create_reminder':
        return 'Create reminder';
      case 'create_shopping_list':
        return 'Add to shopping list';
      case 'create_task':
        return 'Create task';
      default:
        return 'Run action';
    }
  }

  IconData _actionIcon(String? type) {
    switch (type) {
      case 'add_calendar':
        return Icons.event_rounded;
      case 'create_reminder':
        return Icons.alarm_rounded;
      case 'create_shopping_list':
        return Icons.shopping_cart_rounded;
      case 'create_task':
        return Icons.task_alt_rounded;
      default:
        return Icons.bolt_rounded;
    }
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
    if (Motion.enabled) HapticFeedback.mediumImpact();
    setState(() => _running = true);
    await context
        .read<ScreenshotProvider>()
        .findOnline(widget.screenshot);
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _running ? null : _find,
        icon: _running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore_rounded, size: 20),
        label: const Text('Find online'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTheme.btnH),
          foregroundColor: isDark ? AppTheme.inkDark : AppTheme.inkLight,
          side: BorderSide(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
          ),
        ),
      ),
    );
  }
}
