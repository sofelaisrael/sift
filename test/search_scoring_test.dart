import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

/// A field weight is a per-field score, not a per-occurrence multiplier.
///
/// The index writer used to add the field weight once per token the splitter
/// emitted, so a word repeated three times inside an 80-character `summary`
/// scored 15 against the same word mentioned once — the effective weight of a
/// record grew with how loudly it repeated itself rather than with where the
/// word came from. These two tests pin the rule: repetition inside one field
/// changes nothing, and a term that genuinely appears in two different fields
/// still scores the sum of both.
///
/// The weight values themselves are unmeasured constants and are deliberately
/// not asserted here beyond their ordering — recalibrating them is a separate,
/// measurement-gated task. What is asserted is that 5 + 1 still beats 3 + 2,
/// which only holds if a field contributes once and fields add up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_scoring_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<ScreenshotProvider> buildProvider() async {
    await Hive.openBox('screenshots');
    return ScreenshotProvider(
      ocr: OCRService(extractOverride: (_) async => ''),
    );
  }

  /// Ingest through the production write path and return the new id. Every
  /// write here succeeds: paths are distinct and nothing is being deleted.
  Future<String> ingest(
    ScreenshotProvider provider, {
    required String path,
    required int day,
    required String ocrText,
    List<String>? objects,
  }) async {
    final id = await provider.addFromBulkIngest(
      path: path,
      capturedAt: DateTime(2026, 1, day),
      ocrText: ocrText,
      objects: objects,
    );
    return id!;
  }

  test('a term repeated in one field scores the same as a term used once',
      () async {
    final provider = await buildProvider();

    // The term sits on the second line so it reaches `ocrText` (weight 1) and
    // not the `summary` slice (weight 5). That isolates the field under test:
    // the only difference between the first two records is how often the word
    // is said.
    final once = await ingest(provider,
        path: '/g/once.png', day: 1, ocrText: 'Header line\nnoodle total');
    final thrice = await ingest(provider,
        path: '/g/thrice.png',
        day: 2,
        ocrText: 'Header line\nnoodle noodle noodle');
    // Two controls that must outrank a single `ocrText` hit: 2 for the visual
    // label on `objects`, 3 for the user tag.
    final labelled = await ingest(provider,
        path: '/g/labelled.png',
        day: 3,
        ocrText: 'Header line',
        objects: const ['noodle']);
    final tagged = await ingest(provider,
        path: '/g/tagged.png', day: 4, ocrText: 'Header line');
    await provider.addTag(tagged, 'noodle');

    final hits = provider.search('noodle');

    // 3 and 2 come first. Counting occurrences would score `thrice` at 3, which
    // pushes `labelled` (2) to third and leaves the tail a single record
    // instead of the two equal OCR hits.
    expect(hits.take(2).map((s) => s.id), [tagged, labelled]);
    // The two OCR hits are equal, so they share the tail in either order.
    expect(hits.skip(2).map((s) => s.id).toSet(), {once, thrice});
    expect(hits.map((s) => s.id).toSet(), {once, thrice, labelled, tagged},
        reason: 'every record mentions the term, so none is dropped outright');
  });

  test('a term in both summary and ocrText scores the sum of both weights',
      () async {
    final provider = await buildProvider();

    // `summary` is the first line of `ocrText`, so 'noodle' is in both fields
    // and legitimately scores 5 + 1. It is repeated inside the summary on
    // purpose: that repetition is what this test neutralises, and it is what
    // makes the test fail if the index writer counts occurrences again.
    final both = await ingest(provider,
        path: '/g/both.png', day: 1, ocrText: 'noodle noodle shop');
    // 5 (summary) + 1 (ocrText) + 3 (tag) = 9. The same summary copy plus a
    // user tag must still outrank the summary-plus-OCR pair.
    final tagged = await ingest(provider,
        path: '/g/tagged.png', day: 2, ocrText: 'noodle shop');
    await provider.addTag(tagged, 'noodle');
    // 3 (tag) + 2 (objects) = 5, with no summary copy of the word at all, so
    // this is the floor the 5 + 1 pair has to clear.
    final labelled = await ingest(provider,
        path: '/g/labelled.png',
        day: 3,
        ocrText: 'unrelated line',
        objects: const ['noodle']);
    await provider.addTag(labelled, 'noodle');

    expect(
      provider.search('noodle').map((s) => s.id),
      [tagged, both, labelled],
      reason: 'the cross-field double count is deliberate — a term in summary '
          'and ocrText scores 5 + 1, which beats 3 + 2 and loses to 5 + 1 + 3. '
          'Counting occurrences instead scores `both` at 12 and puts it first.',
    );
  });
}
