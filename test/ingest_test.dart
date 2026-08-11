import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/file_enumerator.dart';
import 'package:screensort_lam/services/ingest_service.dart';
import 'package:screensort_lam/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory shotDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ingest_test_');
    shotDir = await Directory('${tempDir.path}/shots').create();
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> makeShot(
    String name,
    DateTime mtime, {
    String text = 'Receipt total 42 dollars',
  }) async {
    final f = File('${shotDir.path}/$name.png');
    await f.writeAsString(text);
    await f.setLastModified(mtime);
    // Match the enumerator's normalized path form.
    return f.path.replaceAll('\\', '/');
  }

  IngestService buildService(Map<String, String> ocrResults) {
    final ocr = OCRService(extractOverride: (p) async => ocrResults[p] ?? '');
    final provider = ScreenshotProvider(ocr: ocr);
    return IngestService(
      provider: provider,
      ocr: ocr,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [],
    );
  }

  test('ingest is idempotent and uses real capture times', () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final older = await makeShot('old', DateTime(2025, 5, 1, 10));
    final newer = await makeShot('new', DateTime(2026, 1, 12, 9, 30));

    final svc = buildService({
      older: 'Old travel notes',
      newer: 'Flight BA123 to Lisbon',
    });
    await svc.start();

    final provider = svc.provider;
    expect(provider.screenshots.length, 2);
    // Newest first.
    expect(provider.screenshots.first.filePath, newer);
    expect(provider.screenshots.first.timestamp, DateTime(2026, 1, 12, 9, 30));
    expect(provider.screenshots.last.timestamp, DateTime(2025, 5, 1, 10));
    expect(provider.screenshots.first.ocrText, 'Flight BA123 to Lisbon');

    // Re-running the pass changes nothing.
    await svc.start();
    expect(provider.screenshots.length, 2);
  });

  test('crash recovery re-pends stuck processing entries without duplicates',
      () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final p1 = await makeShot('a', DateTime(2026, 1, 1, 8));
    final p2 = await makeShot('b', DateTime(2026, 1, 2, 9));

    // Simulate a pass that died mid-OCR: one entry stuck in processing.
    final box = Hive.box('ingest');
    await box.put(p1, {
      'status': 'processing',
      'attempts': 0,
      'lastError': null,
      'enqueuedAt': DateTime.now().toIso8601String(),
      'processedAt': null,
      'screenshotId': null,
    });

    final svc = buildService({p1: 'Alpha text', p2: 'Beta text'});
    await svc.start();

    expect(svc.provider.screenshots.length, 2);
    expect(svc.processedCount, 2);
    final entries = Hive.box('ingest').toMap().cast<String, Map<dynamic, dynamic>>();
    expect(entries[p1]!['status'], 'done');
    expect(entries[p2]!['status'], 'done');
  });

  test('OCR failure is retried then marked failed; missing file is skipped',
      () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final bad = await makeShot('bad', DateTime(2026, 1, 1));
    final ok = await makeShot('ok', DateTime(2026, 1, 2));

    var calls = 0;
    final ocr = OCRService(extractOverride: (p) async {
      if (p == bad) {
        calls++;
        throw StateError('ocr boom');
      }
      return 'Good text';
    });
    final provider = ScreenshotProvider(ocr: ocr);
    final svc = IngestService(
      provider: provider,
      ocr: ocr,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    await svc.start();

    final entries = Hive.box('ingest').toMap().cast<String, Map<dynamic, dynamic>>();
    expect(entries[bad]!['status'], 'failed');
    expect(entries[ok]!['status'], 'done');
    expect(calls, 3); // initial + 2 retries
    expect(provider.screenshots.length, 1);
  });

  test('a file deleted mid-pass is marked skipped', () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final doomed = await makeShot('doomed', DateTime(2026, 1, 1));
    final ocr = OCRService(extractOverride: (p) async {
      // Simulate the file disappearing between enumeration and OCR.
      await File(p).delete();
      return File(p).readAsString(); // throws FileSystemException
    });
    final provider = ScreenshotProvider(ocr: ocr);
    final svc = IngestService(
      provider: provider,
      ocr: ocr,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [],
    );
    await svc.start();

    final entries = Hive.box('ingest').toMap().cast<String, Map<dynamic, dynamic>>();
    expect(entries[doomed]!['status'], 'skipped');
    expect(provider.screenshots, isEmpty);
  });
}
