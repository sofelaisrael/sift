import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../theme/motion_tokens.dart';
import 'brutal_activate.dart';

/// Capture source picker. Paper sheet, neutral icons, no tinted wells.
///
/// The SHEET is not a control, so its chrome keeps `rSheet` and the soft L4
/// shadow and is deliberately outside the brutal set (DESIGN-BRUTALIST.md
/// §2.5, §8 Phase 4). The two source tiles inside it are, and carry the hard
/// edge.
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

class _SourceOption extends StatefulWidget {
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
  State<_SourceOption> createState() => _SourceOptionState();
}

class _SourceOptionState extends State<_SourceOption> {
  bool _pressed = false;
  bool _focused = false;

  void _setFocused(bool value) {
    if (value == _focused) return;
    setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // One of the two contents the spec promotes (§8 Phase 4): the sheet chrome
    // around it stays rSheet 24 with its soft L4 shadow, because a sheet is a
    // container, not a control (§2.5). What the user actually touches inside it
    // gets the full treatment — 2pt stone border, rControl, hard shadow, press.
    //
    // This is a control on a paper sheet, so the fill stays `paper`: the
    // selected and disabled fills in §4.6 belong to chips, and a source picker
    // has no selected state.
    //
    // Focus is not optional. A modal sheet traps traversal, so a source option
    // with no `Focus` leaves the sheet with ZERO focusable children: a keyboard
    // user opens the capture sheet and is stuck. The ring replaces the stone
    // border in place, exactly as on the chip and the button (§5.4), and
    // [brutalActivate] is what makes Enter and Space actually do something.
    return Semantics(
      button: true,
      child: brutalActivate(
        onActivate: widget.onTap,
        child: Focus(
          onFocusChange: _setFocused,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: Transform.translate(
                offset: _pressed && MotionTokens.enabled
                    ? SiftBrutal.offset
                    : Offset.zero,
                child: AnimatedContainer(
                  duration: _pressed ? SiftBrutal.pressIn : SiftBrutal.pressOut,
                  curve: MotionTokens.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: s.paper,
                    borderRadius: BorderRadius.circular(SiftRadii.rControl),
                    border: Border.all(
                      color: _focused ? SiftBrutal.focus(isDark) : s.stone,
                      width: SiftBrutal.borderW,
                    ),
                    boxShadow: _pressed
                        ? SiftBrutal.hardPressed(isDark)
                        : SiftBrutal.hard(isDark),
                  ),
                  child: Column(
                    children: [
                      Icon(widget.icon, size: 28, color: s.ink),
                      const SizedBox(height: 12),
                      Text(
                        widget.label,
                        style: SiftType.bodySans.copyWith(
                          fontWeight: FontWeight.w600,
                          color: s.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: SiftType.metaLabel.copyWith(color: s.stone),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
