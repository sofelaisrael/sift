import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';
import 'package:screensort_lam/services/screenshot_analyzer.dart';

/// What `ScreenshotProvider._deriveDescription` writes, measured through the
/// production write paths.
///
/// `_deriveDescription` is private, so every assertion here goes through
/// `addFromBulkIngest` — the same call the recall harness and the ingest service
/// make — rather than through a hand-built `Screenshot`. A hand-built record
/// would let the test author supply the labels and the OCR and then assert that
/// the derivation used them, which proves nothing about the derivation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('description_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<ScreenshotProvider> seeded() async {
    await Hive.openBox('screenshots');
    return ScreenshotProvider(
      ocr: OCRService(extractOverride: (_) async => ''),
    );
  }

  /// The one record at `/probe/only.png`, or null if the write did not land.
  Future<Screenshot?> only(ScreenshotProvider provider) async =>
      provider.screenshots.length == 1 ? provider.screenshots.single : null;

  group('a record with visual labels gets a description', () {
    test('it is non-empty and says what the picture is', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: '',
        objects: const ['receipt', 'food'],
      );

      final record = await only(provider);
      expect(record, isNotNull);
      expect(record!.description, isNotNull);
      expect(record.description, isNotEmpty);
      // One sentence, plain, and it names the labels rather than gesturing at
      // them. ML Kit returns lowercase single labels, so they read mid-clause.
      expect(record.description, 'Looks like a receipt and food.');
      expect(record.description!.endsWith('.'), isTrue);
    });

    test('one label reads as a singular noun phrase', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: '',
        objects: const ['dog'],
      );

      final record = await only(provider);
      expect(record!.description, 'Looks like a dog.');
    });

    test('a label starting with a vowel gets "an", not "a"', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: '',
        objects: const ['apple'],
      );

      final record = await only(provider);
      expect(record!.description, 'Looks like an apple.');
    });

    test('the label list is capped so this stays a sentence', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: '',
        objects: const ['dog', 'grass', 'sky', 'tree', 'leash', 'ball'],
      );

      final record = await only(provider);
      // Three of six. The full list is still on `objects` and still indexed, so
      // the cap costs the index nothing.
      expect(record!.description, 'Looks like a dog, grass and sky.');
      expect(record.objects, hasLength(6));
    });
  });

  group('a description never repeats the summary', () {
    test('a first-line word is in the summary and not in the description',
        () async {
      final provider = await seeded();
      // `rent` is on the first line, so production puts it in the 80-character
      // summary slice, and it is also in the OCR body. A description that
      // quoted the OCR would say it a third time.
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: 'Rent invoice\nAmount due 240',
        objects: const ['receipt'],
      );

      final record = await only(provider);
      expect(record!.summary, 'Rent invoice');
      expect(record.summary!.toLowerCase().contains('rent'), isTrue);
      // Labels only: nothing from the OCR text at all.
      expect(record.description, 'Looks like a receipt.');
      expect(record.description!.toLowerCase().contains('rent'), isFalse);
      expect(record.description!.toLowerCase().contains('amount'), isFalse);
    });

    test('over a corpus, no description repeats its own summary', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/a.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: 'Noodle shop\nTotal 4.20\nCard 1234',
        objects: const ['food', 'plate'],
      );
      await provider.addFromBulkIngest(
        path: '/probe/b.png',
        capturedAt: DateTime(2026, 4, 2),
        ocrText: 'A very long first line that goes on and on and on and on and '
            'is cut at eighty characters right here\nSecond line',
        objects: const ['text'],
      );

      for (final record in provider.screenshots) {
        expect(record.description, isNotNull);
        // No word the OCR body holds may reappear in the description. The
        // description's own content words are the label words, so this is the
        // assertion that the two fields are not saying the same thing twice.
        final overlap = _ocrContentWords(record);
        expect(overlap, isEmpty,
            reason: '${record.filePath}: description repeats OCR words '
                '$overlap. The description is built from the labels only.');
      }
    });
  });

  group('a description is short', () {
    test('three labels on a long record still stay one sentence', () async {
      final provider = await seeded();
      final longLine = List<String>.filled(40, 'pad thai').join(' ');
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: longLine,
        objects: const ['food', 'plate', 'table'],
      );

      final record = await only(provider);
      expect(record!.description, 'Looks like a food, plate and table.');
      // Short enough to be a caption. This is rendered into the model prompt
      // per screenshot, inside a budget that already holds about six of them.
      expect(record.description!.length, lessThan(80));
    });
  });

  group('a record with nothing to say gets a clean empty', () {
    test('no labels and no OCR: description is null, not a filler sentence',
        () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: '',
      );

      final record = await only(provider);
      expect(record, isNotNull);
      expect(record!.description, isNull);
      expect(record.summary, 'No text found');
    });

    test('no labels but rich OCR: still null, because the text is already said',
        () async {
      final provider = await seeded();
      // Production only asks ML Kit for labels when the OCR is short, so this
      // shape — plenty of text, no labels — is the ordinary rich-screenshot
      // case. `summary` at weight 5 and `ocrText` at weight 1 already hold
      // every token in it, and a description here could only restate them.
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: 'Rent invoice\nAmount due 240\nAccount 8837',
      );

      final record = await only(provider);
      expect(record!.description, isNull);
      expect(record.summary, 'Rent invoice');
    });

    test('blank labels are not a label', () async {
      final provider = await seeded();
      await provider.addFromBulkIngest(
        path: '/probe/only.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: 'Something',
        objects: const ['', '   '],
      );

      final record = await only(provider);
      expect(record!.description, isNull);
    });
  });

  group('both write paths share one derivation', () {
    test('the same signals produce the same record through either path',
        () async {
      await Hive.openBox('screenshots');

      // A stand-in for the analyzer, so the single-image path can be driven with
      // exactly the signals the bulk path is given by argument. Only the native
      // OCR and labelling calls are replaced; the record construction, the
      // summary derivation and the description derivation are production code.
      const ocr = 'Rent invoice\nAmount due 240';
      const labels = <String>['Receipt', 'Food'];

      final bulkProvider = ScreenshotProvider(
        ocr: OCRService(extractOverride: (_) async => ''),
      );
      await bulkProvider.addFromBulkIngest(
        path: '/probe/bulk.png',
        capturedAt: DateTime(2026, 4, 1),
        ocrText: ocr,
        objects: labels,
      );

      final singleProvider = ScreenshotProvider(
        analyzer: _FixedAnalyzer(
          ScreenshotAnalysisResult(ocrText: ocr, objects: labels),
        ),
      );
      expect(
        await singleProvider.processScreenshot('/probe/single.png'),
        isTrue,
      );

      final bulk = bulkProvider.screenshots.single;
      final single = singleProvider.screenshots.single;

      expect(single.description, bulk.description,
          reason:
              'one derivation, so the same signals cannot describe the same '
              'picture two ways');
      expect(single.description, isNotNull);
      expect(bulk.summary, single.summary);
      expect(bulk.objects, single.objects);
    });

    test('a single-image record with no labels is also null, not a filler',
        () async {
      await Hive.openBox('screenshots');
      final provider = ScreenshotProvider(
        analyzer: _FixedAnalyzer(
          ScreenshotAnalysisResult(ocrText: 'Rent invoice\nAmount 240'),
        ),
      );
      expect(await provider.processScreenshot('/probe/single.png'), isTrue);
      expect(provider.screenshots.single.description, isNull);
    });
    test('the derivation is one static helper, called from both sites',
        () async {
      final source =
          await File('lib/providers/screenshot_provider.dart').readAsString();

      // Two call sites, one definition. A third would mean a private copy.
      expect(
        RegExp(r'_deriveDescription\(').allMatches(source).length,
        greaterThanOrEqualTo(3),
        reason: 'the definition plus at least two write sites',
      );
      expect(source.contains('static String? _deriveDescription('), isTrue);
      // The summary derivation was extracted at the same time, for the same
      // reason, so neither field can drift between the two write paths.
      expect(source.contains('static String _deriveSummary('), isTrue);
      expect(
        RegExp(r'_deriveSummary\(').allMatches(source).length,
        greaterThanOrEqualTo(3),
      );
    });
  });
}

