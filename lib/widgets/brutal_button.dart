import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../theme/motion_tokens.dart';
import 'brutal_activate.dart';

/// Visual weight of a brutal control. Exactly one surface per state table in
/// DESIGN-BRUTALIST.md §4.
enum BrutalVariant { filled, outline, text, destructive }

/// The app's one button.
///
/// SIFT's Material buttons cannot express this design: a [ButtonStyle] has no
/// `boxShadow` and no transform, and Material's `elevation` always blurs
/// (DESIGN-BRUTALIST.md §5.1). So the hard edge — a 2pt border plus a
/// down-right offset shadow — has to be painted and moved by hand.
///
/// A press is three independent signals, not one: the control translates
/// down-right by [SiftBrutal.offset] exactly as far as its own shadow, the
/// shadow collapses to nothing, and the fill inverts. Under reduced motion the
/// first two become instant or disappear, and the fill inversion is a 0ms
/// colour swap, so the press still reads with no motion at all (§6.6).
///
/// Every state is resolved from [SiftBrutal] and [SiftColors]; there is no
/// per-component colour or offset anywhere in this file, because two hard-edge
/// directions in one app reads as a rendering fault (§6.3).
class BrutalButton extends StatefulWidget {
  final BrutalVariant variant;

  /// Null disables the control: no press state, no tap, and it announces as
  /// disabled rather than merely looking dimmed.
  final VoidCallback? onPressed;

  /// The label. A `Text` with no style of its own inherits the per-state label
  /// colour; one that sets its own keeps it, exactly as it did under the
  /// Material themes.
  final Widget child;

  /// Optional leading icon. Null leaves the layout identical, and the icon
  /// inherits the label colour so it inverts with it.
  final Widget? icon;

  /// Total height INCLUDING the 2pt border, so the 48dp pointer target is
  /// never eaten by the decoration.
  final double height;

  final EdgeInsetsGeometry? padding;

  /// Accessible name override, for the icon-only shapes. When null the label
  /// text supplies the name.
  final String? semanticLabel;

  /// True fills the incoming width. Replaces the `SizedBox(width: infinity)`
  /// wrapper the three full-width call sites used.
  final bool expand;

