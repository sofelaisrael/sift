import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/theme/motion_tokens.dart';
import 'package:screensort_lam/widgets/brutal_field.dart';

/// The field's whole visual contract is four values: a 2pt border, the rControl
/// corner, a fill, and a shadow. A test that only checked "it renders" would
/// pass a build where the focus ring never swapped, so each of the three states
/// in DESIGN-BRUTALIST.md §4.5 is asserted directly, plus the two things the
/// migration could silently break: the 48/52dp pointer target, and the
/// controller round-trip the Settings key field's save-on-every-keystroke path
/// rides on.
///
/// Every wait is a single `pump(MotionTokens.standard)` after a state change
/// this test caused. Nothing here settles on a timer or a real clock.
void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    required Widget field,
    Brightness brightness = Brightness.light,
  }) async {
    final isDark = brightness == Brightness.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Scaffold(body: Center(child: field)),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) => tester
      .widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(BrutalField),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .decoration as BoxDecoration;

  Border borderOf(WidgetTester tester) =>
      decorationOf(tester).border! as Border;

  EditableText editableOf(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  /// A second focus target inside the same box, so "focus left the field" is
  /// observable. The search bar's clear button and the composer both need the
  /// ring to ignore exactly this.
  ///
  /// It must be ENABLED. A disabled Material button sets `canRequestFocus:
  /// false` on its internal node, so it is skipped by traversal entirely and
  /// focus would never leave the field — which silently turns "focus moved to a
  /// sibling inside the box" into "focus is still on the field", the one thing
  /// these two tests exist to distinguish.
  Widget sibling() =>
      TextButton(onPressed: () {}, child: const Text('Sibling'));

  /// The chat composer's bare field, so a test can put it in a row of its own
  /// without nesting two BrutalFields.
  Widget composerField({
    TextEditingController? controller,
    bool obscure = false,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      style: SiftType.bodySans.copyWith(color: SiftColors.light.ink),
      decoration: const InputDecoration(
        hintText: 'Ask about anything',
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }

  /// The chat composer's real shape, so the 52dp box is exercised with the
  /// content padding that actually ships with it.
  Widget composer({TextEditingController? controller, bool obscure = false}) {
    return BrutalField(
      height: 52,
      child: composerField(controller: controller, obscure: obscure),
    );
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(MotionTokens.standard);
  }

  group('rest', () {
    testWidgets('renders with the token border, radius, fill and shadow',
        (tester) async {
      await pumpField(tester, field: composer());

      final decoration = decorationOf(tester);
      expect(borderOf(tester).top.width, SiftBrutal.borderW);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(SiftRadii.rControl),
      );
      expect(decoration.color, SiftColors.light.paper);
      expect(decoration.boxShadow, SiftBrutal.hardLight);
    });

    testWidgets('the 2pt border is painted inside, so the 48/52dp target holds',
        (tester) async {
      for (final height in [48.0, 52.0]) {
        await pumpField(
          tester,
          field: BrutalField(height: height, child: const TextField()),
        );
        // The container lerps a height change, so let it land before measuring.
        await tester.pump(MotionTokens.standard);

        // The box does not grow: the decoration's padding is folded into the
        // interior rather than added to the height, so the pointer still gets
        // the whole 48/52dp the site had before.
        expect(tester.getSize(find.byType(BrutalField)).height, height);
        expect(height - 2 * SiftBrutal.borderW, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the fixed-height composer does not overflow its box',
        (tester) async {
      // Guards the one geometric risk "the total height does not move" cannot
      // rule out: the 2pt border takes 2dp off a 52dp box whose content already
      // wanted more than 52dp.
      await pumpField(tester, field: composer());

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextField)).height,
        52 - 2 * SiftBrutal.borderW,
      );
    });
  });

  group('focus', () {
    testWidgets("the field's focus swaps the border to the focus colour",
        (tester) async {
      await pumpField(tester, field: composer());

      expect(borderOf(tester).top.color, SiftColors.light.stone);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(MotionTokens.standard);

      expect(borderOf(tester).top.color, SiftBrutal.focusLight);
      // Same weight: the ring replaces the border in place rather than adding
      // to it, so focusing moves nothing.
      expect(borderOf(tester).top.width, SiftBrutal.borderW);
      // And the shadow stays. A field that lost its shadow on focus would read
      // as deflated — focus is engagement, not a sink (§4.5).
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardLight);

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      await tester.pump(MotionTokens.standard);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
    });

    testWidgets('dark mode swaps in the dark focus colour', (tester) async {
      await pumpField(
        tester,
        field: composer(),
        brightness: Brightness.dark,
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(MotionTokens.standard);

      expect(borderOf(tester).top.color, SiftBrutal.focusDark);
      expect(decorationOf(tester).boxShadow, SiftBrutal.hardDark);
    });

    testWidgets('the observing scope is not a focus stop of its own',
        (tester) async {
      // `composerField`, not `composer`: this box already IS the composer's
      // BrutalField, so nesting a second one inside it would put two
      // AnimatedContainers under the finder and every assertion below would
      // read the wrong one.
      await pumpField(
        tester,
        field: BrutalField(
          child: Row(children: [Expanded(child: composerField()), sibling()]),
        ),
      );

      // A bare Focus wrapper would insert itself ahead of the field, so one Tab
      // would land on the scope and the second on the field. One tab has to be
      // enough, and the next has to leave the box entirely.
      await tab(tester);
      expect(editableOf(tester).focusNode.hasFocus, isTrue);
      expect(borderOf(tester).top.color, SiftBrutal.focusLight);

      await tab(tester);
      expect(editableOf(tester).focusNode.hasFocus, isFalse);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
    });

    testWidgets('an external focus node drives the ring instead of the scope',
        (tester) async {
      // The search bar and the composer both own a node, and the search bar's
      // clear button sits inside the same box: focusing it must not light the
      // ring, which is exactly what it did before the migration.
      final node = FocusNode();
      addTearDown(node.dispose);

      await pumpField(
        tester,
        field: BrutalField(
          focusNode: node,
          child: Row(
            children: [
              // Bare field again — this box is the composer's BrutalField.
              Expanded(child: composerField(focusNode: node)),
              sibling(),
            ],
          ),
        ),
      );

      expect(borderOf(tester).top.color, SiftColors.light.stone);

      node.requestFocus();
      await tester.pump();
      await tester.pump(MotionTokens.standard);
      expect(borderOf(tester).top.color, SiftBrutal.focusLight);

      // Focus moved to the sibling inside the same box, so the ring goes back to
      // stone: the caller's node decides, not mere descendant focus.
      await tab(tester);
      expect(node.hasFocus, isFalse);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
    });
  });

  group('disabled', () {
    testWidgets('drops the shadow, mutes the fill, and never takes the ring',
        (tester) async {
      await pumpField(
        tester,
        field: const BrutalField(enabled: false, child: TextField()),
      );

      final decoration = decorationOf(tester);
      expect(decoration.color, SiftColors.light.surfaceWarm2);
      // A shadow means "this is available", so a disabled field drops it...
      expect(decoration.boxShadow, SiftBrutal.none);
      // ...but it keeps its border, so the shape stays identifiable (SC 1.4.11)
      // and the state is not merely "a lighter box".
      expect(borderOf(tester).top.color, SiftColors.light.stone);
      expect(borderOf(tester).top.width, SiftBrutal.borderW);

      // It also refuses pointers, so a tap cannot type into it or raise the
      // ring it is not allowed to show.
      await tester.tap(find.byType(TextField), warnIfMissed: false);
      await tester.pump();
      await tester.pump(MotionTokens.standard);
      expect(borderOf(tester).top.color, SiftColors.light.stone);
    });
  });

  group('text', () {
    testWidgets('a controller round-trips through the field unchanged',
        (tester) async {
      final prefilled = TextEditingController(text: 'flight BA123');
      addTearDown(prefilled.dispose);

      await pumpField(tester, field: composer(controller: prefilled));

      // Whatever the caller set before the first frame must be what renders,
      // or a pre-filled field would silently show empty.
      expect(find.text('flight BA123'), findsOneWidget);

      prefilled.text = 'Lisbon';
      await tester.pump();
      expect(find.text('Lisbon'), findsOneWidget);

      // And user input lands in the caller's own controller, which is the path
      // the Settings key field's onChanged handler rides on.
      final typed = TextEditingController();
      addTearDown(typed.dispose);
      await pumpField(tester, field: composer(controller: typed));

      await tester.enterText(find.byType(TextField), 'sk-lin-9');
      await tester.pump();

      expect(typed.text, 'sk-lin-9');
      expect(find.text('sk-lin-9'), findsOneWidget);
    });

    testWidgets('an obscured field stays obscured through the wrapper',
        (tester) async {
      final controller = TextEditingController(text: 'sk-secret');
      addTearDown(controller.dispose);

      await pumpField(
        tester,
        field: composer(controller: controller, obscure: true),
      );

      // The wrapper owns the box and nothing else, so the field's own
      // obfuscation — and its value — are untouched.
      expect(editableOf(tester).obscureText, isTrue);
      expect(controller.text, 'sk-secret');
    });
  });
}
