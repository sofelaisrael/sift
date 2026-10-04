import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brutal_tokens.dart';
import '../theme/motion_tokens.dart';
import 'brutal_activate.dart';

/// Which warm surface an unselected chip sits on.
///
/// The library filter row already sits on a paper band, so its chips are paper
/// on paper. The actions and chat rows sit on the canvas, and a paper chip
/// there would read as a hole; those take the next step up. Only these two
/// pairs are specified (DESIGN-BRUTALIST.md §4.6), which is why this is an
/// enum and not a free [Color] — the app has exactly two chip treatments, and a
/// per-call-site colour would be a third one nobody reviewed.
enum SiftChipRest {
  /// `paper` fill, `tagText` label. The library filter row.
  paper,

  /// `surfaceWarm1` fill, `ink` label. The actions and chat chip rows.
  warm,
}

/// The one hard-edged box geometry, for every surface that wears it.
///
/// `SiftBrutalChip` is built from this, and so are the three read-only labels
/// that the §2.5 reversal brought into the set — `TypeBadge`, `TagChip` and
/// Detail's `_RecognitionChip`. It exists because after the reversal the
/// 2pt / 4pt / 4pt-offset triple would otherwise be read in four files by hand,
/// and four hand-written copies of one triple is how one hard edge becomes two
/// (§6.3). The factory is the enforcement, the same way the absence of a second
/// `borderW` is.
///
/// [border] and [shadow] default to the resting read-only edge and the resting
/// hard shadow. A caller passes its own only when its state machine resolves a
/// different value — the chip, whose border has a focus branch and whose shadow
/// has a pressed and a disabled branch.
///
/// [borderRadius] exists for the bottom sheet, which is flush with the screen
/// edge and must round its top corners only: rounding all four would show the
/// modal barrier through four 4px notches at the bottom of the screen.
BoxDecoration brutalEdge({
  required Color fill,
  required bool isDark,
  Border? border,
  List<BoxShadow>? shadow,
  BorderRadiusGeometry borderRadius =
      const BorderRadius.all(Radius.circular(SiftRadii.rControl)),
}) =>
    BoxDecoration(
      color: fill,
      borderRadius: borderRadius,
      border: border ??
          Border.all(
            color: SiftBrutal.surfaceEdge(isDark),
            width: SiftBrutal.borderW,
          ),
      boxShadow: shadow ?? SiftBrutal.hard(isDark),
    );

/// The app's one chip: the library filter, the actions filter, and the chat
/// prompt/recent-query chip were three copies of the same 32dp capsule with
/// three different borders, and this replaces all three.
///
/// | State | Fill | Label | Border | Shadow |
/// |---|---|---|---|---|
/// | rest | `paper` / `surfaceWarm1` | `tagText` / `ink` | `stone` @ 2 | hard |
/// | selected | `ink` | `canvas` | `edgeOnFill` @ 2 | hard |
/// | pressed | as rest/selected | as rest/selected | as rest/selected | collapsed |
/// | focused | as rest/selected | as rest/selected | `focus` / `focusOnFill` @ 2 | as rest |
/// | disabled | `surfaceWarm2` | `stone` | `stone` @ 2 | none |
///
/// Two decisions are load-bearing:
///
/// - **Selected is a full fill inversion to `ink`, never a label change.** The
///   label is `canvas` in both modes, so "what is currently filtered" is
///   carried by the fill and the label alone. That single rule is what stops
///   the three chip classes from each inventing their own selected look.
///   The BORDER does move, because a `BoxDecoration` border is painted inside
///   the box on top of the fill: the selected `ink` fill is a slab, so it takes
///   `SiftBrutal.edgeOnFill` at rest and `SiftBrutal.focusOnFill` on focus,
///   both scored against the fill rather than the page (§6.10).
/// - **The corner is [SiftRadii.rControl], not the old full pill.** A pill with
///   a 2pt border and a down-right shadow makes the border meet the shadow
///   sliver at a non-orthogonal angle on the curved leading edge; at 4pt the
///   chip geometry matches the buttons and, since the §2.5 reversal, the
///   cards, badges and banners too. This is the single least-obvious change
///   in the spec and is isolated to this phase for review (§6.11.2).
///
/// Since the reversal, [brutalEdge] is the shared geometry and this widget is
/// one of its callers rather than its only one. It stays here rather than
/// moving to a new file because the radius argument above — the reason a pill
/// does not work with this border — is the reason the labels belong beside it.
///
/// Like [BrutalButton] there is no Material or InkWell: the app sets NoSplash
/// globally, a hard-edged control has no ink to draw, and the down-right
/// translate has to sit outside the decorated box. Durations come from
/// MotionTokens, so reduced motion collapses this press for free (§6.6).
class SiftBrutalChip extends StatefulWidget {
  /// The chip's text. Never reworded here — the caller owns the string.
  final String label;

  /// Null disables the chip: no press state, no tap, and it announces as
  /// disabled rather than merely looking dimmed. No call site disables a chip
  /// today; the state exists because §4.6 specifies it.
  final VoidCallback? onTap;

  final bool selected;

  /// Which warm pair the unselected state uses.
  final SiftChipRest rest;

