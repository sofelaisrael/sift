import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/theme/app_theme.dart';
import 'package:screensort_lam/theme/brutal_tokens.dart';
import 'package:screensort_lam/theme/motion_tokens.dart';
import 'package:screensort_lam/widgets/bottom_sheet.dart';
import 'package:screensort_lam/widgets/brutal_chip.dart';
import 'package:screensort_lam/widgets/chat_atoms.dart';
import 'package:screensort_lam/widgets/skeleton.dart';
import 'package:screensort_lam/widgets/widgets.dart';

import 'wcag_contrast.dart';

/// The §2.5 reversal: the hard edge on read-only surfaces.
///
/// Ten surface families were brought into the brutal set after a device
/// review. They share one geometry, so the assertions here are deliberately
/// about VALUES rather than about pixels: radius, border width, edge colour and
/// shadow are read off the mounted tree, and the shadow is compared to
/// `SiftBrutal.hard(isDark)` rather than to a restated literal. That makes a
/// revert fail, and it makes a second shadow direction fail, without a
/// screenshot.
///
/// No golden and no `RenderRepaintBoundary.toImage` anywhere in this file: a
/// previous attempt at this work hung the whole suite on 300s+ timeouts. Every
/// assertion here is a property read off a widget tree or off a source file.
///
/// Light and dark are SEPARATE tests rather than a loop over both modes inside
/// one. Re-pumping a `MaterialApp` with a different theme inside one
/// `testWidgets` does not reliably rebuild every nested `Container`, and a
/// helper that silently matches nothing is worse than a helper that cannot be
/// called twice.
void main() {
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
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  /// The one hard-edged box of a given fill. Every surface in this file is a
  /// `Container` whose decoration came from `brutalEdge`, and none of them
  /// nests a second decorated box of the same fill — which is what lets a fill
  /// be the finder rather than an index.
  BoxDecoration boxFilledWith(WidgetTester tester, Color fill) {
    final matches = tester
        .widgetList<Container>(
          find.descendant(
              of: find.byType(Scaffold), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color == fill)
        .toList();
    expect(matches, hasLength(1), reason: 'exactly one $fill box');
    return matches.single;
  }

  Border borderOf(BoxDecoration decoration) => decoration.border! as Border;

  /// The four values every hard-edged read-only surface shares. Asserted in one
  /// place so a surface cannot take three of the four and pass.
  void expectHardEdge(
    BoxDecoration decoration,
    Color edge,
    List<BoxShadow> shadow, {
    BorderRadius? radius,
  }) {
    expect(
      decoration.borderRadius,
      radius ?? BorderRadius.circular(SiftRadii.rControl),
    );
    expect(borderOf(decoration).top.width, SiftBrutal.borderW);
    expect(borderOf(decoration).top.color, edge);
    expect(decoration.boxShadow, shadow);
  }

  Future<String> source(String path) => File(path).readAsString();

  /// The source of the single `BrutalButton` constructor call whose
  /// `onPressed` is [callback] — the whole call, parens balanced.
  ///
  /// A file-level `contains('variant: BrutalVariant.outline')` cannot pin ONE
  /// button: the "Find online" button is also `outline`, so the substring
  /// survives this button being turned `filled`, `destructive` or `text`.
  /// Slicing by callback is what makes the variant assertion unique.
  ///
  /// Parens inside a string literal would end the slice early; no call site in
  /// this file has one.
  String buttonSource(String source, String callback) {
    final onPressed = source.indexOf('onPressed: $callback');
    expect(onPressed, isNot(-1), reason: 'no button calls $callback');
    final start = source.lastIndexOf('BrutalButton', onPressed);
    expect(start, isNot(-1), reason: 'no BrutalButton wraps $callback');
    final open = source.indexOf('(', start);

    var depth = 0;
    for (var i = open; i < source.length; i++) {
      if (source[i] == '(') {
        depth++;
      } else if (source[i] == ')') {
        depth--;
        if (depth == 0) return source.substring(start, i + 1);
      }
    }
    fail('unbalanced constructor call for $callback');
  }

  group('the card and its skeleton', () {
    testWidgets('the skeleton is rControl, a 2pt edge and the hard shadow',
        (tester) async {
      await pump(tester, const ScreenshotCardSkeleton());

      expectHardEdge(
        boxFilledWith(tester, SiftColors.light.paper),
        SiftBrutal.surfaceEdgeLight,
        SiftBrutal.hardLight,
      );
    });

    testWidgets('dark mode swaps the edge and the shadow, not the radius',
        (tester) async {
      await pump(
        tester,
        const ScreenshotCardSkeleton(),
        brightness: Brightness.dark,
      );

      expectHardEdge(
        boxFilledWith(tester, SiftColors.dark.paper),
        SiftBrutal.surfaceEdgeDark,
        SiftBrutal.hardDark,
      );
    });

    testWidgets('the light card edge clears 3:1 on the fill it is painted on',
        (tester) async {
      await pump(tester, const ScreenshotCardSkeleton());
      final decoration = boxFilledWith(tester, SiftColors.light.paper);

      // A `BoxDecoration` border paints inside the box, ON TOP OF the fill, so
      // this is scored against `paper` and NOT against the page. The card was a
      // `divider` hairline at 1.42:1 light / 1.22:1 dark while being an
      // `InkWell`, which is the SC 1.4.11 failure the reversal fixes.
      expect(
        wcagContrast(borderOf(decoration).top.color, decoration.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });

    testWidgets('the dark card edge clears 3:1 on the fill it is painted on',
        (tester) async {
      await pump(
        tester,
        const ScreenshotCardSkeleton(),
        brightness: Brightness.dark,
      );
      final decoration = boxFilledWith(tester, SiftColors.dark.paper);

      expect(
        wcagContrast(borderOf(decoration).top.color, decoration.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });

    test('the skeleton and the real card resolve the same decoration',
        () async {
      // `_SiftCard` is private, so it cannot be mounted from a test. What CAN
      // be pinned is the mechanism: both build through the one `brutalEdge`
      // factory, and the card no longer names the old radius or the old shadow
      // at all. Read the card's own source for that half rather than pretending
      // a widget assertion covers a widget this file cannot see.
      final home = await source('lib/screens/home_screen.dart');
      expect(home, contains('decoration: brutalEdge('),
          reason: 'the library card must go through the shared factory');
      expect(home, isNot(contains('SiftRadii.rCard')));
      expect(home, isNot(contains('SiftElevation.card(')));

      final skeleton = await source('lib/widgets/skeleton.dart');
      expect(skeleton, contains('decoration: brutalEdge('));
    });

    test('cardTheme agrees with them', () {
      // Nothing in the app mounts a `Card` — `_SiftCard` and
      // `ScreenshotCardSkeleton` are Containers reading the same tokens — so
      // this block is the fallback for a future `Card`, and it must not be the
      // one soft surface left in the theme.
      final shape =
          AppTheme.lightTheme.cardTheme.shape! as RoundedRectangleBorder;

      expect(shape.borderRadius, BorderRadius.circular(SiftRadii.rControl));
      expect(shape.side.width, SiftBrutal.borderW);
      expect(shape.side.color, SiftBrutal.surfaceEdgeLight);
      expect(AppTheme.lightTheme.cardTheme.elevation, 0);
    });
  });

  group('the snackbar', () {
    test('is rControl with a 2pt slab edge and no blurred elevation', () {
      final theme = AppTheme.lightTheme.snackBarTheme;
      final shape = theme.shape! as RoundedRectangleBorder;

      expect(shape.borderRadius, BorderRadius.circular(SiftRadii.rControl));
      expect(shape.side.width, SiftBrutal.borderW);
      // `ink` is a slab fill in BOTH modes, so the edge is scored against it and
      // takes `edgeOnFill` — not the page-step `surfaceEdge`, which would have
      // measured 3.03:1 light and 0.40:1 dark on this fill.
      expect(shape.side.color, SiftBrutal.edgeOnFillLight);
      expect(theme.elevation, 0);
      expect(theme.backgroundColor, SiftColors.light.ink);
    });

    test('the light slab edge clears 3:1 and the text clears 4.5:1', () {
      final theme = AppTheme.lightTheme.snackBarTheme;
      final shape = theme.shape! as RoundedRectangleBorder;

      expect(
        wcagContrast(shape.side.color, theme.backgroundColor!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(theme.contentTextStyle!.color!, theme.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the dark slab edge clears 3:1 and the text clears 4.5:1', () {
      final theme = AppTheme.darkTheme.snackBarTheme;
      final shape = theme.shape! as RoundedRectangleBorder;

      expect(shape.side.color, SiftBrutal.edgeOnFillDark);
      expect(
        wcagContrast(shape.side.color, theme.backgroundColor!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(theme.contentTextStyle!.color!, theme.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the capture sheet', () {
    /// The chrome, not the two `_SourceOption` tiles inside it: `find.descendant`
    /// is pre-order, so `.first` is the outermost `Container` in the sheet.
    BoxDecoration sheetChrome(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(PremiumBottomSheet),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;

    testWidgets('chrome is rControl on the top corners with the hard shadow',
        (tester) async {
      await pump(
        tester,
        const PremiumBottomSheet(onCamera: _noop, onGallery: _noop),
      );

      expectHardEdge(
        sheetChrome(tester),
        SiftBrutal.surfaceEdgeLight,
        SiftBrutal.hardLight,
        // The sheet is flush with the bottom of the screen, so rounding all four
        // corners would show the modal barrier through four 4px notches.
        radius: const BorderRadius.vertical(
          top: Radius.circular(SiftRadii.rControl),
        ),
      );
    });

    testWidgets('dark mode swaps edge and shadow', (tester) async {
      await pump(
        tester,
        const PremiumBottomSheet(onCamera: _noop, onGallery: _noop),
        brightness: Brightness.dark,
      );

      expectHardEdge(
        sheetChrome(tester),
        SiftBrutal.surfaceEdgeDark,
        SiftBrutal.hardDark,
        radius: const BorderRadius.vertical(
          top: Radius.circular(SiftRadii.rControl),
        ),
      );
    });

    test('the themed sheet shape agrees with the widget', () {
      final shape =
          AppTheme.lightTheme.bottomSheetTheme.shape! as RoundedRectangleBorder;

      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(SiftRadii.rControl)),
      );
      expect(shape.side.width, SiftBrutal.borderW);
      expect(shape.side.color, SiftBrutal.surfaceEdgeLight);
    });
  });

  group('labels: TypeBadge and TagChip', () {
    testWidgets('both are rControl with a 2pt edge and NO cast shadow',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [TypeBadge(type: 'recipe'), TagChip(label: 'Receipts')],
        ),
      );

      final badge = boxFilledWith(tester, SiftColors.light.badgeBg);
      expectHardEdge(
        badge,
        SiftBrutal.surfaceEdgeLight,
        SiftBrutal.none,
      );
      final tag = boxFilledWith(tester, SiftColors.light.paper);
      expectHardEdge(tag, SiftBrutal.surfaceEdgeLight, SiftBrutal.none);
    });

    testWidgets('dark mode swaps the edge on both', (tester) async {
      await pump(
        tester,
        const Column(
          children: [TypeBadge(type: 'recipe'), TagChip(label: 'Receipts')],
        ),
        brightness: Brightness.dark,
      );

      expectHardEdge(
        boxFilledWith(tester, SiftColors.dark.badgeBg),
        SiftBrutal.surfaceEdgeDark,
        SiftBrutal.none,
      );
      expectHardEdge(
        boxFilledWith(tester, SiftColors.dark.paper),
        SiftBrutal.surfaceEdgeDark,
        SiftBrutal.none,
      );
    });

    testWidgets('a label is visibly NOT a chip: it casts, the chip does not',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            TypeBadge(type: 'recipe'),
            SizedBox(height: 8),
            SiftBrutalChip(label: 'Receipts', onTap: _noop),
          ],
        ),
      );

      final badge = boxFilledWith(tester, SiftColors.light.badgeBg);
      final chip = tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(SiftBrutalChip),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration as BoxDecoration;

      // Same radius, same border weight, different depth. Without this the
      // reversal would have made every badge in the app look pressable.
      expect(badge.borderRadius, chip.borderRadius);
      expect(borderOf(badge).top.width, borderOf(chip).top.width);
      expect(badge.boxShadow, SiftBrutal.none);
      expect(chip.boxShadow, SiftBrutal.hardLight);
    });

    testWidgets('a label contributes no focusable or tappable node',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [TypeBadge(type: 'recipe'), TagChip(label: 'Receipts')],
        ),
      );

      // A badge, and a tag with no delete target, are both labels. Scoped to the
      // subtree because `MaterialApp` itself contributes focus nodes.
      //
      // The scope is the widget itself, with no intermediate type in between:
      // `TypeBadge` is `Container > Text` and `TagChip` is `Container > Row`, so
      // scoping through some inner layout type matches zero widgets and every
      // assertion below would pass vacuously.
      for (final widget in [TypeBadge, TagChip]) {
        final scope = find.byType(widget);
        expect(scope, findsOneWidget);
        expect(
          find.descendant(of: scope, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(
            find.descendant(of: scope, matching: find.byType(GestureDetector)),
            findsNothing);
        expect(
          find.descendant(of: scope, matching: find.byType(Focus)),
          findsNothing,
          reason: 'a label is not a tab stop',
        );
      }
    });

    testWidgets('the light badge and tag keep 4.5:1 text and gain a 3:1 edge',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [TypeBadge(type: 'recipe'), TagChip(label: 'Receipts')],
        ),
      );

      const s = SiftColors.light;
      final badge = boxFilledWith(tester, s.badgeBg);
      final tag = boxFilledWith(tester, s.paper);

      // The FILL did not change, so these are carried over from before: badgeText
      // on badgeBg 6.08:1, tagText on paper 4.72:1. Recomputed from the mounted
      // fills rather than restated.
      expect(
          wcagContrast(s.badgeText, badge.color!), greaterThanOrEqualTo(4.5));
      expect(wcagContrast(s.tagText, tag.color!), greaterThanOrEqualTo(4.5));
      // The EDGE did change, so these are the numbers the reversal produced.
      expect(
        wcagContrast(borderOf(badge).top.color, badge.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(borderOf(tag).top.color, tag.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });

    testWidgets('the dark badge and tag keep 4.5:1 text and gain a 3:1 edge',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [TypeBadge(type: 'recipe'), TagChip(label: 'Receipts')],
        ),
        brightness: Brightness.dark,
      );

      const s = SiftColors.dark;
      final badge = boxFilledWith(tester, s.badgeBg);
      final tag = boxFilledWith(tester, s.paper);

      expect(
          wcagContrast(s.badgeText, badge.color!), greaterThanOrEqualTo(4.5));
      expect(wcagContrast(s.tagText, tag.color!), greaterThanOrEqualTo(4.5));
      expect(
        wcagContrast(borderOf(badge).top.color, badge.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(borderOf(tag).top.color, tag.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
    });
  });

  group('chat bubbles', () {
    testWidgets('the user bubble is rControl, 2pt edge, hard shadow, right',
        (tester) async {
      await pump(tester, const UserPill(text: 'What did I save?'));
      await tester.pumpAndSettle();

      final decoration = boxFilledWith(tester, SiftColors.light.surfaceWarm1);
      expectHardEdge(
        decoration,
        SiftBrutal.surfaceEdgeLight,
        SiftBrutal.hardLight,
      );
      expect(
        tester
            .widget<Align>(
              find.descendant(
                of: find.byType(UserPill),
                matching: find.byType(Align),
              ),
            )
            .alignment,
        Alignment.centerRight,
      );
      // The fill did not change, so the 16pt bodySans label keeps 12.57:1.
      expect(
        wcagContrast(SiftColors.light.ink, decoration.color!),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('dark mode swaps edge and shadow on the bubble',
        (tester) async {
      await pump(
        tester,
        const UserPill(text: 'What did I save?'),
        brightness: Brightness.dark,
      );
      await tester.pumpAndSettle();

      final decoration = boxFilledWith(tester, SiftColors.dark.surfaceWarm1);
      expectHardEdge(
        decoration,
        SiftBrutal.surfaceEdgeDark,
        SiftBrutal.hardDark,
      );
      expect(
        wcagContrast(SiftColors.dark.ink, decoration.color!),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('the assistant side carries no container edge at all',
        (tester) async {
      await pump(
        tester,
        const EssayBlock(
          text: 'You saved a flight to Lisbon.',
          showActions: false,
        ),
      );

      // Not "the essay has no border" — the essay is text. What is asserted is
      // that no box of its own was added under it. `BrutalButton` is an
      // `AnimatedContainer`, not a `Container`, so a button edge cannot leak in
      // here; `showActions: false` removes the question anyway.
      final outlines = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(EssayBlock),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null)
          .toList();
      expect(outlines, isEmpty,
          reason: 'the assistant essay must not be put in a hard box');

      // The serif voice is untouched: this is the one thing §9 protects and the
      // reversal must not have cost it. The style lives on the SPAN, not on the
      // `Text` — `Text.rich` is handed a `TextSpan` and leaves `style` null.
      final essay = tester
          .widget<Text>(
            find.textContaining('You saved a flight to Lisbon.'),
          )
          .textSpan!;
      expect(essay.style!.fontFamily, SiftType.serifFamily);
    });

    testWidgets('the two sides are told apart without colour alone',
        (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            UserPill(text: 'What did I save?'),
            EssayBlock(
                text: 'You saved a flight to Lisbon.', showActions: false),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final bubble = boxFilledWith(tester, SiftColors.light.surfaceWarm1);
      final essayBoxes = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(EssayBlock),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .toList();

      // Three differences, none of them a hue: the user turn has a 2pt edge and
      // a cast shadow, the assistant turn has no box at all, and the user turn is
      // the only right-aligned thing here. Giving the assistant a matching
      // bubble would have collapsed this into a symmetric pair that only colour
      // could still separate.
      expect(bubble.border, isNotNull);
      expect(bubble.boxShadow, SiftBrutal.hardLight);
      expect(essayBoxes.where((d) => d.border != null), isEmpty);

      final essayAligns = tester
          .widgetList<Align>(
            find.descendant(
              of: find.byType(EssayBlock),
              matching: find.byType(Align),
            ),
          )
          .toList();
      expect(essayAligns, isEmpty);
    });
  });

  group('the processing banner', () {
    testWidgets('is hard-edged, keeps the pulsing mark and the dismiss target',
        (tester) async {
      // Reduced motion so `PulsingMark`'s 1.2s repeat does not leave a live
      // ticker behind; the mark is still built either way.
      MotionTokens.reduced = true;
      addTearDown(() => MotionTokens.reduced = false);

      await pump(
        tester,
        const ProcessingBanner(
            message: 'Reading your screenshots…', onDismiss: _noop),
      );

      expectHardEdge(
        boxFilledWith(tester, SiftColors.light.surfaceWarm2),
        SiftBrutal.surfaceEdgeLight,
        SiftBrutal.hardLight,
      );
      // The two things the brief says must survive.
      expect(find.byType(PulsingMark), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('its light edge clears 3:1 and its 15pt label clears 4.5:1',
        (tester) async {
      await pump(
          tester, const ProcessingBanner(message: 'Reading your screenshots…'));

      const s = SiftColors.light;
      final decoration = boxFilledWith(tester, s.surfaceWarm2);
      expect(
        wcagContrast(borderOf(decoration).top.color, decoration.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(wcagContrast(s.ink, decoration.color!), greaterThanOrEqualTo(4.5));
    });

    testWidgets('its dark edge clears 3:1 and its 15pt label clears 4.5:1',
        (tester) async {
      await pump(
        tester,
        const ProcessingBanner(message: 'Reading your screenshots…'),
        brightness: Brightness.dark,
      );

      const s = SiftColors.dark;
      final decoration = boxFilledWith(tester, s.surfaceWarm2);
      expect(
        wcagContrast(borderOf(decoration).top.color, decoration.color!),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(wcagContrast(s.ink, decoration.color!), greaterThanOrEqualTo(4.5));
    });

    test('the ingest banner goes through the same factory', () async {
      // `IngestBanner` needs a live `IngestService`, and mounting one drags in
      // Hive and the provider. The honest coverage for it is that it resolves
      // through the shared factory with the same fill pair `ProcessingBanner`
      // uses; the behavioural half is asserted above.
      final banner = await source('lib/widgets/ingest_banner.dart');
      expect(banner, contains('decoration: brutalEdge('));
      expect(banner, isNot(contains('SiftRadii.rThumb')));
      expect(banner, contains('PulsingMark'));
    });
  });

  group('the OCR block and its copy button', () {
    test('the last Material button is gone from the detail screen', () async {
      final detail = await source('lib/screens/detail_screen.dart');

      expect(detail, isNot(contains('TextButton.')),
          reason: 'the sanctioned OCR exception was the last Material button '
              'in the app and the reversal retires it');
      expect(detail, isNot(contains('TextButton(')));
      expect(detail, contains('BrutalButton.icon('));
      // The outline variant, not the ghost: a ghost has no fill to lift it, so
      // its default `ink` label would measure 1.14:1 on this near-black slab.
      // Scoped to the copy button, because the "Find online" button further down
      // the file is also `outline` — a file-level substring would still pass if
      // this button became `filled`.
      expect(
        buttonSource(detail, '_copyOcr'),
        contains('variant: BrutalVariant.outline'),
      );
    });

    test('the copy button keeps the size the Material button had', () async {
      // §9 is an explicit non-goal for typography, and this is the one control
      // that actually moved. It is pinned because a 1pt reduction here is
      // invisible in review and still ships: the doc claiming "keeps
      // microLabel" was wrong, and the code had drifted with it.
      final button = buttonSource(
          await source('lib/screens/detail_screen.dart'), '_copyOcr');

      expect(button, contains('label: Text('));
      expect(button, contains('SiftType.metaLabel'),
          reason: 'the Material TextButton styled this 12pt metaLabel; '
              'microLabel here would be a silent 1pt reduction');
      expect(button, isNot(contains('SiftType.microLabel')));
      expect(button, isNot(contains('SiftType.buttonLabel')));
      // 36 is the Material `minimumSize` height, and the 12pt/1.3 line box is
      // 15.6dp — still under the 16dp icon, so neither grows the box.
      expect(button, contains('height: 36'));
      // 36 is the Material `minimumSize` height, and the 12pt/1.3 line box is
      // 15.6dp — still under the 16dp icon, so neither grows the box.
      expect(button, contains('height: 36'));
    });

    test('the block keeps its mono face and stays selectable', () async {
      final detail = await source('lib/screens/detail_screen.dart');

      expect(detail, contains('SelectableText'));
      expect(detail, contains('SiftType.ocrMono'));
      // Hard-edged, not softened: the block now goes through the factory.
      expect(detail, contains('fill: s.codeBg'));
      // Focus and keyboard activation now come from `BrutalButton` rather than
      // from a Material `side:` override, so the old state-only border is gone.
      expect(detail, isNot(contains('BorderSide.none')));
    });

    test('the 500-char OCR truncation is untouched', () async {
      // The brief names this behaviour. It lives in the chat engine, not the
      // detail screen, so the thing to prove is that neither file moved.
      final engine = await source('lib/services/chat_engine.dart');
      expect(
          engine, contains('static const int _ocrCharsPerScreenshot = 500;'));
      expect(engine, contains('ocr.substring(0, _ocrCharsPerScreenshot)'));

      final detail = await source('lib/screens/detail_screen.dart');
      expect(detail, isNot(contains('ocrText!.substring')),
          reason: 'the detail screen must not gain a second truncation');
    });

    test('the OCR block edge clears 3:1 on codeBg in both modes', () {
      // `stone` on `codeBg` is the tightest row in `surfaceEdge`: 3.45:1 light,
      // 5.74:1 dark. It clears 3:1, which is the point of the token.
      expect(
        wcagContrast(SiftBrutal.surfaceEdgeLight, SiftColors.light.codeBg),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      expect(
        wcagContrast(SiftBrutal.surfaceEdgeDark, SiftColors.dark.codeBg),
        greaterThanOrEqualTo(kNonTextContrast),
      );
      // And the mono text is unaffected: the fill did not change.
      expect(
        wcagContrast(SiftColors.light.codeText, SiftColors.light.codeBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        wcagContrast(SiftColors.dark.codeText, SiftColors.dark.codeBg),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('dividers', () {
    test('the themed default is the brutal weight', () {
      final dividerTheme = AppTheme.lightTheme.dividerTheme;

      expect(dividerTheme.thickness, SiftBrutal.borderW);
      expect(dividerTheme.space, SiftBrutal.borderW);
    });

    test('the eight row separators deliberately stay at the hairline',
        () async {
      // Every `Divider` in the app separates two rows of the SAME table, so a
      // 2pt rule there would mark a boundary that is not there. This test pins
      // the decision, including the count, so "we raised the theme and forgot
      // the call sites" cannot be mistaken for "we decided this".
      final files = [
        'lib/screens/actions_history_screen.dart',
        'lib/screens/detail_screen.dart',
        'lib/screens/onboarding_screen.dart',
        'lib/screens/settings_screen.dart',
        'lib/screens/shopping_list_screen.dart',
        'lib/widgets/about_dialog.dart',
      ];

      var sites = 0;
      for (final path in files) {
        final text = await source(path);
        // `[^)]` rather than `[^;]` so one match cannot swallow the next
        // `Divider` on the following line and quietly undercount.
        final matches =
            RegExp(r'Divider\([^)]*thickness: 1').allMatches(text).toList();
        sites += matches.length;
        expect(matches, isNotEmpty, reason: '$path lost its hairline override');
      }

      expect(sites, 8, reason: 'the row-separator count changed; re-decide');
    });
  });

  group('one shadow direction', () {
    test('no BoxShadow literal exists outside the two token files', () {
      // §6.3's mechanical check. It matters more after this change than before:
      // a dozen more surfaces now cast shadows, and the failure mode — one
      // surface with an offset of (3, 3) — reads as a bug, not a variation.
      const allowed = {
        'lib/theme/app_theme.dart',
        'lib/theme/brutal_tokens.dart'
      };
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (allowed.contains(path)) continue;
        if (entity.readAsStringSync().contains('BoxShadow(')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'a hand-written BoxShadow outside the token files is a '
              'second shadow direction');
    });

    test('no visible surface resolves a soft elevation any more', () {
      // The soft ramp stays in the palette on purpose (§9), but nothing that is
      // a visible surface may draw from it now.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == 'lib/theme/app_theme.dart') continue;
        final text = entity.readAsStringSync();
        if (RegExp(r'SiftElevation\.(card|sheet|l[1-5]|l4Dark)\b')
            .hasMatch(text)) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });
  });
}

void _noop() {}
