import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/action_service.dart';
import 'package:screensort_lam/services/file_enumerator.dart';
import 'package:screensort_lam/services/ingest_service.dart';
import 'package:screensort_lam/services/ocr_service.dart';
import 'package:screensort_lam/services/screenshot_watcher.dart';

class _FakeActionService extends ActionService {
  @override
  Future<void> notify(String title, String body) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory shotDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'localOnly': true,
      'privacy_consent': true,
    });
    tempDir = await Directory.systemTemp.createTemp('watcher_ingest_');
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

  Future<String> makeShot(String name, DateTime mtime,
      {String text = 'some screenshot text'}) async {
    final f = File('${shotDir.path}/$name.png');
    await f.writeAsString(text);
    await f.setLastModified(mtime);
    return f.path;
  }

  test(
      'watcher stands down while ingest runs, then picks up the post-pass delta',
      () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final ocr = OCRService(
      extractOverride: (p) async => 'OCR of $p',
    );
    final provider = ScreenshotProvider(ocr: ocr);

    // Index two files through the ingest pass.
    await makeShot('a', DateTime(2026, 1, 1));
    await makeShot('b', DateTime(2026, 1, 2));
    final ingest = IngestService(
      provider: provider,
      ocr: ocr,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [],
    );
    await ingest.start();
    expect(provider.screenshots.length, 2);

    var ingesting = false;
    final watcher = ScreenshotWatcher(
      provider: provider,
      actionService: _FakeActionService(),
      isIngesting: () => ingesting,
      enumerator: FileEnumerator(folders: [shotDir.path]),
    )..ensureNotificationPermission = () async {};

    await watcher.start();
    try {
      // A new file appears while the pass claims to be active: ignored.
      await makeShot('c', DateTime(2026, 1, 3));
      ingesting = true;
      await watcher.scanNow();
      expect(provider.screenshots.length, 2);

      // Pass done: one tick yields exactly one new record.
      ingesting = false;
      await watcher.scanNow();
      expect(provider.screenshots.length, 3);
      expect(provider.screenshots.first.filePath, endsWith('c.png'));

      // Already-known files are never re-processed.
      await watcher.scanNow();
      expect(provider.screenshots.length, 3);
    } finally {
      watcher.stop();
    }
  });
}
