import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/motion_tokens.dart';
import 'sift_mark.dart';

/// Flat, paper-styled about dialog: mark, serif title, version, closing line,
/// hairline rows and the Licenses entry (fonts are OFL-licensed).
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
    final s = AppTheme.of(context);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SiftMark(size: 40),
            const SizedBox(height: 16),
            Text(
              'Sift',
              style: SiftType.serifTitle.copyWith(color: s.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              style: SiftType.metaLabel.copyWith(color: s.stone),
            ),
            const SizedBox(height: 24),
            const _FeatureRow(
              icon: Icons.photo_library_rounded,
              title: 'Capture',
              description: 'Add any screenshot',
            ),
            const _Hairline(),
            const _FeatureRow(
              icon: Icons.visibility_rounded,
              title: 'Understand',
              description: 'Reads and remembers what you save',
            ),
            const _Hairline(),
            const _FeatureRow(
              icon: Icons.task_alt_rounded,
              title: 'Act',
              description: 'Calendar, reminders, shopping lists',
            ),
            const _Hairline(),
            _licenseRow(context, s),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (MotionTokens.canHaptic) HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                },
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenseRow(BuildContext context, SiftColors s) {
    return InkWell(
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'Sift',
        applicationVersion: '1.0.0',
        applicationLegalese: 'Sift and its fonts are open source.',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 20, color: s.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Licenses',
                style: SiftType.bodySans.copyWith(
                  fontWeight: FontWeight.w600,
                  color: s.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: s.stone),
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
    final s = AppTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: s.ink),
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
                ),
                Text(
                  description,
                  style: SiftType.bodySansMd.copyWith(color: s.graphite),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    return Divider(color: s.divider, height: 1, thickness: 1);
  }
}
