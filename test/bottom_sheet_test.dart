import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/bottom_sheet.dart';

/// The capture sheet's two source tiles are the one Phase 4 control that the
/// brutal migration did not have to invent — they were already an enabled
/// [InkWell] — so they are also the one most likely to keep working by
/// accident. This file pins the three things a modal sheet can get wrong.
///
/// A `showModalBottomSheet` traps traversal: if the option has no [Focus], Tab
/// walks out of an empty sheet and Enter activates nothing, which is a live
/// keyboard regression that no colour or shadow assertion would ever see.
void main() {
  /// The sheet chrome is a plain [Container], so the only [AnimatedContainer]s
  /// in the tree are the two source tiles. `.first` is the Camera tile, which is
  /// the one the single Tab below lands on.
  BoxDecoration decorationOf(WidgetTester tester) => (tester
      .widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(PremiumBottomSheet),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      )
      .decoration) as BoxDecoration;

  Border borderOf(WidgetTester tester) =>
      decorationOf(tester).border! as Border;

  testWidgets(
      'the source option is reachable by Tab, rings, and fires on Enter',
      (tester) async {
    var camera = 0;
    var gallery = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: PremiumBottomSheet(
              onCamera: () => camera++,
              onGallery: () => gallery++,
            ),
          ),
        ),
      ),
    );

    // The ring first, for the same reason the button and chip tests assert it
    // first: a zero counter below is only meaningful if we know the key
    // actually reached THIS tile. Ring asserted last could not tell a missed
    // activation apart from a Tab that went somewhere else entirely.
    expect(borderOf(tester).top.color, SiftColors.light.stone);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // Focus landed, and the ring replaced the stone border in place — the
    // sheet control follows the same §5.4 rule as the chip and the button, at
    // the same 2pt width, so a focusable-but-invisible tile fails here.
    expect(borderOf(tester).top.color, SiftBrutal.focusLight);
    expect(borderOf(tester).top.width, SiftBrutal.borderW);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(camera, 1);
    expect(gallery, 0);
  });
}
