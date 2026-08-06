import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'sift_mark.dart';

/// Flat, porcelain-styled about dialog with the Sift mark. No sparkles,
/// no emoji, no colored wells.
class PremiumAboutDialog extends StatelessWidget {
  const PremiumAboutDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const PremiumAboutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.r2xl),
      ),
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SiftMark(size: 40),
            const SizedBox(height: 16),
            Text(
              'Sift',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                  ),
            ),
            const SizedBox(height: 24),
            const _FeatureRow(
              icon: Icons.photo_library_rounded,
              title: 'Capture',
              description: 'Take or pick any screenshot',
            ),
            const SizedBox(height: 12),
            const _FeatureRow(
              icon: Icons.visibility_rounded,
              title: 'Understand',
              description: 'Reads and comprehends what you save',
            ),
            const SizedBox(height: 12),
            const _FeatureRow(
              icon: Icons.task_alt_rounded,
              title: 'Act',
              description: 'Calendar, reminders, shopping lists',
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your screenshots stay on your device. You stay in control.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? AppTheme.inkDark : AppTheme.inkLight,
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
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
