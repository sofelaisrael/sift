import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';
import 'package:screensort_lam/widgets/privacy_gate.dart';

import 'wcag_contrast.dart';

/// Both halves of the dialog surface, asserted in both directions.
///
/// This file previously asserted the opposite of what it asserts now. The spec
/// put the hard edge on a dialog's ACTION ROW and left the chrome warm, because
/// "chrome is a container, not a control". That was reversed after a device
/// review — brutal buttons were landing inside a warm box — so the chrome now
/// carries the 2pt edge and [SiftRadii.rControl] as well, and the second test
/// below asserts exactly that.
///
/// Both directions are still asserted on purpose. The action-row test alone
/// would pass a build that had reverted the chrome, and the chrome test alone
/// would pass a build with no brutal control in it.
///
/// Both assertions run against a REAL production dialog — `privacy_gate.dart`,
/// one of the eight `showDialog` sites — rather than a dialog the test builds
/// itself. The previous version of this file constructed its own `AlertDialog`
/// with its own `BrutalButton`s, so "the action row carries the 2pt border" was
/// a statement about the test's own widgets and would have held if every one of
/// the eight real sites had been left as a Material `TextButton`.
///
/// Copy is not asserted beyond the title, which exists to prove the production
/// dialog really is the one on screen: the body string literals in these files
/// are load-bearing for the source-scanning tests, and this one must not become
/// a second place they have to be kept in sync.
void main() {
  /// Opens the real privacy-consent dialog through its real entry point.
  ///
  /// The two mocked keys are the ones its own guards read: `localOnly` false so
  /// it does not return early as local-only, `privacy_consent` false so it is
  /// not already answered. Everything after that is production code.
  Future<BuildContext> openRealDialog(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'localOnly': false,
      'privacy_consent': false,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrivacyConsentIfNeeded(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // The entry point awaits SharedPreferences before showing, then routes in
    // over 150ms. pumpAndSettle covers both; no clock is involved.
    await tester.pumpAndSettle();

    // The production title, so "the action row below is the real one" is a fact
    // this test establishes rather than assumes.
    expect(find.text('One thing before we start'), findsOneWidget);

    return tester.element(find.byType(AlertDialog));
  }

  testWidgets("the production dialog's action row carries the 2pt border",
      (tester) async {
    await openRealDialog(tester);

    // The filled action, not the ghost beside it: a ghost deliberately has no
    // hard edge (§4.3), so asserting on the first BrutalButton would read the
    // wrong one.
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(BrutalButton).last,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.width, SiftBrutal.borderW);
    // `bone`: a filled button is a slab, so its resting edge is the slab edge,
    // not the page-fill `stone` (which is 1.06:1 on the `accentDeep` fill).
    expect(border.top.color, SiftColors.light.bone);
    expect(decoration.boxShadow, SiftBrutal.hardLight);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(SiftRadii.rControl),
    );
  });

  testWidgets('the dialog chrome now carries the hard edge too',
      (tester) async {
    final context = await openRealDialog(tester);
    final dialogTheme = Theme.of(context).dialogTheme;

    // rControl, not rCard: this is the reversal of the old rule, and it is
    // asserted rather than assumed so a revert cannot pass quietly.
    final shape = dialogTheme.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      BorderRadius.circular(SiftRadii.rControl),
    );
    expect(shape.side, isNot(BorderSide.none));

    // The 2pt edge is scored against the `paper` fill it is painted on, so it
    // takes the page-step `surfaceEdge`, and both operands are read off the
    // PUMPED theme rather than restated as two palette constants — reading the
    // constants would pass even if the side had been left at `divider`, which is
    // 1.42:1 on `paper` and the exact failure the edge exists to prevent.
    expect(shape.side.width, SiftBrutal.borderW);
    expect(shape.side.color, SiftBrutal.surfaceEdgeLight);
    expect(dialogTheme.backgroundColor, SiftColors.light.paper);
    expect(
      wcagContrast(shape.side.color, dialogTheme.backgroundColor!),
      greaterThanOrEqualTo(kNonTextContrast),
    );

    // `elevation: 0`, because a `Material`'s only shadow is the blurred
    // elevation one. Left at the M3 default of 6 this dialog carries a 24px-blur
    // shadow under a 2pt hard border — two shadow languages, one of them in a
    // different direction.
    expect(dialogTheme.elevation, 0);
    expect(dialogTheme.shadowColor, Colors.transparent);
  });

  testWidgets('dark mode swaps the dialog edge, and nothing else',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'localOnly': false,
      'privacy_consent': false,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrivacyConsentIfNeeded(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('One thing before we start'), findsOneWidget);

    final dialogTheme =
        Theme.of(tester.element(find.byType(AlertDialog))).dialogTheme;
    final shape = dialogTheme.shape! as RoundedRectangleBorder;

    expect(shape.side.color, SiftBrutal.surfaceEdgeDark);
    expect(shape.side.width, SiftBrutal.borderW);
    expect(dialogTheme.backgroundColor, SiftColors.dark.paper);
    // 4.68:1 — the fill is untouched by this change, so the 15pt body text on
    // `paper` is exactly where it was.
    expect(
      wcagContrast(shape.side.color, dialogTheme.backgroundColor!),
      greaterThanOrEqualTo(kNonTextContrast),
    );
  });
}
