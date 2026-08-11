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
    tempDir = await Directory.systemTemp.createTemp('hide_test_');
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
    await Hive.openBox('actions');
    await Hive.openBox('chat');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');
    final ocr = OCRService(extractOverride: (_) async => '');
    final provider = ScreenshotProvider(ocr: ocr);
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  test('hide removes from every sink and survives re-ingest; wipe resets',
      () async {
    final provider = await buildProvider();

    const p1 = '/gallery/a.png';
    const p2 = '/gallery/b.png';
    await provider.addFromBulkIngest(
      path: p1,
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'Lisbon flight BA123',
    );
    await provider.addFromBulkIngest(
      path: p2,
      capturedAt: DateTime(2026, 1, 2),
      ocrText: 'Chess opening theory',
    );

    expect(provider.search('lisbon').length, 1);
    expect(provider.visibleScreenshots.length, 2);
    expect(provider.recentScreenshots.length, 2);
    expect(provider.byType['document']!.length, 2);

    // Tag the visible one, then hide the Lisbon shot.
    final visibleId = provider.screenshots
        .firstWhere((s) => s.filePath == p2)
        .id;
    await provider.addTag(visibleId, 'chess');
    expect(provider.byTag('chess').length, 1);

    await provider.hideScreenshot(p1);

    // Absent from every sink.
    expect(provider.search('lisbon'), isEmpty);
    expect(provider.visibleScreenshots.length, 1);
    expect(provider.recentScreenshots.length, 1);
    expect(provider.byType['document']!.length, 1);
    expect(provider.isHidden(p1), isTrue);

    // Watcher-seen + hidden box record it.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watcher_seen'), contains(p1));
    expect(Hive.box('hidden_paths').get(p1), isNotNull);

    // Re-ingest of the same path dedupes and does not resurrect it.
    final again = await provider.addFromBulkIngest(
      path: p1,
      capturedAt: DateTime(2026, 1, 3),
      ocrText: 'again',
    );
    expect(again, isNull);
    expect(provider.search('lisbon'), isEmpty);

    // Unhide restores visibility.
    await provider.unhideScreenshot(p1);
    expect(provider.search('lisbon').length, 1);

    // Full wipe clears ingest + hidden boxes and reseeds watcher_seen.
    await provider.hideScreenshot(p1);
    await provider.deleteEverything();
    expect(Hive.box('ingest').keys, isEmpty);
    expect(Hive.box('hidden_paths').keys, isEmpty);
    expect(provider.screenshots, isEmpty);
    expect(prefs.getStringList('watcher_seen') ?? const [], contains(p1));
  });
}
