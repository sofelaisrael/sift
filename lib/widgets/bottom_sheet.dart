import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Capture source picker. Porcelain tiles, neutral icons, no tinted wells.
class PremiumBottomSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const PremiumBottomSheet({
    super.key,
    required this.onCamera,
    required this.onGallery,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onCamera,
    required VoidCallback onGallery,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PremiumBottomSheet(
        onCamera: onCamera,
        onGallery: onGallery,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.raisedDark : AppTheme.raisedLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.r2xl)),
        border: Border(
          top: BorderSide(color: isDark ? AppTheme.hairDark : AppTheme.hairLight),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add Screenshot',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Take a photo or pick from your library',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.slateDark : AppTheme.slateLight,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SourceOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      subtitle: 'Take a photo',
                      onTap: () {
                        Navigator.pop(context);
                        onCamera();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      subtitle: 'Pick from library',
                      onTap: () {
                        Navigator.pop(context);
                        onGallery();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(AppTheme.rXl),
            border: Border.all(
              color: isDark ? AppTheme.hairDark : AppTheme.hairLight,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: isDark ? AppTheme.inkDark : AppTheme.inkLight,
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.ashDark : AppTheme.ashLight,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
