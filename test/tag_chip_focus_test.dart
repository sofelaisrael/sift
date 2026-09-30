import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';
import 'package:screensort_lam/widgets/widgets.dart';

/// The `TagChip` delete target is ONE tab stop and Enter works on the FIRST Tab.
///
/// The brutal focus ring arrived as a `Focus` wrapped AROUND the delete
/// target's `InkWell`. In this SDK `InkResponse.build` is
///
///   Actions(actions: {ActivateIntent, ButtonActivateIntent}, child: Focus(...))
///
/// so the wrapping `Focus` was inserted BETWEEN those Actions and the
/// `InkWell`'s own node. Being a plain focusable node it attached to the
/// traversal order first and was traversed first, which produced two defects
/// from one change:
///
///  * the chip took TWO Tabs to reach, and
///  * the first of them was inert — the ring lit, and Enter dispatched
///    `ActivateIntent` upward from a context whose nearest handler was nothing,
///    because `WidgetsApp.defaultActions` registers neither intent. Nothing
///    happened. Only Tab #2 worked.
///
/// Before the brutalist change the `InkWell` was a single tab stop with its own
/// `Actions` ancestor, so Enter worked on the first Tab. The ring had traded a
/// working control for a doubled stop whose first landing did nothing, on the
/// home filter row and on the detail screen's tag editor alike.
///
/// The fix reads the ring off the `InkWell`'s own focus (`onFocusChange`) rather
/// than adding a node, so this file pins three things: one tab stop, Enter
/// firing on that first Tab, and the ring still being there.
void main() {
  const label = 'Receipts';

  /// The 40pt delete target's circle, found by its shape. The pill above it is
  /// also a `Container` with a `BoxDecoration`, so the shape is what makes this
  /// unambiguous rather than the index.
  Container deleteTarget(WidgetTester tester) {
    final circles = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TagChip),
            matching: find.byType(Container),
          ),
        )
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle)
        .toList();
    expect(circles, hasLength(1), reason: 'the delete target circle');
    return circles.single;
  }

  /// The ring as painted, or null when the target is unfocused.
  Border? ring(WidgetTester tester) =>
      (deleteTarget(tester).decoration! as BoxDecoration).border as Border?;

  /// The chip and a second control behind it, so tab order is decidable rather
  /// than depending on what happens to follow the last focusable in the tree.
  Future<void> pump(WidgetTester tester, VoidCallback onDeleted) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Row(
            children: [
              TagChip(label: label, onDeleted: onDeleted),
              const SizedBox(width: 24),
              const BrutalButton(onPressed: _noop, child: Text('After')),
            ],
          ),
        ),
      ),
    );
  }

  group('one tab stop', () {
    testWidgets('the first Tab lands on the delete target and lights the ring',
        (tester) async {
      await pump(tester, _noop);

      expect(ring(tester), isNull, reason: 'nothing is focused at rest');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // `_deleteFocused` is written from exactly one place — the InkWell's own
      // focus callback — so a lit ring proves the FIRST Tab reached the
      // InkWell's node rather than some wrapper above it.
      final painted = ring(tester);
      expect(painted, isNotNull,
          reason: 'the first Tab did not focus the target');
      expect(painted!.top.color, SiftBrutal.focusLight);
      expect(painted.top.width, SiftBrutal.borderW);
    });

    testWidgets('the second Tab leaves the chip entirely', (tester) async {
      // The doubling is the defect this file exists for, so it is asserted
      // directly: a single Tab past the target must not come back to it. With
      // the old wrapping `Focus` this landed back on the outer node and the ring
      // was still lit here.
      await pump(tester, _noop);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester), isNull, reason: 'the chip is two tab stops');
    });
  });

  group('Enter activates', () {
    testWidgets('on the FIRST Tab, with the ring already asserted lit',
        (tester) async {
      var fired = 0;
      await pump(tester, () => fired++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Ordered before the activation so a zero below can never be a misdelivered
      // key: this is the assertion that the key reached the target.
      expect(ring(tester), isNotNull,
          reason: 'focus never landed on the delete target');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(fired, 1, reason: 'Enter on the first Tab did nothing');
    });

    testWidgets('Space activates too, off the same single node',
        (tester) async {
      // Both keys route through `ActivateIntent`, which the InkWell's own
      // Actions handles; this pins that the fix did not bind Enter only.
      var fired = 0;
      await pump(tester, () => fired++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(fired, 1);
    });

    testWidgets('the next Tab reaches the control after the chip',
        (tester) async {
      // Proves the first Tab was not swallowed by a wrapper that then had to be
      // tabbed past: focus continues forward from the delete target.
      var fired = 0;
      var after = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Row(
              children: [
                TagChip(label: label, onDeleted: () => fired++),
                const SizedBox(width: 24),
                BrutalButton(
                    onPressed: () => after++, child: const Text('After')),
              ],
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(after, 1, reason: 'focus did not move forward off the chip');
    });
  });

  group('dark mode', () {
    testWidgets('the ring is the dark page-step colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: TagChip(label: label, onDeleted: _noop),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // The target's own box carries no fill, so the ring is scored against the
      // `paper` pill beneath it — a page step, hence `focus` and not `focusOnFill`
      // (§4.6).
      expect(ring(tester)!.top.color, SiftBrutal.focusDark);
    });
  });

  testWidgets('a chip with no delete target contributes no focusable node', (
    tester,
  ) async {
    // The label-only chip is a label, not a control (§2.5). Nothing to break,
    // and this guards the opposite mistake: adding focus machinery to the pill.
    // The assertion is on the SUBTREE rather than on `primaryFocus`, because a
    // Tab in an otherwise empty tree lands on the route's own focus scope.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: TagChip(label: label)),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(
      find.descendant(of: find.byType(TagChip), matching: find.byType(Focus)),
      findsNothing,
    );
  });
}

void _noop() {}