/// The framing words a description carries in every sentence. Not OCR content,
/// and not index-reachable either: a one-character term is rejected by the
/// minimum-query gate and prefix matching only ever widens a query term, so
/// `a` in the index cannot be reached by anything a user can type.
///
/// They are excluded from the "does not repeat the summary" comparison below
/// because a description is a sentence and a sentence has an article. What must
/// never happen is a *content* word from the OCR appearing twice.
Set<String> _contentWords(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((String w) => w.isNotEmpty && !_framingWords.contains(w))
    .toSet();

const Set<String> _framingWords = <String>{
  'looks',
  'like',
  'a',
  'an',
  'and',
  'of',
};

/// Words the OCR body holds that the description also holds. Framing excluded on
/// both sides. This intersection is what "the description duplicates the OCR"
/// means, and it has to be empty for every production-written record.
Set<String> _ocrContentWords(Screenshot record) => record.summary!
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((String w) => w.isNotEmpty && !_framingWords.contains(w))
    .toSet()
    .intersection(_contentWords(record.description!));

/// An analyzer that returns one fixed result. Stands in for the native ML Kit
/// calls only, so the write path under test is production code.
class _FixedAnalyzer implements ScreenshotAnalyzer {
  _FixedAnalyzer(this.result);

  final ScreenshotAnalysisResult result;

  @override
  Future<ScreenshotAnalysisResult> analyze(String imagePath) async => result;
}
