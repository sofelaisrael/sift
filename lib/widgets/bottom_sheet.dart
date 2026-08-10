import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Capture source picker. Paper tiles, neutral icons, no tinted wells.
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
    final s = AppTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: s.paper,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SiftRadii.rSheet),
        ),
        boxShadow: SiftElevation.sheet(
          Theme.of(context).brightness == Brightness.dark,
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
                  color: s.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add a screenshot',
                  style: SiftType.serifHeadline.copyWith(color: s.ink),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Take a photo or pick from your library',
                  style: SiftType.bodySansMd.copyWith(color: s.graphite),
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
    final s = AppTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SiftRadii.rCard),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: s.paper,
            borderRadius: BorderRadius.circular(SiftRadii.rCard),
            border: Border.all(color: s.divider),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: s.ink),
              const SizedBox(height: 12),
              Text(
                label,
                style: SiftType.bodySans.copyWith(
                  fontWeight: FontWeight.w600,
                  color: s.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: SiftType.metaLabel.copyWith(color: s.stone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
