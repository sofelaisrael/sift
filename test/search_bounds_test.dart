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
    await provider.loadScreenshots();
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
    // 'bag' is a *prefix* of the indexed 'bagel'. This assertion used to encode
    // the opposite spec — the plan said "exact token match, no prefix" while
    // this line demanded a prefix hit, so the test and the spec contradicted
    // each other. Prefix matching was adopted on purpose (an as-you-type box
    // with a debounce is mid-word most of the time), so the line is now the
    // spec. Mid-word still does not match; see the substring-bound test below.
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

  test('prefix matching reaches a completion, not a mid-word substring',
      () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/bagels.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'Bagel shop order total 12 dollars',
    );
    final id = provider.screenshots.single.id;

    // The adopted behaviour: a query term matches indexed terms that start
    // with it. The search box is as-you-type with a debounce, so 'bag' is what
    // a user has typed most of the time and it must find 'bagel'.
    expect(provider.search('bag').map((s) => s.id), [id]);
    expect(provider.search('bagel').map((s) => s.id), [id]);
    // Any word in the record, not just the one that happens to be first.
    expect(provider.search('ord').map((s) => s.id), [id]);
    expect(provider.search('doll').map((s) => s.id), [id]);

    // The bound that keeps this from being substring search: a fragment in the
    // middle of an indexed word starts nothing, so it finds nothing.
    expect(provider.search('age'), isEmpty);
    expect(provider.search('gel'), isEmpty);
    expect(provider.search('agel'), isEmpty);
  });

  test('the splitter separates underscores and keeps CJK runs intact',
      () async {
    final provider = await buildProvider();
    await provider.addFromBulkIngest(
      path: '/g/Screenshot_20260927_143012.png',
      capturedAt: DateTime(2026, 1, 1),
      ocrText: '订单2026 total',
    );
    final id = provider.screenshots.single.id;

    // `\w` includes '_', so with the underscore left inside the word class the
    // whole file name was a single token. The numeric halves are the proof:
    // they are not a prefix of that token, so only a real split finds them.
    expect(provider.search('screenshot').map((s) => s.id), [id]);
    expect(provider.search('20260927').map((s) => s.id), [id]);
    expect(provider.search('143012').map((s) => s.id), [id]);

    // The CJK range is untouched. CJK has no spaces, so `\u4e00-\u9fff` is the
    // only reason '订单2026' survives as one token; drop that range and the run
    // is deleted rather than split, taking the word with it.
    expect(provider.search('订单').map((s) => s.id), [id]);
    // Still one token, so a fragment from inside the run is not a prefix.
    expect(provider.search('单2'), isEmpty);
  });
}
