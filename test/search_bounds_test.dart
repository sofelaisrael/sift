import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_bounds_');
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
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');
    final ocr = OCRService(extractOverride: (_) async => '');
    final provider = ScreenshotProvider(ocr: ocr);
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  test('min-query gate: one ASCII char is too short, one CJK char is enough',
      () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/a.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'Bagel shop order total 12 dollars',
    );
    await provider.addFromBulkIngest(
      path: '/g/b.png',
      capturedAt: DateTime(2026, 1, 2),
      ocrText: '咖啡店的菜单 拿铁 美式',
    );

    expect(provider.search('b'), isEmpty);
    expect(provider.search('zz'), isEmpty);
    expect(provider.search('bag').length, 1);
    expect(provider.search('咖').length, 1);
    expect(provider.search('拿铁').length, 1);
    expect(provider.search(''), isEmpty);
  });

  test('search scores across text and file name', () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/receipt_0312.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'Lunch at noodle bar',
    );
    await provider.addFromBulkIngest(
      path: '/g/passport.png',
      capturedAt: DateTime(2026, 1, 2),
      ocrText: 'Scanned identity document',
    );

    expect(provider.search('noodle').length, 1);
    // File name is in the haystack even when OCR text is not.
    expect(provider.search('receipt').length, 1);
    expect(provider.search('passport').length, 1);
  });

  test('multi-term queries are capped and matched', () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/a.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'alpha beta gamma delta',
    );
    await provider.addFromBulkIngest(
      path: '/g/b.png',
      capturedAt: DateTime(2026, 1, 2),
      ocrText: 'alpha only',
    );

    final hits = provider.search('alpha beta gamma delta epsilon zeta eta');
    expect(hits.length, 2);
    // Most terms matched wins the ranking despite the term cap.
    expect(hits.first.filePath, '/g/a.png');
  });

  test('tag filter narrows results to tagged hits', () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/a.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'travel visa document',
    );
    await provider.addFromBulkIngest(
      path: '/g/b.png',
      capturedAt: DateTime(2026, 1, 2),
      ocrText: 'travel itinerary',
    );

    final tagged = provider.screenshots.first.id;
    await provider.addTag(tagged, 'work');

    expect(provider.search('travel').length, 2);
    expect(provider.byTag('work').length, 1);
    expect(provider.byTag('nope'), isEmpty);
  });
}