  const BrutalButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = BrutalVariant.filled,
    this.icon,
    this.height = SiftSpacing.btnH,
    this.padding,
    this.semanticLabel,
    this.expand = false,
  });

  const BrutalButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.variant = BrutalVariant.filled,
    this.height = SiftSpacing.btnH,
    this.padding,
    this.semanticLabel,
    this.expand = false,
  }) : child = label;

  /// A ghost button. It is 40dp to match the `textButtonTheme` minimum the 12
  /// ghost call sites already occupy, and it carries NO hard shadow: a
  /// down-right offset needs a silhouette to cast from, and giving a quiet
  /// secondary action a fill to cast one would promote it to primary weight
  /// (§4.3). For the same reason it does not translate on press — the
  /// translate exists to land the control on its own shadow, and there is no
  /// shadow to land on.
  const BrutalButton.text({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.height = SiftSpacing.s40,
    this.padding,
    this.semanticLabel,
    this.expand = false,
  })  : variant = BrutalVariant.text,
        child = label;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  bool _pressed = false;
  bool _focused = false;

  bool get _disabled => widget.onPressed == null;

  bool get _ghost => widget.variant == BrutalVariant.text;

  void _setPressed(bool value) {
    if (value == _pressed) return;
    setState(() => _pressed = value);
  }

  void _setFocused(bool value) {
    if (value == _focused) return;
    setState(() => _focused = value);
  }

  /// Pressed is a full inversion, never a tint. The Material press fill was
  /// `accentPressed`, which sits at 3.98:1 under the label and fails SC 1.4.3
  /// — inverting to ink/canvas is 14.28:1 and costs no extra colour (§4.1).
  Color _fill(SiftColors s, bool isDark) {
    if (_disabled) {
      return widget.variant == BrutalVariant.outline ? s.paper : s.surfaceWarm2;
    }
    switch (widget.variant) {
      case BrutalVariant.filled:
        if (_pressed) return isDark ? s.canvas : s.ink;
        return isDark ? s.ink : s.accentDeep;
      case BrutalVariant.destructive:
        if (_pressed) return isDark ? s.canvas : s.ink;
        return s.error;
      case BrutalVariant.outline:
        if (_pressed) return isDark ? s.surfaceWarm2 : s.surfaceWarm1;
        return s.paper;
      case BrutalVariant.text:
        // The pressed fill is what the label is DRAWN ON, so unlike the hard
        // shadow it is NOT fill-agnostic (§1) — the fill-agnostic argument only
        // covers an edge whose near side is hidden by its own offset. §7.1
        // originally scored this row against `canvas`, which is not what gets
        // painted, and every number below is recomputed against the real fill.
        //
        // Two label colours reach this state, because a `Text` that sets its own
        // style keeps it: `accentDeep`/`ink` by default, and `stone` at the two
        // sites that dim their label (onboarding 'Skip', widgets.dart 'Ask your
        // memory instead'). Both are `buttonLabel` 15pt/600, so both owe 4.5:1
        // and both are asserted in the test rather than reasoned about here.
        // Operands below are `L + 0.05`, not raw luminance — the ratio is
        // (L_lighter + 0.05) / (L_darker + 0.05).
        //
        // LIGHT: `canvas`, and the arithmetic says it is the only option there
        // is. The binding label is `stone` (L + 0.05 = 0.21153), so a 4.5:1
        // fill needs L + 0.05 >= 0.95186 — and the only palette steps in light
        // that reach it are `paper`/`onAccent` (0.99792) and `canvas`
        // (0.95772), which sit 1.00:1 and 1.04:1 from the two surfaces this
        // button is ever mounted on. A fill cannot be both 4.5:1-safe and
        // visible on `canvas` AND `paper`: the whole admissible band is 0.0476
        // of luminance wide and the two hosts are 0.0402 apart inside it. So
        // light keeps `canvas` — the label contrast is the part that cannot be
        // compromised — and the press is carried by the pressed ghost's edge
        // instead (see pressBorder). (`surfaceWarm2` fails at 3.79:1 and
        // `surfaceWarm1` at 4.15:1, both on the `stone` label.)
        //
        // DARK: `paper`, which is 4.68:1 under the `stone` label and 11.58:1
        // under the default `ink`. `surfaceWarm2` is ruled out by that 4.68
        // (3.83:1) and `canvas` is ruled out in dark because it IS the dark
        // page: a `canvas` press would change nothing at all, leaving the fill
        // as the only press signal (§7.4). `paper` is the only step that both
        // lifts the press visibly and clears both labels.
        if (_pressed) return isDark ? s.paper : s.canvas;
        return Colors.transparent;
    }
  }

  Color _labelColor(SiftColors s, bool isDark) {
    if (_disabled) return s.stone;
    switch (widget.variant) {
      case BrutalVariant.filled:
      case BrutalVariant.destructive:
        if (_pressed) return isDark ? s.ink : s.canvas;
        return isDark ? s.canvas : s.onAccent;
      case BrutalVariant.outline:
        return s.ink;
      case BrutalVariant.text:
        // Dark mode changes the LABEL rather than reaching for a lighter fill,
        // because no fill rescues `accent` here: on pure white it is only
        // 1.05 / 0.33633 = 3.12:1, and the dark palette's lightest surface makes
        // it worse, so no background in either mode reaches 4.5:1 under it.
        // `ink` is therefore the dark pressed label. It reuses the outlined
        // button's dark REST pairing (`ink` on `paper`) rather than inventing a
        // third dark combination, which is the point the spec makes in §4.3.
        if (_pressed) return isDark ? s.ink : s.accentDeep;
        return s.ink;
    }
  }

  /// The 2pt edge a pressed GHOST paints, and the only thing carrying the press
  /// in light mode.
  ///
  /// The ghost's press cannot be a fill change on its own. §4.3's press fill in
  /// light was `canvas`, and the ghost is mounted either on `canvas` (onboarding,
  /// home's `_batchBar`) or on `paper` (every dialog action row) — so the wash
  /// measured 1.00:1 on one host and 1.04:1 on the other and drew nothing. The
  /// dark mode already rejects `canvas` for exactly this reason and takes
  /// `paper` instead; light has the same problem in mirror image, and its only
  /// available fix is bounded by the label, because the label sits ON the fill.
  ///
  /// The arithmetic, from [wcagContrast] over the `SiftColors.light` palette:
  ///
  ///   stone label  L + 0.05 = 0.21153  →  a 4.5:1 fill needs L + 0.05 >= 0.95186
  ///   paper/onAccent 0.99792   accentDeep 4.99 · stone 4.72 · vs canvas 1.04 · vs paper 1.00
  ///   canvas         0.95772   accentDeep 4.79 · stone 4.53 · vs canvas 1.00 · vs paper 1.04
  ///
  /// Those are the only two steps that clear the binding `stone` label, and they
  /// are the two hosts. So in light there is no fill that is both safe under the
  /// label and visible against the page, and the choice is forced: keep `canvas`
  /// for the label's 4.53:1 and put the press on an edge instead. Nothing is
  /// regressed to get there — light default stays 4.79:1, light `stone` 4.53:1,
  /// dark default 11.58:1, dark `stone` 4.68:1.
  ///
  /// [SiftColors.ink] is the right edge value, and one name covers both modes
  /// because `ink` IS each mode's own extreme step (warm-black in light, cream
  /// in dark — the same step the dark hard shadow is built from). A
  /// `BoxDecoration` border paints inside the box and ON TOP OF THE FILL, so this
  /// 2pt edge has the pressed fill on its inner side and the host on its outer
  /// one, and `ink` clears 3:1 on every such pair:
  ///
  ///   light  ink on the canvas fill / canvas host 13.71 · on a paper host 14.29
  ///   dark   ink on the paper fill / paper host 11.58 · on a canvas host 13.06
  ///
  /// Asserted per mode against both hosts in the test rather than restated here.
  ///
  /// It is not [SiftBrutal.focus], which is what the focused ghost draws. Focus
  /// wins when both are true: the focus indicator is what SC 2.4.7 is about, and
  /// a press affordance must not be allowed to erase it.
  Border? pressBorder(SiftColors s) => Border.all(
        color: s.ink,
        width: SiftBrutal.borderW,
      );

  /// A `BoxDecoration` border paints INSIDE the box, ON TOP OF THE FILL, so
  /// both the ring and the resting edge are scored against THIS control's own
  /// box and never against the page. The earlier comment here claimed the ring
  /// "replaces the border so it never lands on the fill"; that was the defect,
  /// not the fix — the border is the fill's own outermost 2pt, so the ring is
  /// always on the fill, and on the light filled button the fill IS
  /// `accentDeep` (SC 2.4.7 / 1.4.11, §6.10).
  ///
  /// A page-filled control — outlined, ghost, or disabled, all of which fill
  /// with a `paper` / `surfaceWarm` step — keeps `stone` and
  /// [SiftBrutal.focus]. A filled or destructive button is a slab and takes the
  /// inverted pair instead, at rest and pressed alike. Zero layout change: the
  /// ring still replaces the border in place at the same 2pt.
  ///
  /// The ghost is the one variant with no resting edge at all, so its border
  /// exists only in a state: the focus ring, or [pressBorder] while held down.
  Border? _border(SiftColors s, bool isDark) {
    if (_ghost) {
      // The ghost has no resting edge (§4.3), so both of its edges are
      // state-only. Focus is resolved first and wins over a simultaneous press:
      // the ring is the SC 2.4.7 indicator and must never be repainted by a
      // press affordance.
      if (_focused) {
        return Border.all(
          color: SiftBrutal.focus(isDark),
          width: SiftBrutal.borderW,
        );
      }
      return _pressed ? pressBorder(s) : null;
    }
    // Disabled fills with `surfaceWarm2`, a page step, so a disabled button
    // keeps the page-fill pair and the ring it already showed.
    final slab = !_disabled &&
        (widget.variant == BrutalVariant.filled ||
            widget.variant == BrutalVariant.destructive);
    return Border.all(
      color: _focused
          ? (slab
              ? SiftBrutal.focusOnFill(isDark: isDark, pressed: _pressed)
              : SiftBrutal.focus(isDark))
          : (slab ? SiftBrutal.edgeOnFill(isDark) : s.stone),
      width: SiftBrutal.borderW,
    );
  }

  /// A shadow means "this is available", so a disabled control drops it and a
  /// pressed one collapses it to a zero-offset sliver rather than softening it.
  List<BoxShadow> _shadow(bool isDark) {
    if (_disabled || _ghost) return SiftBrutal.none;
    return _pressed ? SiftBrutal.hardPressed(isDark) : SiftBrutal.hard(isDark);
  }

  /// Paint-time only: no relayout, and the hit test follows the box so the
  /// in-flight tap is unaffected. Suppressed entirely under reduced motion,
  /// where the fill inversion and shadow collapse carry the press alone.
  Offset get _translate => _pressed && !_ghost && MotionTokens.enabled
      ? SiftBrutal.offset
      : Offset.zero;

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = _labelColor(s, isDark);

    // Deliberately not a Material/InkWell: the app sets NoSplash globally and
    // there is no ink to draw here, so a gesture detector with the button
    // semantics set by hand is the whole interaction (§5.3.4). The durations
    // come from MotionTokens, which is the single reduced-motion gate, so this
    // file declares no Duration of its own (§6.6).
    //
    // [brutalActivate] is what Material's InkWell was providing for free: a
    // GestureDetector on its own is reachable and announced but not OPERABLE
    // from a keyboard, so Enter and Space need an Actions ancestor to land on.
    return Semantics(
      button: true,
      enabled: !_disabled,
      label: widget.semanticLabel,
      child: brutalActivate(
        onActivate: widget.onPressed,
        child: Focus(
          onFocusChange: _setFocused,
          child: MouseRegion(
            // Hover is a deliberate no-op on every surface in the spec; the
            // cursor is the one thing a pointer device is owed (§4.0).
            cursor:
                _disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onPressed,
              onTapDown: _disabled ? null : (_) => _setPressed(true),
              onTapUp: _disabled ? null : (_) => _setPressed(false),
              onTapCancel: _disabled ? null : () => _setPressed(false),
              child: Transform.translate(
                offset: _translate,
                child: AnimatedContainer(
                  duration: _pressed ? SiftBrutal.pressIn : SiftBrutal.pressOut,
                  curve: MotionTokens.easeOutCubic,
                  height: widget.height,
                  width: widget.expand ? double.infinity : null,
                  padding: widget.padding ??
                      const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _fill(s, isDark),
                    borderRadius: _ghost
                        ? null
                        : BorderRadius.circular(SiftRadii.rControl),
                    border: _border(s, isDark),
                    boxShadow: _shadow(isDark),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        IconTheme.merge(
                          data: IconThemeData(color: labelColor, size: 18),
                          child: widget.icon!,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: DefaultTextStyle.merge(
                          style:
                              SiftType.buttonLabel.copyWith(color: labelColor),
                          child: widget.child,
                        ),
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
