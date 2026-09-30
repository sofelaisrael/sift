import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';

import 'wcag_contrast.dart';

/// THE ACCESSIBILITY FIX, pinned.
///
/// DESIGN-BRUTALIST.md §6.11.3: the dark UNSELECTED switch thumb used to be
/// `paper` on a `surfaceWarm2` track — 1.22:1, i.e. the thumb was invisible
/// against its own track until the switch was turned on. That is a behaviour
/// fix bundled into a visual change, which is exactly the kind of thing a
/// reviewer mistakes for scope creep, so it is asserted rather than described:
/// these tests recompute the ratio from the resolved theme colours and fail if
/// the pair ever drops back to the shipped one.
///
/// All three Settings call sites route through the single `_flatSwitch` seam,
/// so resolving the theme once is resolving all three.
void main() {
  /// The state set Material asks about for a plain, unfocused, unpressed
  /// switch. `WidgetState` is an enum, so "none" is the empty set.
  const off = <WidgetState>{};
  const on = <WidgetState>{WidgetState.selected};
  const focused = <WidgetState>{WidgetState.focused};
  const onAndFocused = <WidgetState>{WidgetState.selected, WidgetState.focused};

  /// Mounts a real `Switch` and returns the `SwitchThemeData` AS THE MOUNTED
  /// WIDGET SEES IT — resolved through `Theme.of` on an element taken from
  /// inside the switch's own subtree, not read off the static theme object.
  ///
  /// What that buys, precisely: the mount is load-bearing. `Theme.of` is called
  /// on the element of the switch's single track `CustomPaint`, so if the tree
  /// stopped containing a `Switch` the finder would find no `CustomPaint`,
  /// `tester.element` would throw, and the test would fail. The previous
  /// version read `AppTheme.darkTheme.switchTheme` directly and would have
  /// passed identically against `home: const SizedBox()`. It is also a
  /// genuinely different object: `MaterialApp` merges the theme it is handed,
  /// so the in-tree `ThemeData` is not `identical` to the static one.
  Future<SwitchThemeData> resolve(
    WidgetTester tester, {
    required Brightness brightness,
    bool selected = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Scaffold(
          body: Switch(value: selected, onChanged: _noop),
        ),
      ),
    );

    // MaterialApp wraps its `theme` in an AnimatedTheme, so a re-pump that
    // swaps light for dark is still mid-interpolation and `Theme.of` would hand
    // back the previous mode's values. Settle first or the second call in any
    // loop silently measures the first.
    await tester.pumpAndSettle();

    // The track is painted by exactly one CustomPaint in the subtree. That is
    // an element inside the mounted control, which is what makes the read
    // below a read of the real tree.
    final track = find.descendant(
      of: find.byType(Switch),
      matching: find.byType(CustomPaint),
    );
    expect(track, findsOneWidget);

    // A real Switch laid out by Material, not a zero-sized placeholder.
    expect(tester.getSize(find.byType(Switch)).height,
        greaterThanOrEqualTo(kNonTextTargetDp));

    return Theme.of(tester.element(track)).switchTheme;
  }

  Color track(SwitchThemeData theme, Set<WidgetState> states) =>
      theme.trackColor!.resolve(states)!;

  group('dark mode', () {
    testWidgets('the unselected thumb is legible against its own track',
        (tester) async {
      final theme = await resolve(tester, brightness: Brightness.dark);

      final thumb = theme.thumbColor!.resolve(off)!;
      final trackFill = track(theme, off);

      expect(
        thumb,
        isNot(SiftColors.dark.paper),
        reason: 'dark unselected thumb regressed to `paper`, which is 1.22:1 '
            'on the surfaceWarm2 track and invisible against it (§6.11.3)',
      );

      expect(thumb, SiftColors.dark.stone);
      expect(trackFill, SiftColors.dark.surfaceWarm2);
      expect(
        wcagContrast(thumb, trackFill),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });

    testWidgets('the selected thumb is legible against the accentDeep track',
        (tester) async {
      final theme =
          await resolve(tester, brightness: Brightness.dark, selected: true);

      final thumb = theme.thumbColor!.resolve(on)!;
      final trackFill = track(theme, on);

      expect(thumb, SiftColors.dark.canvas);
      expect(trackFill, SiftColors.dark.accentDeep);
      expect(
        wcagContrast(thumb, trackFill),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });
  });

  group('light mode', () {
    testWidgets('both thumbs clear 3:1 on their own track', (tester) async {
      final offTheme = await resolve(tester, brightness: Brightness.light);
      final offThumb = offTheme.thumbColor!.resolve(off)!;
      final offTrack = track(offTheme, off);

      final onTheme =
          await resolve(tester, brightness: Brightness.light, selected: true);
      final onThumb = onTheme.thumbColor!.resolve(on)!;
      final onTrack = track(onTheme, on);

      expect(offThumb, SiftColors.light.ink);
      expect(offTrack, SiftColors.light.surfaceWarm2);
      expect(onThumb, SiftColors.light.paper);
      expect(onTrack, SiftColors.light.accentDeep);

      expect(
        wcagContrast(offThumb, offTrack),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(onThumb, onTrack),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });
  });

  group('track outline', () {
    testWidgets('is 2pt stone at rest on a real mounted Switch',
        (tester) async {
      for (final (brightness, isDark) in [
        (Brightness.light, false),
        (Brightness.dark, true),
      ]) {
        final theme = await resolve(tester, brightness: brightness);
        final expectedStone =
            isDark ? SiftColors.dark.stone : SiftColors.light.stone;

        expect(theme.trackOutlineWidth?.resolve(off), SiftBrutal.borderW);
        expect(theme.trackOutlineColor?.resolve(off), expectedStone);
        // A bare Switch with no focus does not request focus, so an explicit
        // focused state is what the ring is resolved against.
        expect(
          theme.trackOutlineColor?.resolve(focused),
          SiftBrutal.focus(isDark),
        );
      }
    });

    testWidgets('is legible against the track it outlines', (tester) async {
      // SC 1.4.11 is about the boundary against what surrounds it, so this is
      // the ratio the outline has to clear, not the fill.
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = await resolve(tester, brightness: brightness);
        final outline = theme.trackOutlineColor!.resolve(off)!;
        final trackFill = track(theme, off);

        expect(
          wcagContrast(outline, trackFill),
          greaterThanOrEqualTo(kNonTextContrast),
          reason: 'track outline on the $brightness fill',
        );
      }
    });

    test('was transparent before, so the switch had no boundary at all', () {
      // Guards the specific regression: reverting to transparent makes the
      // track vanish against the canvas in dark, and nothing else notices.
      for (final theme in [
        AppTheme.lightTheme.switchTheme,
        AppTheme.darkTheme.switchTheme,
      ]) {
        expect(
          theme.trackOutlineColor?.resolve(off),
          isNot(Colors.transparent),
        );
      }
    });
  });

  group('the ON track resting outline', () {
    // DESIGN-BRUTALIST.md §7.6.2 recorded this as a known gap rather than a fix:
    // `switchTheme` only branched on `focused`, so a selected-and-unfocused track
    // fell through to `stone`, which measures 1.06:1 in light against the
    // `accentDeep` fill — a 2pt border that drew nothing. The tests above read
    // the OFF track, so nothing noticed.

    testWidgets('clears 3:1 against its own track fill in both modes', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final isDark = brightness == Brightness.dark;
        final theme =
            await resolve(tester, brightness: brightness, selected: true);

        final outline = theme.trackOutlineColor!.resolve(on)!;
        final trackFill = track(theme, on);

        // The ON track fills with the same `accentDeep` in BOTH modes, so one
        // fill value has to clear the threshold twice and the two modes disagree
        // about which palette step does it.
        expect(
          trackFill,
          isDark ? SiftColors.dark.accentDeep : SiftColors.light.accentDeep,
        );

        // The outline paints inside the track, on top of the track FILL, so the
        // fill is the adjacent colour and the page is not what it is scored
        // against — the same rule the brutal controls follow (§6.10).
        expect(
          wcagContrast(outline, trackFill),
          greaterThanOrEqualTo(kNonTextContrast),
          reason: 'ON resting outline $brightness = '
              '${wcagContrast(outline, trackFill).toStringAsFixed(2)}:1',
        );
      }
    });

    testWidgets('is the measured pair, not stone and not the focus ring', (
      tester,
    ) async {
      // Two properties the 3:1 floor alone does not pin.
      //
      // Not `stone`: that is the 1.06:1 value the fix removes, and it is what
      // the code fell through to before.
      //
      // Not the focus ring: the ring is `onAccent` in light and `canvas` in dark,
      // and either of those as a resting edge would put the focused state within
      // 1.04:1 (light) or 1.00:1 (dark) of the resting one — the focus indicator
      // would stop being visible. Measured from the palette, `divider` is the
      // darkest light step that clears 3:1 and `ink` the lightest dark one that
      // is not the ring, so the pair is forced rather than chosen.
      for (final (brightness, expected) in [
        (Brightness.light, SiftColors.light.divider),
        (Brightness.dark, SiftColors.dark.ink),
      ]) {
        final isDark = brightness == Brightness.dark;
        final theme =
            await resolve(tester, brightness: brightness, selected: true);

        expect(theme.trackOutlineWidth?.resolve(on), SiftBrutal.borderW);
        expect(theme.trackOutlineColor?.resolve(on), expected);
        expect(expected, SiftBrutal.edgeOnTrack(isDark));

        final palette = isDark ? SiftColors.dark : SiftColors.light;
        expect(theme.trackOutlineColor?.resolve(on), isNot(palette.stone));
        expect(
          theme.trackOutlineColor?.resolve(on),
          isNot(SiftBrutal.focusOnFill(isDark: isDark)),
        );

        // Focus still CHANGES something. The light step is only 1.42:1, which is
        // the price of keeping the resting edge off the ring, and it is asserted
        // so a future edit cannot close that gap to 1.00:1 unnoticed.
        final resting = theme.trackOutlineColor!.resolve(on)!;
        final focusedRing = theme.trackOutlineColor!.resolve(onAndFocused)!;
        expect(resting, isNot(focusedRing));
        expect(
          wcagContrast(resting, focusedRing),
          greaterThanOrEqualTo(kDistinguishableState),
          reason: 'resting and focused ON outlines are indistinguishable, '
              '$brightness',
        );

        // And the ring this change must not regress is still a compliant one.
        expect(
          wcagContrast(focusedRing, track(theme, on)),
          greaterThanOrEqualTo(kNonTextContrast),
        );
      }
    });

    testWidgets('the OFF track keeps its page-step stone resting edge', (
      tester,
    ) async {
      // The ON track is a slab and the OFF track is a `surfaceWarm2` page step,
      // so the two states are not allowed to drift onto one value.
      for (final (brightness, stone) in [
        (Brightness.light, SiftColors.light.stone),
        (Brightness.dark, SiftColors.dark.stone),
      ]) {
        final theme = await resolve(tester, brightness: brightness);
        expect(theme.trackOutlineColor?.resolve(off), stone);
      }
    });
  });
}

/// How far apart two colours must be before a state change reads as one. Stated
/// locally so the light switch pair's 1.42:1 is a threshold somebody picked
/// rather than a number nobody questioned.
const double kDistinguishableState = 1.25;

/// WCAG 2.2 SC 2.5.8 floor, restated locally so the mounted-size assertion
/// above does not read as an arbitrary number.
const double kNonTextTargetDp = 24.0;

void _noop(bool value) {}
