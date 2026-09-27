import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

/// The local analyzer stores the literal `'No text found'` as `summary` when an
/// image has no readable text. It is a display string, so it must not reach
/// the inverted index: `summary` is the heaviest field at weight 5, and the
/// literal would donate `no`, `text` and `found` at 5 points each to every
/// text-free screenshot in the library.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_placeholder_');
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

  Future<String> addShot(
    ScreenshotProvider provider, {
    required String name,
    String ocrText = '',
    List<String>? objects,
  }) async {
    final id = await provider.addFromBulkIngest(
      path: '/g/$name.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: ocrText,
      objects: objects,
    );
    return id!;
  }

  test('a text-free screenshot indexes nothing from its summary placeholder',
      () async {
    final provider = await buildProvider();
    final id =
        await addShot(provider, name: 'skyline', objects: const ['skyscraper']);

    // The placeholder is still stored, so the card keeps saying it.
    expect(provider.screenshots.single.summary, 'No text found');

    // ...but none of its words are searchable, alone or together.
    expect(provider.search('text'), isEmpty);
    expect(provider.search('no'), isEmpty);
    expect(provider.search('found'), isEmpty);
    expect(provider.search('no text found'), isEmpty);

    // The record is not silenced: real content on it still answers.
    expect(provider.search('skyscraper').map((s) => s.id), [id]);
  });

  test('the placeholder no longer outranks a genuine match for "text"',
      () async {
    final provider = await buildProvider();
    // Genuine hit: "text" is in the OCR body but not in the summary line, so
    // it scores once at the OCR weight.
    final real = await addShot(
      provider,
      name: 'menu',
      ocrText: 'Lunch at noodle bar\nask about the text under the total',
    );
    // Text-free: the placeholder used to score 5 against the same query.
    final textless = await addShot(
      provider,
      name: 'skyline',
      objects: const ['skyscraper'],
    );

    final hits = provider.search('text');
    expect(
      hits.map((s) => s.id),
      [real],
      reason: 'the text-free record scores 0 and must drop out entirely; while '
          'the placeholder is indexed it scores 5 and outranks the real match '
          'at 1',
    );
    expect(hits, isNot(contains(textless)));
  });

  test('a real summary that merely contains the placeholder words is indexed',
      () async {
    final provider = await buildProvider();
    // The guard is an exact match, not a substring match: genuine content that
    // happens to use the words must stay searchable.
    final id = await addShot(
      provider,
      name: 'receipt',
      ocrText: 'No text found on the receipt, total 12 dollars',
    );

    expect(provider.search('receipt').map((s) => s.id), [id]);
    expect(provider.search('dollars').map((s) => s.id), [id]);
  });

  test('the constant lamType is not indexed', () async {
    final provider = await buildProvider();
    final id = await addShot(provider, name: 'skyline', objects: const ['sky']);

    // 'document' is written on every record, so it cannot discriminate.
    expect(provider.search('document'), isEmpty);
    // The stored field is untouched: the type filter still groups by it.
    expect(provider.screenshots.single.lamType, 'document');
    expect(provider.byType['document']!.single.id, id);
  });
}