  /// Label weight per state, left null to keep [SiftType.chipLabel]'s own w500.
  /// The three call sites disagreed about this before the migration, and §9
  /// forbids a typography change, so the difference is carried as a parameter
  /// rather than silently normalised.
  final FontWeight? restLabelWeight;
  final FontWeight? selectedLabelWeight;

  /// Total height INCLUDING the 2pt border. Stays 32dp, the app's existing
  /// chip height — enlarging it would reflow three screens and is a layout
  /// change (§9). A 2pt border is 6.25% of that, which §6.8 assesses as
  /// visible rather than dominant.
  final double height;

  const SiftBrutalChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.rest = SiftChipRest.paper,
    this.restLabelWeight,
    this.selectedLabelWeight,
    this.height = SiftSpacing.chipH,
  });

  @override
  State<SiftBrutalChip> createState() => _SiftBrutalChipState();
}

class _SiftBrutalChipState extends State<SiftBrutalChip> {
  bool _pressed = false;
  bool _focused = false;

  bool get _disabled => widget.onTap == null;

  void _setPressed(bool value) {
    if (value == _pressed) return;
    setState(() => _pressed = value);
  }

  void _setFocused(bool value) {
    if (value == _focused) return;
    setState(() => _focused = value);
  }

  Color _restFill(SiftColors s) => switch (widget.rest) {
        SiftChipRest.paper => s.paper,
        SiftChipRest.warm => s.surfaceWarm1,
      };

  Color _restLabel(SiftColors s) => switch (widget.rest) {
        SiftChipRest.paper => s.tagText,
        SiftChipRest.warm => s.ink,
      };

  Color _fill(SiftColors s) {
    if (_disabled) return s.surfaceWarm2;
    return widget.selected ? s.ink : _restFill(s);
  }

  Color _labelColor(SiftColors s) {
    if (_disabled) return s.stone;
    return widget.selected ? s.canvas : _restLabel(s);
  }

  /// A shadow means "this is available", so a disabled chip drops it and a
  /// pressed one collapses it to a zero-offset sliver rather than softening it.
  /// Hover is a deliberate no-op on every surface in the spec (§4.0).
  List<BoxShadow> _shadow(bool isDark) {
    if (_disabled) return SiftBrutal.none;
    return _pressed ? SiftBrutal.hardPressed(isDark) : SiftBrutal.hard(isDark);
  }

  /// Paint-time only, and exactly as far as the chip's own shadow so it lands on
  /// it. Suppressed under reduced motion, where the shadow collapse carries the
  /// press alone.
  Offset get _translate =>
      _pressed && MotionTokens.enabled ? SiftBrutal.offset : Offset.zero;

  @override
  Widget build(BuildContext context) {
    final s = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weight =
        widget.selected ? widget.selectedLabelWeight : widget.restLabelWeight;
    // A selected, enabled chip is a slab: its own fill is `ink`, not a page
    // step. A disabled chip fills with `surfaceWarm2`, which is a page step, so
    // it keeps the page-fill pair.
    final slab = widget.selected && !_disabled;

    // A GestureDetector is reachable and announced but not OPERABLE from a
    // keyboard, so the chip needs the same Actions ancestor Material's InkWell
    // supplies — see [brutalActivate].
    return Semantics(
      button: true,
      enabled: !_disabled,
      selected: widget.selected,
      child: brutalActivate(
        onActivate: widget.onTap,
        child: Focus(
          onFocusChange: _setFocused,
          child: MouseRegion(
            cursor:
                _disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              onTapDown: _disabled ? null : (_) => _setPressed(true),
              onTapUp: _disabled ? null : (_) => _setPressed(false),
              onTapCancel: _disabled ? null : () => _setPressed(false),
              child: Transform.translate(
                offset: _translate,
                child: AnimatedContainer(
                  duration: _pressed ? SiftBrutal.pressIn : SiftBrutal.pressOut,
                  curve: MotionTokens.easeOutCubic,
                  height: widget.height,
                  padding:
                      const EdgeInsets.symmetric(horizontal: SiftSpacing.s14),
                  alignment: Alignment.center,
                  decoration: brutalEdge(
                    fill: _fill(s),
                    isDark: isDark,
                    // A `BoxDecoration` border paints inside the box, on top of
                    // the fill, so the border is scored against THIS chip's own
                    // fill. An unselected chip fills with a page step and keeps
                    // `stone` + `SiftBrutal.focus`; the selected chip inverts
                    // to `ink` and is a slab, so it takes the inverted pair
                    // (§6.10 — the old claim that the ring "never lands on the
                    // fill" was the defect: it measured 2.86:1 in light and
                    // 2.38:1 in dark against the selected fill). The press
                    // never changes the chip's fill, so the ring has no press
                    // term here.
                    border: Border.all(
                      color: _focused
                          ? (slab
                              ? SiftBrutal.focusOnFill(isDark: isDark)
                              : SiftBrutal.focus(isDark))
                          : (slab ? SiftBrutal.edgeOnFill(isDark) : s.stone),
                      width: SiftBrutal.borderW,
                    ),
                    shadow: _shadow(isDark),
                  ),
                  child: Text(
                    widget.label,
                    style: SiftType.chipLabel.copyWith(
                      fontWeight: weight,
                      color: _labelColor(s),
                    ),
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
