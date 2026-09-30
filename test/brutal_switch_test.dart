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
}

/// WCAG 2.2 SC 2.5.8 floor, restated locally so the mounted-size assertion
/// above does not read as an arbitrary number.
const double kNonTextTargetDp = 24.0;

void _noop(bool value) {}
