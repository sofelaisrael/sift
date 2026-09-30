import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Neobrutalism-as-accent tokens.
///
/// SIFT is a warm-paper reading app. These tokens do not restyle it. They add
/// one visual grammar — "hard edge means this is a control" — to interactive
/// surfaces only, so tappability is learnable without tapping. Read-only
/// content keeps the paper personality; see DESIGN-BRUTALIST.md §2.5 for the
/// surfaces that are deliberately excluded.
///
/// Every value here is locked. Per-component overrides are a bug, not a
/// variation: two different shadow directions is the fastest way to make a
/// hard-edge language read as a rendering fault.
abstract final class SiftBrutal {
  SiftBrutal._();

  /// Control border weight. The existing hairline (0.5 light / 1.0 dark,
  /// AppTheme.hairline) is a *layer separator*; this is a *boundary marker* and
  /// needs enough weight to survive at 3:1 legibility against a light fill.
  /// 1.5 was tried and reads as a hairline at chip size.
  ///
  /// The control CORNER radius is deliberately NOT here. It lives once, as
  /// `SiftRadii.rControl`, and every brutal control that has a corner to round
  /// reads that name: `BrutalButton`, `SiftBrutalChip`, `BrutalField`, and the
  /// bottom sheet's `_SourceOption` pair. The one brutal surface that does not
  /// is `TagChip`'s 40pt delete target, and it is not an oversight — that one is
  /// `BoxShape.circle`, so it has no corner radius to set. Restating the value
  /// in this file is what would let one hard edge become two, and the deletion
  /// is the enforcement: there is no second copy here to drift.
  static const double borderW = 2.0;

  /// The one hard shadow offset. Direction is down-right on the assumption of
  /// a top-left light source, which is also the direction the existing warm
  /// L1–L4 shadows assume (all positive-Y; only L5 is negative-Y, and L5 is
  /// not used on any control).
  static const Offset offset = Offset(4, 4);

  /// Light-mode hard shadow: the existing warm shadow base #281E14 at 55%.
  /// Alpha is chosen so the 4pt sliver clears WCAG 2.1 SC 1.4.11 (3:1
  /// non-text contrast) against BOTH light page surfaces:
  ///   canvas #F8F4ED → 3.64:1 · paper #FBF9F4 → 3.80:1
  /// Because the offset hides the near edges, this value is fill-agnostic: it
  /// works under an accentDeep fill and a paper fill alike. That is why there
  /// is no accent-coloured hard shadow anywhere in the system.
  static const List<BoxShadow> hardLight = [
    BoxShadow(color: Color(0x8C281E14), offset: Offset(4, 4), blurRadius: 0),
  ];

  /// Dark-mode hard shadow: the edge is INVERTED to a light value.
  ///
  /// A black hard shadow on canvas #1F1B16 is arithmetically invisible —
  /// contrast(black, #1F1B16) = 0.06133/0.05 = 1.23:1. The offset edge
  /// therefore becomes `ink` at 45%, chosen to clear 3:1 against all three
  /// dark surfaces a control can sit on AND against the dark filled button's
  /// own cream fill:
  ///   canvas #1F1B16 → 3.69:1 · paper #2A2520 → 3.27:1
  ///   dark FilledButton fill ink #E8E0D2 → 3.54:1
  static const List<BoxShadow> hardDark = [
    BoxShadow(color: Color(0x73E8E0D2), offset: Offset(4, 4), blurRadius: 0),
  ];

  static const List<BoxShadow> none = [];

  static List<BoxShadow> hard(bool isDark) => isDark ? hardDark : hardLight;

  /// Press: the control translates down-right by [offset] while the shadow
  /// collapses to zero offset. blurRadius stays 0 in both states — the shadow
  /// never softens, it only disappears.
  ///
  /// A 4pt translate is deliberate: it equals the shadow offset exactly, so
  /// the control lands precisely on its own shadow and the button appears to
  /// have been pushed into the page. A smaller translate leaves a visible
  /// gap; a larger one detaches it.
  static const List<BoxShadow> hardPressedLight = [
    BoxShadow(color: Color(0x8C281E14), offset: Offset.zero, blurRadius: 0),
  ];
  static const List<BoxShadow> hardPressedDark = [
    BoxShadow(color: Color(0x73E8E0D2), offset: Offset.zero, blurRadius: 0),
  ];

