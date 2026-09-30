import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/theme/motion_tokens.dart';
import 'package:screensort_lam/widgets/brutal_chip.dart';

import 'wcag_contrast.dart';

/// A chip is four values per state — a 2pt border, a 4pt corner, a fill, a
/// shadow — and the one that carries meaning is the selected fill. Both states
/// are asserted directly against the tokens, because a build where "selected"
/// only changed the border would pass a test that checked "it renders".
///
/// Every assertion reads one widget off one pump; nothing settles on a timer.
void main() {
  Future<void> pumpChip(
    WidgetTester tester, {
    required Widget chip,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Scaffold(body: Center(child: chip)),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) => tester
      .widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SiftBrutalChip),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .decoration as BoxDecoration;

  Border borderOf(WidgetTester tester) =>
      decorationOf(tester).border! as Border;

  TextStyle labelStyleOf(WidgetTester tester) =>
      tester.widget<Text>(find.text('Receipts')).style!;

  group('rest', () {
    testWidgets('carries the token border, radius, fill and shadow',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
          rest: SiftChipRest.paper,
        ),
      );

      final decoration = decorationOf(tester);
      expect(borderOf(tester).top.width, SiftBrutal.borderW);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
      // The pill is gone. This is the spec's least obviously-good change and the
      // one most likely to be reverted, so it is pinned rather than assumed.
      expect(
        decoration.borderRadius,
        BorderRadius.circular(SiftRadii.rControl),
      );
      expect(decoration.color, SiftColors.light.paper);
      expect(decoration.boxShadow, SiftBrutal.hardLight);
      expect(labelStyleOf(tester).color, SiftColors.light.tagText);
    });

    testWidgets('the warm rest pair is the one actions and chat ship',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
          rest: SiftChipRest.warm,
        ),
      );

      expect(decorationOf(tester).color, SiftColors.light.surfaceWarm1);
      expect(labelStyleOf(tester).color, SiftColors.light.ink);
      // The 2pt border is the thing these two chips did not have at all before.
      expect(borderOf(tester).top.width, SiftBrutal.borderW);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
    });

    testWidgets('dark mode swaps the hard shadow, not the border',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(label: 'Receipts', onTap: _noop),
        brightness: Brightness.dark,
      );

      expect(decorationOf(tester).boxShadow, SiftBrutal.hardDark);
      expect(borderOf(tester).top.color, SiftColors.dark.stone);
    });
  });

  group('selected', () {
    testWidgets('inverts the fill to ink and the label to canvas',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
          selected: true,
        ),
      );

      // Selected is a fill inversion, never a label change: the label is
      // `canvas` in both modes, so the fill and the label alone carry which
      // filter is on (§4.6). The BORDER does move, because it is painted on top
      // of the fill — `ink` is a slab fill, so it takes `edgeOnFill`.
      expect(decorationOf(tester).color, SiftColors.light.ink);
      expect(labelStyleOf(tester).color, SiftColors.light.canvas);
      expect(borderOf(tester).top.width, SiftBrutal.borderW);
      expect(borderOf(tester).top.color, SiftColors.light.bone);
      expect(
        decorationOf(tester).borderRadius,
        BorderRadius.circular(SiftRadii.rControl),
      );
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardLight);
    });

    testWidgets('the selected border clears 3:1 against the selected fill',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
          selected: true,
        ),
      );

      // Both sides of the ratio are read off the PUMPED chip, not off two
      // palette constants. Reading the constants would pass even if the chip
      // had swapped `bone` for `divider` — which is 1.42:1 on paper and the
      // exact failure this pairing exists to prevent (§4.6, §7.1).
      final decoration = decorationOf(tester);
      final border = decoration.border! as Border;

      expect(
        border.top.color,
        SiftColors.light.bone,
        reason: 'the selected border regressed off `bone`, which is the only '
            'palette step that separates from every slab fill in both modes',
      );
      expect(
        wcagContrast(border.top.color, decoration.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });
  });

  group('press', () {
    // The chip owns its own _pressed/_translate/_shadow logic rather than
    // sharing the button's, so nothing else in this file would notice if the
    // translate quietly became Offset.zero or the shadow stopped collapsing.
    testWidgets('translates onto its own shadow when motion is allowed',
        (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
        ),
      );

      final rest = tester.getTopLeft(find.text('Receipts'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Receipts')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Exactly as far as the shadow, so the chip lands on it (§4.6).
      expect(
        tester.getTopLeft(find.text('Receipts')) - rest,
        SiftBrutal.offset,
      );
      // The shadow collapses rather than softening, so blurRadius stays 0.
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardPressedLight);
      // The chip's press is a translate plus a shadow collapse, NOT a fill
      // inversion: the fill carries which filter is selected, so inverting it
      // on press would read as a selection change.
      expect(decorationOf(tester).color, SiftColors.light.paper);
      // The border does not move either, so focus is not implied.
      expect(borderOf(tester).top.color, SiftColors.light.stone);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Receipts')), rest);
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardLight);
    });

    testWidgets('a selected chip presses the same way', (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
          selected: true,
        ),
      );

      final rest = tester.getTopLeft(find.text('Receipts'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Receipts')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getTopLeft(find.text('Receipts')) - rest,
        SiftBrutal.offset,
      );
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardPressedLight);
      expect(decorationOf(tester).color, SiftColors.light.ink);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Receipts')), rest);
    });

    testWidgets('reduced motion drops the translate but keeps the press',
        (tester) async {
      MotionTokens.reduced = true;
      addTearDown(() => MotionTokens.reduced = false);

      await pumpChip(
        tester,
        chip: const SiftBrutalChip(
          label: 'Receipts',
          onTap: _noop,
        ),
      );

      final rest = tester.getTopLeft(find.text('Receipts'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Receipts')),
      );
      await tester.pump();

      // Nothing moves...
      expect(tester.getTopLeft(find.text('Receipts')), rest);
      // ...but the shadow still collapses, so the press is not carried by the
      // transform alone (SC 7.4).
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardPressedLight);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardLight);
    });

    testWidgets('a disabled chip does not press', (tester) async {
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(label: 'Receipts', onTap: null),
      );

      final rest = tester.getTopLeft(find.text('Receipts'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Receipts')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // No translate, no shadow to collapse, and the disabled fill stays put.
      expect(tester.getTopLeft(find.text('Receipts')), rest);
      expect(decorationOf(tester).boxShadow, SiftBrutal.none);
      expect(decorationOf(tester).color, SiftColors.light.surfaceWarm2);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('keyboard activation', () {
    // As with the button, the ring is asserted first so that "did not fire" can
    // never be confused with "the key never arrived". The chip has no Material
    // or InkWell behind it, so without an Actions ancestor it is reachable and
    // announced but not OPERABLE: Enter would do nothing at all (SC 2.1.1).
    testWidgets('Enter on a focused chip fires onTap', (tester) async {
      var fired = 0;
      await pumpChip(
        tester,
        chip: SiftBrutalChip(label: 'Receipts', onTap: () => fired++),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // The ring replaces the stone border, so a lit ring here means focus
      // landed on THIS chip and the Enter below is really delivered to it.
      expect(borderOf(tester).top.color, SiftBrutal.focusLight);
      expect(borderOf(tester).top.width, SiftBrutal.borderW);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('a selected chip still activates from the keyboard',
        (tester) async {
      // Selected swaps the fill to `ink` and the label to `canvas`, so this
      // pins that the shared wrapper is not conditional on the visual variant.
      var fired = 0;
      await pumpChip(
        tester,
        chip: SiftBrutalChip(
          label: 'Receipts',
          onTap: () => fired++,
          selected: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('a disabled chip does not activate on Enter', (tester) async {
      var fired = 0;
      await pumpChip(
        tester,
        chip: SiftBrutalChip(label: 'Receipts', onTap: () => fired++),
      );

      // Re-pump the same control with the callback removed. The enabled case
      // above proves the counter really does fire, so this is a real check
      // that a null onTap suppresses it.
      await pumpChip(
        tester,
        chip: const SiftBrutalChip(label: 'Receipts', onTap: null),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // A disabled chip is still focusable, so the key genuinely reaches it and
      // the non-firing below is meaningful rather than vacuous.
      expect(borderOf(tester).top.color, SiftBrutal.focusLight);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // Enter cannot activate something a pointer cannot press.
      expect(fired, 0);
      // No press inversion leaked in from the keypress.
      expect(decorationOf(tester).color, SiftColors.light.surfaceWarm2);
      expect(decorationOf(tester).boxShadow, SiftBrutal.none);
    });
  });
}

void _noop() {}
