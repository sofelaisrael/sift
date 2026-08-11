import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/image_labeler.dart';
import 'package:screensort_lam/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory importDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('import_images_test_');
    importDir = await Directory('${tempDir.path}/imports').create();
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> makeImage(String name) async {
    final f = File('${tempDir.path}/$name');
    await f.writeAsBytes(List.generate(64, (i) => i));
    return f.path.replaceAll('\\', '/');
  }

  test('importImages copies, OCRs, labels, and dedupes re-imports', () async {
    await Hive.openBox('screenshots');
    final a = await makeImage('a.png');
    final b = await makeImage('b.png');

    final ocr = OCRService(extractOverride: (_) async => 'Imported text here');
    final labeler =
        ImageLabeler(labelOverride: (_) async => ['photo', 'landscape']);
    final provider = ScreenshotProvider(ocr: ocr, labeler: labeler);

    final added1 = await provider.importImages([a, b], importDir: importDir);
    expect(added1, 2);
    expect(provider.screenshots.length, 2);
    expect(
      provider.screenshots.every((s) => s.filePath.startsWith(importDir.path)),
      isTrue,
    );
    expect(provider.screenshots.first.objects, contains('photo'));
    expect(provider.search('landscape'), isNotEmpty);

    // Re-importing the same files adds nothing (dedupe by name suffix + size).
    final added2 = await provider.importImages([a, b], importDir: importDir);
    expect(added2, 0);
    expect(provider.screenshots.length, 2);
  });

  test('disallowed names and extensions are skipped', () async {
    await Hive.openBox('screenshots');
    // Windows-style backslash path carrying a ".." name, plus a disallowed
    // extension and a non-whitelisted gif.
    final evil = File('${tempDir.path}\\..%2Fevil.png');
    await evil.writeAsBytes(const [1, 2, 3]);
    final exe = await makeImage('virus.exe');
    final gif = await makeImage('anim.gif');
    final ok = await makeImage('good.png');

    final ocr = OCRService(extractOverride: (_) async => 'ok text');
    final provider = ScreenshotProvider(ocr: ocr);

    final added = await provider.importImages(
      [evil.path, exe, gif, ok],
      importDir: importDir,
    );

    expect(added, 1);
    expect(provider.screenshots.length, 1);
    expect(provider.screenshots.single.fileName, endsWith('good.png'));
  });
}