  static List<BoxShadow> hardPressed(bool isDark) =>
      isDark ? hardPressedDark : hardPressedLight;

  /// Focus-visible ring colour, light mode, ON A PAGE-FILLED CONTROL. NOT
  /// `accent`: accent on canvas is 2.85:1 and on paper 2.97:1 — both below the
  /// 3:1 non-text threshold, so the existing 1.5pt `accent` focus ring
  /// (app_theme.dart:589, :716) does not clear SC 1.4.11. `accentDeep` clears
  /// it with margin: 4.79:1 on canvas, 4.99:1 on paper. Thicker is not a
  /// substitute for a different hue; both changes are made.
  ///
  /// These two are the ring for a control whose own box is a PAGE step —
  /// `paper`, `surfaceWarm1`, `surfaceWarm2`, or nothing at all on the ghost.
  /// A control that fills with a colour instead is a slab, and a slab cannot
  /// use this pair: see [focusOnFill].
  static const Color focusLight = Color(0xFFB04F2B); // == accentDeep

  /// Focus-visible ring colour, dark mode, on a page-filled control. `accent`
  /// clears 3:1 here (5.48:1 on canvas, 4.86:1 on paper) where `accentDeep`
  /// would not (3.26:1 on canvas, 2.89:1 on paper).
  static const Color focusDark = Color(0xFFD97757); // == accent

  static Color focus(bool isDark) => isDark ? focusDark : focusLight;

  /// The focus ring ON A FILLED SLAB — a filled or destructive button, the
  /// selected chip, the ON switch track. A slab is the one control whose own
  /// box is a colour rather than a page step.
  ///
  /// A `BoxDecoration` border paints INSIDE the box, ON TOP OF THE FILL. That
  /// single fact is the whole reason this pair exists. The earlier claim that
  /// the ring "replaces the border so it never lands on the fill" was wrong:
  /// the border is the fill's own outermost 2pt, so the ring is always on the
  /// fill. On the light filled button the fill IS `accentDeep` and
  /// [focusLight] is also `accentDeep` — 1.00:1, no indicator at all (§6.10).
  ///
  /// A slab ring therefore cannot be a darker shade of the slab. It is the
  /// value the slab is never filled with — the control's own FOREGROUND, which
  /// every slab is already painting its label or thumb in, so this costs no new
  /// hue in either mode. One value per mode covers every slab fill, because the
  /// palette offers nothing else: the only light steps clear of `accentDeep`
  /// are `paper` / `onAccent` / `canvas` (4.79–4.99:1) and the only dark one
  /// clear of `ink` is `canvas`; `bone` is 2.32:1 and `ink` itself 1.00:1.
  ///
  ///   light  `onAccent` #FBF9F4 → accentDeep 4.99 · error 5.47 · ink 14.28
  ///   dark   `canvas`   #1F1B16 → ink 13.06 · error 6.10 · accentDeep 3.26
  ///
  /// [pressed] follows the press, which inverts the fill exactly as it
  /// inverts the label (§4.1): the dark press fill IS `canvas`, i.e. the dark
  /// ring, so a dark button held down while focused would show 1.00:1. The
  /// light pair needs no flip — `onAccent` is 14.28:1 on the light press fill.
  static const Color focusOnFillLight = Color(0xFFFBF9F4); // == onAccent
  static const Color focusOnFillDark = Color(0xFF1F1B16); // == canvas (dark)
  static const Color focusOnFillPressedDark =
      Color(0xFFE8E0D2); // == ink (dark)

  static Color focusOnFill({required bool isDark, bool pressed = false}) {
    if (!isDark) return focusOnFillLight;
    return pressed ? focusOnFillPressedDark : focusOnFillDark;
  }

