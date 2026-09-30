import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';
import 'package:screensort_lam/widgets/privacy_gate.dart';

/// Phase 4 gate, in both directions.
///
/// The spec puts the hard edge on a dialog's ACTION ROW, not on the dialog:
/// chrome is a container, so it keeps `rCard` 20 and stays borderless
/// (DESIGN-BRUTALIST.md §2.5, §8 Phase 4 — "if the sheet itself grew a hard
/// edge, that is a Phase 4 failure"). A test that only checked the action row
/// would pass a build that had also hard-edged the dialog box, and one that only
/// checked the box would pass a build with no brutal control in it, so both are
/// asserted.
///
/// Both assertions run against a REAL production dialog — `privacy_gate.dart`,
/// one of the nine `showDialog` sites — rather than a dialog the test builds
/// itself. The previous version of this file constructed its own `AlertDialog`
/// with its own `BrutalButton`s, so "the action row carries the 2pt border" was
/// a statement about the test's own widgets and would have held if every one of
/// the nine real sites had been left as a Material `TextButton`.
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

  testWidgets('the dialog chrome itself stays warm', (tester) async {
    final context = await openRealDialog(tester);
    final dialogTheme = Theme.of(context).dialogTheme;

    // rCard, not rControl: a hard-edged dialog box would be a container wearing
    // a control's grammar, which is the §1 rule inverted.
    final shape = dialogTheme.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      BorderRadius.circular(SiftRadii.rCard),
    );
    expect(shape.side, BorderSide.none);
    expect(dialogTheme.backgroundColor, SiftColors.light.paper);
  });
}
