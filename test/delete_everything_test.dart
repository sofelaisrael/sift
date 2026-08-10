import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('delete_everything_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
  });

  test('deleteEverything wipes boxes and reseeds the watcher_seen guard', () async {
    final screenshotsBox = await Hive.openBox('screenshots');
    final shot = Screenshot(
      id: 's1',
      fileName: 'shot.png',
      filePath: '/gallery/shot.png',
      timestamp: DateTime(2026, 1, 1),
    );
    await screenshotsBox.put('s1', shot.toJson());

    final actionsBox = await Hive.openBox('actions');
    await actionsBox.put('a1', {'dummy': true});

    final chatBox = await Hive.openBox('chat');
    await chatBox.put('c1', {'dummy': true});

    final provider = ScreenshotProvider();
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);

    await provider.deleteEverything();

    expect(screenshotsBox.length, 0);
    expect(actionsBox.length, 0);
    expect(chatBox.length, 0);
    expect(provider.screenshots, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watcher_seen'), contains('/gallery/shot.png'));
  });
}
