import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/theme/motion_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';

import 'wcag_contrast.dart';

/// WCAG 2.1 SC 1.4.3 — the 4.5:1 floor for text below 18.66px bold / 24px.
/// `SiftType.buttonLabel` is 15pt/600, so every button label in the app owes
/// this ratio, not the 3:1 large-text one.
const double kTextContrast = 4.5;

/// The brutal press is carried by three signals, so a test that only checks the
/// translate would pass a build that had already regressed one of the other
/// two. These cover the four contract points that are cheap to assert: the
/// touch target, the disabled announcement, the focus ring, and the fact that
/// reduced motion removes the translate but not the press itself.
void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required Widget button,
    Brightness brightness = Brightness.light,
  }) async {
    final isDark = brightness == Brightness.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Scaffold(body: Center(child: button)),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) => tester
      .widget<AnimatedContainer>(find.byType(AnimatedContainer))
      .decoration as BoxDecoration;

  group('touch target', () {
    testWidgets('filled and outlined clear 48dp with the border inside it',
        (tester) async {
      for (final variant in [
        BrutalVariant.filled,
        BrutalVariant.outline,
        BrutalVariant.destructive,
      ]) {
        await pumpButton(
          tester,
          button: BrutalButton(
            variant: variant,
            onPressed: () {},
            child: const Text('Go'),
          ),
        );

        expect(
            tester.getSize(find.byType(BrutalButton)).height, SiftSpacing.btnH);
        // The 2pt is painted inside the box, so the interior is 44dp and the
        // pointer still gets the whole 48dp.
        expect(SiftSpacing.btnH - 2 * SiftBrutal.borderW, greaterThan(40));
      }
    });

    testWidgets('the ghost keeps the 40dp the text button theme imposed',
        (tester) async {
      await pumpButton(
        tester,
        button: BrutalButton.text(
          onPressed: () {},
          label: const Text('Skip'),
        ),
      );

      expect(tester.getSize(find.byType(BrutalButton)).height, 40);
    });
  });

  group('disabled', () {
    testWidgets('announces as disabled and ignores the tap', (tester) async {
      await pumpButton(
        tester,
        button: const BrutalButton(
          onPressed: null,
          child: Text('Completed'),
        ),
      );

      final handle = tester.ensureSemantics();
      final data = tester.getSemantics(find.byType(BrutalButton));
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);

      // An enabled instance of the same widget announces the opposite, which is
      // what proves `enabled:` is wired rather than the flag being always-false.
      await pumpButton(
        tester,
        button: BrutalButton(onPressed: () {}, child: const Text('Go')),
      );
      expect(
        tester
            .getSemantics(find.byType(BrutalButton))
            .flagsCollection
            .isEnabled,
        Tristate.isTrue,
      );

      await pumpButton(
        tester,
        button: const BrutalButton(
          onPressed: null,
          child: Text('Completed'),
        ),
      );

      // A disabled control never enters the pressed state, so a tap on it is
      // inert rather than merely callback-less.
      await tester.tap(find.byType(BrutalButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));

      // It keeps its border so the shape is still identifiable (SC 1.4.11) and
      // drops the shadow, because a shadow means "available".
      final decoration = decorationOf(tester);
      expect(decoration.color, SiftColors.light.surfaceWarm2);
      expect((decoration.border! as Border).top.color, SiftColors.light.stone);
      expect(decoration.boxShadow, SiftBrutal.none);
      handle.dispose();
    });
  });

  group('focus-visible', () {
    testWidgets('keyboard focus replaces the border with the focus colour',
        (tester) async {
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () {},
          child: const Text('Go'),
        ),
      );

      // `bone`, not `stone`: this is a FILLED button, so the border is painted
      // on its own `accentDeep` fill, where `stone` is 1.06:1 and drew nothing.
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftColors.light.bone,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // The ring is the slab pair, NOT `SiftBrutal.focus`: the border is
      // painted on the fill, so the indicator has to beat the fill
      // (4.99:1), not the page.
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftBrutal.focusOnFillLight,
      );
      expect((decorationOf(tester).border! as Border).top.width,
          SiftBrutal.borderW);

      // It is a focus-visible treatment, not a permanent one: it comes back
      // with the resting border the moment focus leaves.
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftColors.light.bone,
      );
    });

    testWidgets('dark mode swaps in the dark focus colour', (tester) async {
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () {},
          child: const Text('Go'),
        ),
        brightness: Brightness.dark,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftBrutal.focusOnFillDark,
      );
    });
  });

  group('keyboard activation', () {
    // Every test here asserts the focus ring FIRST, so "the callback did not
    // fire" can never be confused with "the key never arrived". Without that
    // ordering a broken harness — a control that was never focusable, a Tab
    // that went somewhere else — would pass a no-fire assertion vacuously.
    testWidgets('Enter on a focused button fires onPressed', (tester) async {
      var fired = 0;
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () => fired++,
          child: const Text('Go'),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // The ring lighting proves focus landed on THIS control...
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftBrutal.focusOnFillLight,
      );

      // ...so a zero here is a real regression and not a misdelivered key.
      // A GestureDetector alone is reachable and announced but not OPERABLE:
      // no Actions ancestor means ActivateIntent resolves to nothing and Enter
      // silently does nothing (SC 2.1.1 alongside SC 2.4.7).
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('Space on a focused button fires onPressed', (tester) async {
      var fired = 0;
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () => fired++,
          child: const Text('Go'),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftBrutal.focusOnFillLight,
      );

      // Space is bound to the same ActivateIntent, so one intent covers both
      // keys and neither is left as an unhandled shortcut.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('all four variants activate from the keyboard', (tester) async {
      // The wrapper is shared, so one helper call covers every surface. This
      // pins the coverage rather than the helper: a future variant that forgets
      // to wrap itself fails here.
      for (final variant in [
        BrutalVariant.filled,
        BrutalVariant.outline,
        BrutalVariant.destructive,
        BrutalVariant.text,
      ]) {
        var fired = 0;
        await pumpButton(
          tester,
          button: BrutalButton(
            variant: variant,
            onPressed: () => fired++,
            child: const Text('Go'),
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(fired, 1, reason: '$variant did not activate on Enter');
        // Leave nothing focused so the next iteration's Tab lands on the new
        // control rather than continuing from the previous one's node.
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pump();
      }
    });

    testWidgets('a disabled button does not activate on Enter', (tester) async {
      var fired = 0;
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () => fired++,
          child: const Text('Go'),
        ),
      );

      // Rebuild as the same control with the callback removed. The counter is
      // the callback that the enabled case proved DOES fire, so this is a real
      // check that null onPressed suppresses it rather than a control that
      // merely never received a key.
      await pumpButton(
        tester,
        button: const BrutalButton(
          onPressed: null,
          child: Text('Completed'),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // A disabled control is still focusable, so the ring still lights and
      // the key genuinely reaches it. That is what makes the non-firing below
      // meaningful rather than vacuous. The PAGE-fill ring, not the slab one:
      // a disabled button fills with `surfaceWarm2`, a page step, even when its
      // variant is `filled`.
      expect(
        (decorationOf(tester).border! as Border).top.color,
        SiftBrutal.focusLight,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // Enter cannot activate something a pointer cannot press.
      expect(fired, 0);

      // And it still reads as the disabled surface afterwards: no press
      // inversion leaked in from the keypress.
      expect(decorationOf(tester).color, SiftColors.light.surfaceWarm2);
      expect(decorationOf(tester).boxShadow, SiftBrutal.none);
    });
  });

  group('press', () {
    testWidgets('translates onto its own shadow when motion is allowed',
        (tester) async {
      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () {},
          child: const Text('Hide'),
        ),
      );

      final rest = tester.getTopLeft(find.text('Hide'));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Hide')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getTopLeft(find.text('Hide')) - rest, SiftBrutal.offset);
      // The shadow collapses rather than softening, so blurRadius stays 0.
      expect(
        decorationOf(tester).boxShadow,
        SiftBrutal.hardPressedLight,
      );
      expect(decorationOf(tester).color, SiftColors.light.ink);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Hide')), rest);
    });

    testWidgets('reduced motion drops the translate but keeps the press',
        (tester) async {
      MotionTokens.reduced = true;
      addTearDown(() => MotionTokens.reduced = false);

      await pumpButton(
        tester,
        button: BrutalButton(
          onPressed: () {},
          child: const Text('Hide'),
        ),
      );

      final rest = tester.getTopLeft(find.text('Hide'));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Hide')));
      await tester.pump();

      // Nothing moves...
      expect(tester.getTopLeft(find.text('Hide')), rest);
      // ...but the fill inversion and the shadow collapse are both still there,
      // so the press is not carried by the transform alone (SC 7.4).
      expect(decorationOf(tester).color, SiftColors.light.ink);
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardPressedLight);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the ghost press is a fill wash with no hard shadow',
        (tester) async {
      await pumpButton(
        tester,
        button: BrutalButton.text(
          onPressed: () {},
          label: const Text('Skip'),
        ),
      );

      final rest = tester.getTopLeft(find.text('Skip'));
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Skip')));
      await tester.pump(const Duration(milliseconds: 100));

      // `canvas`, not the `surfaceWarm1` the §4.3 state table still lists. The
      // table is superseded here: `accentDeep` on `surfaceWarm1` is 4.39:1 and
      // fails SC 1.4.3 for this 15pt/600 label, so the pressed fill was moved
      // to `canvas` for 4.79:1 (§7.1). Asserted against the shipped value so
      // the test cannot pass while the contrast fix is silently reverted.
      expect(decorationOf(tester).color, SiftColors.light.canvas);
      expect(decorationOf(tester).boxShadow, SiftBrutal.none);
      expect(tester.getTopLeft(find.text('Skip')), rest);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('ghost pressed label contrast', () {
    /// Presses [label] and returns the fill the label is actually drawn on
    /// together with the colour it is actually drawn in — both read off the
    /// mounted, pressed widget rather than off `SiftColors` constants.
    ///
    /// The label colour comes from the rendered `RichText` because that is the
    /// style that actually paints: `DefaultTextStyle.merge` only sets the
    /// per-state colour, and a `Text` carrying its own `style.color` overrides
    /// it. Two production sites do exactly that (onboarding 'Skip',
    /// widgets.dart 'Ask your memory instead'), which is why both variants are
    /// measured below rather than assuming one label covers the state.
    Future<(Color fill, Color label)> pressGhost(
      WidgetTester tester, {
      required Brightness brightness,
      required String label,
      required bool dimmed,
    }) async {
      await pumpButton(
        tester,
        brightness: brightness,
        button: Builder(
          builder: (context) => BrutalButton.text(
            onPressed: () {},
            label: Text(
              label,
              style: dimmed
                  ? SiftType.buttonLabel.copyWith(
                      color: AppTheme.of(context).stone,
                    )
                  : null,
            ),
          ),
        ),
      );

      final gesture =
          await tester.startGesture(tester.getCenter(find.text(label)));
      await tester.pump(const Duration(milliseconds: 100));

      final fill = decorationOf(tester).color!;
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.text(label),
          matching: find.byType(RichText),
        ),
      );
      final labelColour = rich.text.style!.color!;

      await gesture.up();
      await tester.pumpAndSettle();

      return (fill, labelColour);
    }

    // The ghost's pressed fill is what the label is DRAWN ON, so unlike the
    // hard shadow it is not fill-agnostic. This was a live SC 1.4.3 failure:
    // `accentDeep` on `surfaceWarm1` is 4.39:1 and `accent` on `surfaceWarm2`
    // is 3.98:1, both under the 4.5:1 this 15pt/600 label owes. The ratio is
    // COMPUTED from what the widget rendered, so the test cannot pass by
    // restating a claim the implementation happens to match today.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final dimmed in [false, true]) {
        testWidgets(
          'the ${dimmed ? 'dimmed ' : ''}pressed label clears 4.5:1 on its own '
          'fill in ${brightness.name}',
          (tester) async {
            final (fill, label) = await pressGhost(
              tester,
              brightness: brightness,
              label: dimmed ? 'Skip' : 'Cancel',
              dimmed: dimmed,
            );

            // A ghost at rest is transparent, so a transparent fill here would
            // mean the press never engaged and the ratio below would be
            // meaningless (it would be measured against the page, not a fill).
            expect(fill.a, greaterThan(0), reason: 'the press did not engage');

            expect(
              wcagContrast(label, fill),
              greaterThanOrEqualTo(kTextContrast),
              reason: 'pressed ghost label on its own fill '
                  '($brightness, dimmed=$dimmed)',
            );
          },
        );
      }
    }
  });
}
