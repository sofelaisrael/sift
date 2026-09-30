import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';
import 'package:screensort_lam/widgets/brutal_chip.dart';

import 'wcag_contrast.dart';

/// The focus ring is scored against the control's OWN FILL, not the page.
///
/// A `BoxDecoration` border paints inside the box, on top of the fill, so the
/// ring is always drawn over the fill. The spec this suite implements was
/// written on the opposite assumption — DESIGN-BRUTALIST.md §6.10 said the
/// in-place border "never sits on the fill" and called the resulting 1.00:1
/// "irrelevant" — so the light filled button, the app's primary CTA and a fill
/// of `accentDeep`, shipped with a ring of `accentDeep`: no indicator at all,
/// and an SC 2.4.7 failure on the most important control in the app.
///
/// Every ratio here is COMPUTED from the mounted, focused control with
/// [wcagContrast] — the same helper the chip and switch tests already use — so
/// no figure in this file is a restated claim. Both sides of every ratio are
/// read off the widget tree rather than off `SiftColors` constants, so a build
/// that quietly changed a FILL could not make a test pass by pairing the ring
/// with a page colour the control never paints on.
void main() {
  /// The state sets Material asks about. `WidgetState` is an enum, so "none"
  /// is the empty set.
  const off = <WidgetState>{};
  const on = <WidgetState>{WidgetState.selected};
  const focused = <WidgetState>{WidgetState.focused};
  const onAndFocused = <WidgetState>{WidgetState.selected, WidgetState.focused};

  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    // MaterialApp wraps its theme in an AnimatedTheme, so a re-pump that swaps
    // light for dark is still interpolating and every colour read below would
    // come out as a lerp of the two palettes — a mid-grey `bone` instead of
    // `bone` dark, say, and a ratio measured against a colour the control never
    // paints. Settle before reading anything.
    await tester.pumpAndSettle();
  }

  /// Both painted edges of one control's box, read off the mounted tree.
  (Color ring, Color fill) edgesOf(
    WidgetTester tester,
    Finder control,
  ) {
    final decoration = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: control,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .decoration as BoxDecoration;
    return ((decoration.border! as Border).top.color, decoration.color!);
  }

  /// Tabs to the control — the route a keyboard or switch-access user takes —
  /// and returns the ring and the fill it actually paints.
  Future<(Color ring, Color fill)> focusEdges(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) async {
    await pump(tester, child, brightness: brightness);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    return edgesOf(tester, find.byWidget(child));
  }

  /// The switch paints no `BoxDecoration` of its own, so the same question is
  /// asked of the `SwitchThemeData` — resolved through `Theme.of` on an
  /// element taken from inside a really mounted `Switch`, as
  /// `brutal_switch_test.dart` does, so a tree that stopped containing a switch
  /// fails here instead of passing.
  Future<(Color ring, Color fill)> focusTrack(
    WidgetTester tester, {
    required bool selected,
    Brightness brightness = Brightness.light,
  }) async {
    await pump(
      tester,
      Switch(value: selected, onChanged: _onChanged),
      brightness: brightness,
    );

    final track = find.descendant(
      of: find.byType(Switch),
      matching: find.byType(CustomPaint),
    );
    expect(track, findsOneWidget);

    final theme = Theme.of(tester.element(track)).switchTheme;
    return (
      theme.trackOutlineColor!.resolve(onAndFocused)!,
      theme.trackColor!.resolve(on)!,
    );
  }

  /// One assertion, shared by all seven cases, so the floor is stated once and
  /// a passing run always means the same thing.
  void expectRingClearsOwnFill(Color ring, Color fill, String what) {
    // An opaque fill is what makes the ratio mean anything: a transparent or
    // absent fill here would mean the control was measured against the page,
    // which is the mistake this whole file exists to prevent.
    expect(fill.a, greaterThan(0),
        reason: '$what has no fill to score against');
    expect(
      wcagContrast(ring, fill),
      greaterThanOrEqualTo(kNonTextContrast),
      reason: '$what: ring ${hex(ring)} on its own fill ${hex(fill)} = '
          '${wcagContrast(ring, fill).toStringAsFixed(2)}:1',
    );
  }

  group('focus ring against the fill it is painted on', () {
    testWidgets("filled, light — the app's primary CTA", (tester) async {
      final (ring, fill) = await focusEdges(
        tester,
        const BrutalButton(onPressed: _noop, child: Text('Go')),
      );

      // The identity assertions are the guard against a vacuous pass: if the
      // fill or the ring moved, the ratio below would be scoring a pair this
      // control does not actually paint.
      expect(fill, SiftColors.light.accentDeep);
      expect(ring, SiftBrutal.focusOnFillLight);
      expectRingClearsOwnFill(ring, fill, 'filled light');
    });

    testWidgets('filled, dark', (tester) async {
      final (ring, fill) = await focusEdges(
        tester,
        const BrutalButton(onPressed: _noop, child: Text('Go')),
        brightness: Brightness.dark,
      );

      expect(fill, SiftColors.dark.ink);
      expect(ring, SiftBrutal.focusOnFillDark);
      expectRingClearsOwnFill(ring, fill, 'filled dark');
    });

    testWidgets('destructive, light', (tester) async {
      final (ring, fill) = await focusEdges(
        tester,
        const BrutalButton(
          variant: BrutalVariant.destructive,
          onPressed: _noop,
          child: Text('Delete'),
        ),
      );

      expect(fill, SiftColors.light.error);
      expect(ring, SiftBrutal.focusOnFillLight);
      expectRingClearsOwnFill(ring, fill, 'destructive light');
    });

    testWidgets('chip, selected, light', (tester) async {
      final (ring, fill) = await focusEdges(
        tester,
        const SiftBrutalChip(label: 'Receipts', onTap: _noop, selected: true),
      );

      expect(fill, SiftColors.light.ink);
      expect(ring, SiftBrutal.focusOnFillLight);
      expectRingClearsOwnFill(ring, fill, 'chip selected light');
    });

    testWidgets('chip, selected, dark', (tester) async {
      final (ring, fill) = await focusEdges(
        tester,
        const SiftBrutalChip(label: 'Receipts', onTap: _noop, selected: true),
        brightness: Brightness.dark,
      );

      expect(fill, SiftColors.dark.ink);
      expect(ring, SiftBrutal.focusOnFillDark);
      expectRingClearsOwnFill(ring, fill, 'chip selected dark');
    });

    testWidgets('switch, on, light', (tester) async {
      final (ring, fill) = await focusTrack(tester, selected: true);

      expect(fill, SiftColors.light.accentDeep);
      expect(ring, SiftBrutal.focusOnFillLight);
      expectRingClearsOwnFill(ring, fill, 'switch on light');
    });

    testWidgets('switch, on, dark', (tester) async {
      final (ring, fill) = await focusTrack(
        tester,
        selected: true,
        brightness: Brightness.dark,
      );

      expect(fill, SiftColors.dark.accentDeep);
      expect(ring, SiftBrutal.focusOnFillDark);
      expectRingClearsOwnFill(ring, fill, 'switch on dark');
    });
  });

  group('the states the seven cases do not name', () {
    // A press inverts the fill exactly as it inverts the label (§4.1), and a
    // keyboard user holding Space is focused and pressed at the same time, so
    // the ring has to follow the fill or the dark button rings itself in its
    // own ring colour.
    testWidgets('filled and pressed at once still clears 3:1', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pump(
          tester,
          const BrutalButton(onPressed: _noop, child: Text('Go')),
          brightness: brightness,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final gesture =
            await tester.startGesture(tester.getCenter(find.text('Go')));
        await tester.pump(const Duration(milliseconds: 100));

        final (ring, fill) = edgesOf(tester, find.byType(BrutalButton));

        await gesture.up();
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pump();

        expectRingClearsOwnFill(ring, fill, 'filled + pressed, $brightness');
      }
    });

    // The off track fills with `surfaceWarm2`, a page step, so it keeps the
    // page-fill ring. Asserted so the focused branch above cannot swallow it.
    testWidgets('the off switch keeps the page-fill ring', (tester) async {
      await pump(tester, const Switch(value: false, onChanged: _onChanged));

      final track = find.descendant(
        of: find.byType(Switch),
        matching: find.byType(CustomPaint),
      );
      final theme = Theme.of(tester.element(track)).switchTheme;

      final ring = theme.trackOutlineColor!.resolve(focused)!;
      final fill = theme.trackColor!.resolve(off)!;

      expect(ring, SiftBrutal.focusLight);
      expectRingClearsOwnFill(ring, fill, 'switch off, light');
    });
  });

  group('the resting edge on a filled slab', () {
    /// SC 1.4.11's 3:1 is owed by the focus INDICATOR, and a resting edge is
    /// not one. What it owes is being visible at all, and the floor it has to
    /// clear is stated here rather than assumed: the defect this change fixes
    /// was `stone` on the light `accentDeep` fill at 1.06:1, a 2pt border that
    /// drew nothing. Two is a deliberately weak floor, because the palette has
    /// no step that both separates from every slab fill and sits far enough
    /// from the ring to be unmistakable — see `SiftBrutal.edgeOnFill`.
    const double kVisibleEdge = 2.0;

    testWidgets('is visible on the fill of every filled variant', (
      tester,
    ) async {
      for (final (variant, label) in [
        (BrutalVariant.filled, 'filled'),
        (BrutalVariant.destructive, 'destructive'),
      ]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final isDark = brightness == Brightness.dark;
          await pump(
            tester,
            BrutalButton(
              variant: variant,
              onPressed: _noop,
              child: const Text('Go'),
            ),
            brightness: brightness,
          );

          final (edge, fill) = edgesOf(tester, find.byType(BrutalButton));

          expect(edge, SiftBrutal.edgeOnFill(isDark));
          expect(
            wcagContrast(edge, fill),
            greaterThanOrEqualTo(kVisibleEdge),
            reason: '$label resting edge ${hex(edge)} on its own fill '
                '${hex(fill)}, $brightness = '
                '${wcagContrast(edge, fill).toStringAsFixed(2)}:1',
          );
        }
      }
    });

    testWidgets('is visible on the selected chip fill in both modes', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pump(
          tester,
          const SiftBrutalChip(label: 'Receipts', onTap: _noop, selected: true),
          brightness: brightness,
        );

        final (edge, fill) = edgesOf(tester, find.byType(SiftBrutalChip));

        expect(edge, SiftBrutal.edgeOnFill(brightness == Brightness.dark));
        expect(
          wcagContrast(edge, fill),
          greaterThanOrEqualTo(kVisibleEdge),
          reason: 'selected chip resting edge, $brightness = '
              '${wcagContrast(edge, fill).toStringAsFixed(2)}:1',
        );
      }
    });

    // A page-filled control is not a slab and must not be restyled by any of
    // the above: the disabled button keeps `stone`, because `surfaceWarm2` is
    // a page step even when the variant is `filled`.
    testWidgets('is not applied to a page-filled control', (tester) async {
      await pump(
        tester,
        const BrutalButton(
          variant: BrutalVariant.filled,
          onPressed: null,
          child: Text('Done'),
        ),
      );

      final (edge, fill) = edgesOf(tester, find.byType(BrutalButton));
      expect(edge, SiftColors.light.stone);
      expect(fill, SiftColors.light.surfaceWarm2);
    });
  });
}

void _noop() {}

void _onChanged(bool value) {}
