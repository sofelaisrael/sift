import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/file_enumerator.dart';
import 'package:screensort_lam/services/image_labeler.dart';
import 'package:screensort_lam/services/ingest_service.dart';
import 'package:screensort_lam/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory shotDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('label_search_test_');
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

  Future<String> makeShot(String name, {String text = ''}) async {
    final f = File('${shotDir.path}/$name.png');
    await f.writeAsString(text);
    return f.path.replaceAll('\\', '/');
  }

  test('ingest labels a text-less screenshot via objects and search finds it',
      () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final path = await makeShot('puppy', text: '');
    expect(path, isNotEmpty);
    final ocr = OCRService(extractOverride: (_) async => '');
    final labeler = ImageLabeler(labelOverride: (_) async => ['dog', 'puppy']);
    final provider = ScreenshotProvider(ocr: ocr, labeler: labeler);
    final svc = IngestService(
      provider: provider,
      ocr: ocr,
      labeler: labeler,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [],
    );
    await svc.start();

    expect(provider.screenshots.length, 1);
    expect(provider.screenshots.first.objects, contains('dog'));
    // The text-less screenshot is now findable by its visual label.
    expect(provider.search('puppy'), isNotEmpty);
  });

  test('addFromBulkIngest stores labels in objects and they are searchable',
      () async {
    await Hive.openBox('screenshots');
    final path = await makeShot('menu', text: 'Pasta 12 euro');
    final provider = ScreenshotProvider(
      ocr: OCRService(extractOverride: (_) async => ''),
    );
    await provider.addFromBulkIngest(
      path: path,
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'Pasta 12 euro',
      objects: const ['menu', 'food'],
    );
    final s = provider.screenshots.single;
    expect(s.objects, contains('food'));
    expect(provider.search('food'), isNotEmpty);
    expect(provider.search('menu'), isNotEmpty);
  });

  test('rich OCR text skips visual labeling (no objects)', () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');

    final path = await makeShot('texty', text: '');
    expect(path, isNotEmpty);
    final ocr = OCRService(extractOverride: (_) async => 'a' * 300);
    final labeler = ImageLabeler(labelOverride: (_) async => ['dog']);
    final provider = ScreenshotProvider(ocr: ocr, labeler: labeler);
    final svc = IngestService(
      provider: provider,
      ocr: ocr,
      labeler: labeler,
      enumerator: FileEnumerator(folders: [shotDir.path]),
      retryDelays: const [],
    );
    await svc.start();
    expect(provider.screenshots.single.objects, isEmpty);
  });
}