  /// The RESTING 2pt edge on a filled slab. `stone` — the resting edge on
  /// every page-filled control — is arithmetically blind on a slab: 1.06:1 on
  /// the light `accentDeep` fill, 1.16:1 on `error` in both modes. The light
  /// filled button's border, the one the whole 2pt language rests on, drew
  /// nothing.
  ///
  /// `bone` is the one palette step that separates from every slab fill in both
  /// modes, and the one that maximises the worst case of the alternatives
  /// (per alternative, over the slab fills: `stone` 1.06, `graphite` 1.38,
  /// `ink` 1.00 — it IS the selected chip's fill — `error` 1.00):
  ///
  ///   light  accentDeep 2.32 · error 2.54 · ink 6.64 (selected chip, pressed)
  ///   dark   ink 6.08 · error 2.84 · canvas 2.15 (pressed)
  ///
  /// The cost of one shared value is that the ring sits 2.15:1 from it, so the
  /// focus state is a step rather than an inversion. The alternative — an `ink`
  /// edge, 14.28:1 from the ring — is 1.00:1 on the selected chip's own fill,
  /// so it cannot be the shared value. A resting edge is not the focus
  /// indicator, so SC 1.4.11's 3:1 is not owed here; what it owes is being
  /// visible, and 2.15:1 where the defect was 1.06:1 is.
  static const Color edgeOnFillLight = Color(0xFFB5AB9E); // == bone (light)
  static const Color edgeOnFillDark = Color(0xFF5A4F44); // == bone (dark)

  static Color edgeOnFill(bool isDark) =>
      isDark ? edgeOnFillDark : edgeOnFillLight;

  /// The RESTING 2pt edge on the switch's ON track. Deliberately NOT
  /// [edgeOnFill], and this is the one place the shared-value rule above is
  /// broken.
  ///
  /// `switchTheme` had no resting edge for a selected track at all — it fell
  /// through to `stone`, which measures 1.06:1 in light and 1.62:1 in dark
  /// against the `accentDeep` fill. The track fills with the same `accentDeep`
  /// in BOTH modes (there is no dark-slab variant for it), so one fill value has
  /// to clear the threshold twice, and the two modes disagree about which step
  /// does it. Measured over the whole palette, against `accentDeep` (L + 0.05 =
  /// 0.19996):
  ///
  ///   light  paper/onAccent 4.99 · canvas 4.79 · divider 3.51 · bone 2.32 · ink 2.86
  ///   dark   ink 4.01 · canvas 3.26 · paper 2.89 · divider 2.37 · bone 1.52
  ///
  /// Two of those are disqualified on state legibility rather than contrast. The
  /// light ring is `onAccent` and the dark ring is `canvas`, so `canvas` cannot
  /// be the light resting edge (1.04:1 from its own ring — the focus state
  /// would stop being visible, an SC 2.4.7 regression) and cannot be the dark
  /// one (1.00:1 from its own ring — it IS the ring). That leaves, per mode:
  ///
  ///   light  `divider` 3.51:1 on the track, 1.42:1 from the ring
  ///   dark   `ink`     4.01:1 on the track, 13.06:1 from the ring
  ///
  /// `divider` is the DARKEST light step that clears 3:1, which is the same
  /// reason `bone` was picked for the shared edge: among the steps that qualify,
  /// the one furthest from the ring is the one that keeps focus readable. The
  /// 1.42:1 light step is weaker than the 2.15:1 `bone` gets, and that cost is
  /// named rather than hidden.
  ///
  /// Unsharing is safe here in a way it was not for [edgeOnFill]: this value is
  /// used on exactly one surface, so unlike the shared edge it can collide with
  /// nothing. `ink` IS the dark filled button's and the dark selected chip's
  /// fill, and neither control is ever inside a switch track.
  static const Color edgeOnTrackLight = Color(0xFFDDD2BD); // == divider (light)
  static const Color edgeOnTrackDark = Color(0xFFE8E0D2); // == ink (dark)

  static Color edgeOnTrack(bool isDark) =>
      isDark ? edgeOnTrackDark : edgeOnTrackLight;

  /// Press timing. Mirrors MotionTokens.press / MotionTokens.pressRelease
  /// rather than restating them, so the brutal press obeys the app's single
  /// reduced-motion gate for free: under reduced motion both durations
  /// collapse to Duration.zero and the press becomes an instant state swap.
  static Duration get pressIn => MotionTokens.press;

  static Duration get pressOut => MotionTokens.pressRelease;
}
