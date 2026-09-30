import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/screens/chat_screen.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/widgets/brutal_button.dart';

import 'wcag_contrast.dart';

/// The chat send circle is a control: reachable, activatable, and ringed.
///
/// DESIGN-BRUTALIST.md §7.6 recorded it as the one interactive element in the
/// app left outside the brutal control system — a bare `GestureDetector` with no
/// `Focus`, no `Actions` and no `Semantics(button:)`. It was therefore not
/// Tab-reachable and Enter did nothing on it, while being the primary action of
/// the screen it lives on.
///
/// §2.5 does exclude circular icon buttons from the hard-edge treatment, and
/// that exclusion is honoured: the press-scale, the fill, the shape and the
/// absence of a cast shadow are all unchanged, and these tests pin the press-scale
/// and the shadow so the focus work cannot quietly become a restyle. What §2.5
/// over-reached on was focus, which is not a shape question, so the ring is a 2pt
/// border on the same circle rather than a square around it.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool enabled,
    required VoidCallback onPressed,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SiftSendCircle(enabled: enabled, onPressed: onPressed),
          ),
        ),
      ),
    );
    // MaterialApp wraps its theme in an AnimatedTheme, so a re-pump that swaps
    // light for dark is still interpolating and every colour read below would
    // come out as a lerp of the two palettes. Settle before reading anything.
    await tester.pumpAndSettle();
  }

  /// The circle's own decoration, read off the mounted tree. Scoped to the send
  /// button because a sibling `BrutalButton` paints an `AnimatedContainer` too.
  BoxDecoration decoration(WidgetTester tester) => tester
      .widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(SiftSendCircle),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .decoration as BoxDecoration;

  /// The focus ring as painted, or null while unfocused.
  Border? ring(WidgetTester tester) => decoration(tester).border as Border?;

  group('keyboard reachability', () {
    testWidgets('one Tab focuses it and lights the 2pt ring', (tester) async {
      await pump(tester, enabled: true, onPressed: _noop);

      expect(ring(tester), isNull, reason: 'nothing is focused at rest');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final painted = ring(tester);
      expect(painted, isNotNull,
          reason: 'the send button is not Tab-reachable');
      expect(painted!.top.width, SiftBrutal.borderW);
      // `accentDeep` is a slab, so the ring is the slab pair and not the plain
      // page-step one (§6.10). Same rule as the filled button.
      expect(painted.top.color, SiftBrutal.focusOnFillLight);
    });

    testWidgets('Enter fires onPressed on that first Tab', (tester) async {
      var fired = 0;
      await pump(tester, enabled: true, onPressed: () => fired++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Asserted before the activation so a zero below can only mean the intent
      // did nothing, never that the key went elsewhere: this is the proof the
      // node took focus.
      expect(ring(tester), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('Space fires it too', (tester) async {
      var fired = 0;
      await pump(tester, enabled: true, onPressed: () => fired++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(fired, 1);
    });

    testWidgets('the ring clears 3:1 against the fill it is painted on',
        (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final isDark = brightness == Brightness.dark;
        await pump(
          tester,
          enabled: true,
          onPressed: _noop,
          brightness: brightness,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        final box = decoration(tester);
        final fill = box.color!;
        expect(fill.a, greaterThan(0));
        expect((box.border! as Border).top.color,
            SiftBrutal.focusOnFill(isDark: isDark));

        expect(
          wcagContrast((box.border! as Border).top.color, fill),
          greaterThanOrEqualTo(kNonTextContrast),
          reason: 'send circle ring on its own fill, $brightness = '
              '${wcagContrast((box.border! as Border).top.color, fill).toStringAsFixed(2)}:1',
        );
      }
    });

    testWidgets('it is one tab stop', (tester) async {
      // The send button and a second control, so tab order is decidable rather
      // than depending on what happens to follow the last focusable in the tree.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Row(
              children: [
                SiftSendCircle(enabled: true, onPressed: _noop),
                SizedBox(width: 24),
                BrutalButton(onPressed: _noop, child: Text('After')),
              ],
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester), isNotNull);

      // A single Tab past the circle must leave it. Before the fix the bare
      // GestureDetector had no focus node at all and this first Tab went
      // straight to the button; had the fix added a wrapper `Focus` above the
      // control's own, this would land back on the wrapper instead.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester), isNull, reason: 'the send button is two tab stops');
    });
  });

  group('semantics', () {
    testWidgets('announces as a named button', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, enabled: true, onPressed: _noop);

      final node = tester.getSemantics(find.byType(SiftSendCircle));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, 'Send message');
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('announces as disabled and does not send', (tester) async {
      // `enabled: widget.enabled` plus a null `onActivate` plus a null `onTap`.
      // A disabled control that still fired would be worse than one that never
      // reached the focus at all.
      var fired = 0;
      final handle = tester.ensureSemantics();
      await pump(tester, enabled: false, onPressed: () => fired++);

      final node = tester.getSemantics(find.byType(SiftSendCircle));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);

      // Still reachable, so the non-firing below is a real check.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final painted = ring(tester);
      expect(painted, isNotNull);
      // A disabled circle fills with `surfaceWarm2`, a page step, so it takes
      // the plain ring rather than the slab one.
      expect(painted!.top.color, SiftBrutal.focusLight);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fired, 0, reason: 'a disabled send button fired');

      await tester.tap(find.byType(SiftSendCircle), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fired, 0, reason: 'a disabled send button answered a tap');
      handle.dispose();
    });

    testWidgets('the disabled ring still clears 3:1 on its own fill',
        (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pump(
          tester,
          enabled: false,
          onPressed: _noop,
          brightness: brightness,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        final box = decoration(tester);
        expect(
          wcagContrast((box.border! as Border).top.color, box.color!),
          greaterThanOrEqualTo(kNonTextContrast),
          reason: 'disabled send circle ring on its own fill, $brightness',
        );
      }
    });
  });

  group('existing treatment is untouched', () {
    testWidgets('the tap still fires and still press-scales', (tester) async {
      var fired = 0;
      await pump(tester, enabled: true, onPressed: () => fired++);

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(AnimatedContainer)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        0.94,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, 1);
    });

    testWidgets('it is still a bare circle with no cast shadow',
        (tester) async {
      // §2.5's exclusion, pinned: a down-right offset shadow fights a circle's
      // curvature, so the send button must not grow one. Only the focus ring is
      // new.
      await pump(tester, enabled: true, onPressed: _noop);

      final box = decoration(tester);
      expect(box.shape, BoxShape.circle);
      expect(box.boxShadow, isNull);
      expect(tester.getSize(find.byType(AnimatedContainer)),
          const Size(SiftSpacing.sendBtn, SiftSpacing.sendBtn));
      expect(box.color, SiftColors.light.accentDeep);
    });
  });
}

void _noop() {}
