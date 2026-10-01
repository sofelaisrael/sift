import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

/// `ScreenshotProvider.explainScores()` — the additive accessor that reports
/// which field earned each part of a score `search()` ranked on.
///
/// Nothing here asserts that a weight is *right*. Phase 0 exists because the
/// weights are unmeasured, and a test that went red when they looked wrong would
/// push whoever ran it to tune them or delete the baseline. What is asserted is
/// the accessor's own contract, which is narrower and has to hold whatever the
/// weights are:
///
///   1. the per-field breakdown adds up to the total score — the invariant that
///      makes attribution a decomposition rather than a second opinion;
///   2. a hit reachable through one field attributes entirely to that field;
///   3. a term in two fields attributes to both, which is the deliberate 5 + 1
///      double count between `summary` and `ocrText`;
///   4. a query with no results returns an empty explanation, not an error;
///   5. calling it changes nothing `search()` returns.
///
/// (1) is the load-bearing one. The accessor recomputes the per-field split from
/// the record, so a future write path that indexes a field the split does not
/// know about would silently under-report. That shows up as a sum that does not
/// add up, and `contributionsMatchScore` is the flag that says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_explanation_');
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

  /// Write one fully-populated row straight into the box.
  ///
  /// The production write path cannot fill `description`, `searchKeywords`,
  /// `recognitions` or `extractedData` — they are null / [] on every record the
  /// local analyzer writes — so a test that wants every weighted field indexed
  /// has to put the row there itself and let `loadScreenshots()` build the index
  /// from the stored JSON. Every other record in this file is still written
  /// through the production path.
  Future<void> putFullRecord({
    required String id,
    required String fileName,
    required String summary,
    String? description,
    List<String>? tags,
    List<String>? objects,
    List<String>? recognitions,
    List<String>? searchKeywords,
    Map<String, String>? extractedData,
    required String ocrText,
  }) async {
    await Hive.box('screenshots').put(id, <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'filePath': '/x/$fileName',
      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
      'ocrText': ocrText,
      'lamType': 'document',
      'summary': summary,
      'actionType': null,
      'actionCompleted': false,
      'actionResult': null,
      'description': description,
      'objects': objects ?? const <String>[],
      'recognitions': recognitions ?? const <String>[],
      'webResults': const <Map<String, String>>[],
      'isFavorite': false,
      'tags': tags ?? const <String>[],
      'suggestedAction': null,
      'extractedData': extractedData,
      'searchKeywords': searchKeywords ?? const <String>[],
    });
  }

  /// Seed one record through the production write path, which is enough for
  /// every field the local analyzer can actually fill.
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

  group('the breakdown adds up to the score', () {
    test('every result of every query, over a record with all nine fields',
        () async {
      final provider = await buildProvider();
      // 'Albatross' is on the first line so it lands in both `summary` (5) and
      // `ocrText` (1); 'Zeppelin' is only in `description` (4) and the OCR body;
      // the rest give one field apiece, so the invariant is exercised on
      // single-field, two-field and three-field results alike.
      await putFullRecord(
        id: 'full',
        fileName: 'full.png',
        summary: 'Albatross',
        description: 'Zeppelin tail',
        tags: const <String>['Kestrel'],
        objects: const <String>['Falcon'],
        recognitions: const <String>['Osprey'],
        searchKeywords: const <String>['Harrier'],
        extractedData: const <String, String>{'Merlin': 'Vulture'},
        ocrText: 'Albatross flight log\nZeppelin tail number 4471',
      );
      await ingest(provider,
          path: '/x/plain.png', day: 2, ocrText: 'Nothing relevant here');
      await provider.loadScreenshots();

      const List<String> queries = <String>[
        'albatross',
        'zeppelin',
        'kestrel',
        'falcon',
        'osprey',
        'harrier',
        'merlin',
        'vulture',
        'full',
        'flight',
        'tail',
        'albatross zeppelin',
        'albatross zeppelin kestrel falcon osprey harrier',
        'nosuchtokenanywhere',
      ];

      int checked = 0;
      for (final String q in queries) {
        final List<Screenshot> ranked = provider.search(q, limit: 20);
        final SearchExplanation explained =
            provider.explainScores(q, limit: 20);

        expect(explained.results.map((SearchScoreExplanation r) => r.fileName),
            ranked.map((Screenshot s) => s.fileName),
            reason: 'explainScores() must return the same records, in the same '
                'order, as search() did for "$q"');
        expect(explained.isConsistent, isTrue,
            reason: 'every breakdown for "$q" must add up');

        for (int i = 0; i < explained.results.length; i++) {
          final SearchScoreExplanation r = explained.results[i];
          expect(r.contributionsSum,
              r.fieldContributions.values.fold(0, (int a, int b) => a + b),
              reason: 'contributionsSum must be the map summed');
          expect(r.contributionsSum, r.score,
              reason: 'for "$q" rank ${i + 1} (${r.fileName}) the per-field '
                  'weights must account for the whole score');
          expect(r.contributionsMatchScore, isTrue);
          checked++;
        }
      }
      expect(checked, greaterThan(0),
          reason:
              'the invariant must actually have been asserted on something');
    });

    test('a term reachable through three fields names all three and adds up',
        () async {
      // `contributionsMatchScore` is computed from the map, never assumed. It
      // cannot be forced false from a test today, and that is the design: the
      // split is derived through the same `_indexedFields` table the index was
      // built from, so within this version of `lib/` the two always agree. The
      // flag is here for the day a write path indexes something the split does
      // not describe, and what this pins is that the sum is read off the map
      // rather than the map being assumed to cover the score.
      final provider = await buildProvider();
      final id = await ingest(provider,
          path: '/x/one.png', day: 1, ocrText: 'zeppelin tail number');
      await provider.addTag(id, 'zeppelin');

      final SearchScoreExplanation r =
          provider.explainScores('zeppelin', limit: 5).results.single;
      expect(r.fieldContributions,
          <String, int>{'summary': 5, 'ocrText': 1, 'tags': 3},
          reason:
              'the term is on the first line, so it is in the summary slice '
              'and the OCR body, and the user also tagged it');
      expect(r.score, 9);
      expect(r.contributionsSum,
          r.fieldContributions.values.fold(0, (int a, int b) => a + b));
      expect(r.contributionsMatchScore, isTrue);
    });
  });

  test('a hit reachable through one field attributes 100% to that field',
      () async {
    final provider = await buildProvider();
    // 'Noodle' on the second line, so it reaches `ocrText` (1) and not the
    // `summary` slice (5). Nothing else in this corpus says it, so the whole
    // score has to belong to `ocrText` -- there is nowhere else for it to come
    // from.
    await ingest(provider,
        path: '/x/first.png', day: 1, ocrText: 'Header line\nnoodle special');
    await ingest(provider,
        path: '/x/second.png', day: 2, ocrText: 'Header line\nno relation');
    await provider.loadScreenshots();

    final SearchScoreExplanation r =
        provider.explainScores('noodle', limit: 5).results.single;

    expect(r.fileName, 'first.png');
    expect(r.fieldContributions, <String, int>{'ocrText': 1});
    expect(r.score, 1);
    expect(r.contributionsMatchScore, isTrue,
        reason: '100% of the score is one field, so it must add up exactly');
  });

  test('a term in both summary and ocrText attributes to both', () async {
    final provider = await buildProvider();
    // `summary` is the first line of `ocrText`, so 'noodle' is genuinely in both
    // fields and the index really does score both (5 + 1). Attributing it to
    // one of them would understate the record and overstate the other.
    await ingest(provider,
        path: '/x/both.png', day: 1, ocrText: 'noodle shop\ntotal 4.20');
    await provider.loadScreenshots();

    final SearchScoreExplanation r =
        provider.explainScores('noodle', limit: 5).results.single;

    expect(r.fieldContributions, <String, int>{'summary': 5, 'ocrText': 1},
        reason: 'the cross-field double count is deliberate, and attribution '
            'has to show both halves of it');
    expect(r.score, 6);
    expect(r.contributionsSum, 6);
    expect(r.contributionsMatchScore, isTrue);
  });

  test('a query with no results is empty, not an error', () async {
    final provider = await buildProvider();
    await ingest(provider,
        path: '/x/one.png', day: 1, ocrText: 'something readable');
    await provider.loadScreenshots();

    // Three ways to come back with nothing: nothing matches, the query is under
    // the minimum length, and the query has no usable term at all. Each must be
    // an empty explanation.
    for (final String q in <String>[
      'nosuchtokenanywhere',
      'x',
      '   ',
      '',
      '--',
    ]) {
      final SearchExplanation e = provider.explainScores(q, limit: 5);
      expect(e.query, q);
      expect(e.results, isEmpty,
          reason: 'no results for "$q" is an empty '
              'explanation, not a failure');
      expect(e.isConsistent, isTrue,
          reason: 'an empty explanation is vacuously consistent; it must not '
              'report a mismatch it has no rows for');
      expect(provider.search(q, limit: 5), isEmpty,
          reason: 'and it must agree with search() about there being nothing');
    }
  });

  test('search() returns the identical ranked list after the accessor ran',
      () async {
    final provider = await buildProvider();
    for (int i = 0; i < 12; i++) {
      final id = await ingest(provider,
          path: '/x/shot_$i.png',
          day: i + 1,
          ocrText: 'Record $i\nalbatross line ${i % 4} tagword',
          objects: const <String>['Falcon', 'Food']);
      if (i % 3 == 0) await provider.addTag(id, 'tagword');
    }
    await provider.loadScreenshots();

    const List<String> queries = <String>[
      'albatross',
      'record',
      'record 3',
      'tagword',
      'falcon',
      'shot_4',
      'shot_11',
      'line',
      'line 0',
      'albatross line tagword falcon shot_4',
      'nosuchtokenanywhere',
      'x',
    ];

    List<List<String>> capture() => queries
        .map((String q) => provider
            .search(q, limit: 20)
            .map<String>((Screenshot s) => s.fileName)
            .toList())
        .toList();

    final List<List<String>> before = capture();

    // Call the accessor over the same queries and over a second, disjoint set,
    // twice, so a mutation of the index or of a record would have to survive
    // being looked at before the second capture.
    for (int pass = 0; pass < 2; pass++) {
      for (final String q in queries) {
        provider.explainScores(q, limit: 20);
      }
      provider.explainScores('anything at all', limit: 20);
      provider.explainScores('café', limit: 1);
    }

    expect(capture(), before,
        reason: 'explainScores() is additive and read-only; it must not move a '
            'single rank');

    // ...and the same holds for the scores themselves, which is the property the
    // harness depends on when it reads them.
    final SearchExplanation a = provider.explainScores('albatross', limit: 20);
    final SearchExplanation b = provider.explainScores('albatross', limit: 20);
    expect(
      a.results
          .map((SearchScoreExplanation r) =>
              '${r.fileName}:${r.score}:${r.contributionsSum}')
          .toList(),
      b.results
          .map((SearchScoreExplanation r) =>
              '${r.fileName}:${r.score}:${r.contributionsSum}')
          .toList(),
    );
  });
}
