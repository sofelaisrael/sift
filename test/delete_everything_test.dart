import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/chat_message.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/screens/chat_screen.dart';
import 'package:screensort_lam/services/ocr_service.dart';
import 'package:screensort_lam/services/screenshot_analyzer.dart';
import 'package:screensort_lam/theme/app_theme.dart';

class _BlockingAnalyzer implements ScreenshotAnalyzer {
  final entered = Completer<void>();
  final release = Completer<ScreenshotAnalysisResult>();

  @override
  Future<ScreenshotAnalysisResult> analyze(String imagePath) {
    if (!entered.isCompleted) entered.complete();
    return release.future;
  }
}

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
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
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
    await provider.loadScreenshots();

    await provider.deleteEverything(
      importDir: Directory('${tempDir.path}/sift_imports'),
    );

    expect(screenshotsBox.length, 0);
    expect(actionsBox.length, 0);
    expect(chatBox.length, 0);
    expect(provider.screenshots, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watcher_seen'), contains('/gallery/shot.png'));
    expect(prefs.getBool('localOnly'), isTrue);
    expect(provider.localOnly, isTrue);
  });

  test('deleteEverything removes private imports recursively and keeps originals',
      () async {
    await Hive.openBox('screenshots');
    final gallery = Directory('${tempDir.path}/gallery')..createSync();
    final original = File('${gallery.path}/original.png')
      ..writeAsBytesSync([1, 2, 3]);
    final documents = Directory('${tempDir.path}/documents')..createSync();
    final importDir = Directory('${documents.path}/sift_imports')..createSync();
    final nested = Directory('${importDir.path}/nested')..createSync();
    final imported = File('${nested.path}/copy.png')
      ..writeAsBytesSync([4, 5, 6]);

    final provider = ScreenshotProvider(
      ocr: OCRService(extractOverride: (_) async => 'imported text'),
      documentsDirectoryLoader: () async => documents,
    );
    await provider.importImages([original.path]);
    await provider.addFromBulkIngest(
      path: original.path,
      capturedAt: DateTime(2026, 1, 1),
      ocrText: 'gallery original',
    );
    expect(provider.screenshots, hasLength(2));
    expect(imported.existsSync(), isTrue);

    await provider.deleteEverything();

    expect(importDir.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
  });

  test('deleteEverything persists local-only mode instead of resetting it',
      () async {
    SharedPreferences.setMockInitialValues({'localOnly': false});
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider();
    await provider.loadScreenshots();

    await provider.deleteEverything(
      importDir: Directory('${tempDir.path}/sift_imports'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('localOnly'), isTrue);
    expect(provider.localOnly, isTrue);
  });

  test('deletion waits for in-flight analysis and blocks its commit', () async {
    await Hive.openBox('screenshots');
    final analyzer = _BlockingAnalyzer();
    final provider = ScreenshotProvider(analyzer: analyzer);
    final analysis = provider.processScreenshot('${tempDir.path}/gallery.png');
    await analyzer.entered.future;

    final deletion = provider.deleteEverything(
      importDir: Directory('${tempDir.path}/sift_imports'),
    );
    expect(provider.isDeleting, isTrue);
    expect(await provider.processScreenshot('${tempDir.path}/new.png'), isFalse);
    expect(
      await provider.addFromBulkIngest(
        path: '${tempDir.path}/new.png',
        capturedAt: DateTime(2026, 1, 1),
        ocrText: 'blocked',
      ),
      isNull,
    );

    analyzer.release.complete(
      ScreenshotAnalysisResult(ocrText: 'must not be stored'),
    );
    expect(await analysis, isFalse);
    await deletion;

    expect(provider.screenshots, isEmpty);
    expect(Hive.box('screenshots'), isEmpty);
    expect(provider.isDeleting, isFalse);
  });

  test('a failing documents-directory loader keeps data and errors', () async {
    final screenshotsBox = await Hive.openBox('screenshots');
    final shot = Screenshot(
      id: 's1',
      fileName: 'shot.png',
      filePath: '/gallery/shot.png',
      timestamp: DateTime(2026, 1, 1),
    );
    await screenshotsBox.put('s1', shot.toJson());
    final chatBox = await Hive.openBox('chat');
    await chatBox.put('c1', {'dummy': true});
    SharedPreferences.setMockInitialValues({'localOnly': false});

    final provider = ScreenshotProvider(
      documentsDirectoryLoader: () async =>
          throw StateError('documents directory unavailable'),
    );
    await provider.loadScreenshots();

    await expectLater(
      provider.deleteEverything(),
      throwsA(
        isA<DataDeletionException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('Could not delete everything'),
            contains('private import folder'),
            isNot(contains('documents directory unavailable')),
            isNot(contains(tempDir.path)),
          ),
        ),
      ),
    );

    // No box was cleared and no preference was wiped.
    expect(screenshotsBox.length, 1);
    expect(chatBox.length, 1);
    expect(provider.screenshots, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('localOnly'), isFalse);
    expect(provider.isDeleting, isFalse);
  });

  test('a failing import-directory delete keeps data and the files', () async {
    final screenshotsBox = await Hive.openBox('screenshots');
    await screenshotsBox.put('s1', {
      'id': 's1',
      'fileName': 'shot.png',
      'filePath': '/gallery/shot.png',
      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
    });
    final actionsBox = await Hive.openBox('actions');
    await actionsBox.put('a1', {'dummy': true});
    SharedPreferences.setMockInitialValues({
      'localOnly': false,
      'key_youtube': 'k',
    });

    final documents = Directory('${tempDir.path}/documents')..createSync();
    final importDir =
        Directory('${documents.path}/sift_imports')..createSync();
    final imported = File('${importDir.path}/copy.png')
      ..writeAsBytesSync([1, 2, 3]);

    final provider = ScreenshotProvider(
      documentsDirectoryLoader: () async => documents,
      importDirectoryCleaner: (_) async =>
          throw StateError('EBUSY /data/secret'),
    );
    await provider.loadScreenshots();

    await expectLater(
      provider.deleteEverything(),
      throwsA(
        isA<DataDeletionException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('Could not delete everything'),
            contains('private import folder'),
            isNot(contains('EBUSY')),
            isNot(contains(importDir.path)),
          ),
        ),
      ),
    );

    // The import folder is still there: the failure is not reported as a
    // completed cleanup, and nothing else was destroyed either.
    expect(importDir.existsSync(), isTrue);
    expect(imported.existsSync(), isTrue);
    expect(screenshotsBox.length, 1);
    expect(actionsBox.length, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_youtube'), 'k');
    expect(provider.isDeleting, isFalse);
  });

  test('a failed preferences clear is surfaced, not swallowed', () async {
    final documents = Directory('${tempDir.path}/documents')..createSync();
    final importDir =
        Directory('${documents.path}/sift_imports')..createSync();
    File('${importDir.path}/copy.png').writeAsBytesSync([1, 2, 3]);
    final screenshotsBox = await Hive.openBox('screenshots');
    await screenshotsBox.put('s1', {
      'id': 's1',
      'fileName': 'shot.png',
      'filePath': '/gallery/shot.png',
      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
    });
    SharedPreferences.setMockInitialValues({
      'localOnly': false,
      'key_youtube': 'k',
    });

    final provider = ScreenshotProvider(
      documentsDirectoryLoader: () async => documents,
      preferencesClearer: (_) async => false,
    );
    await provider.loadScreenshots();

    await expectLater(
      provider.deleteEverything(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('preference clear failed'),
            isNot(contains(tempDir.path)),
          ),
        ),
      ),
    );

    // The clear failed, so the saved key is still on disk: the wipe must not
    // report success. The import folder is already gone at that point, which is
    // why the Settings copy cannot promise that nothing was deleted.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_youtube'), 'k');
    expect(importDir.existsSync(), isFalse);
    expect(provider.isDeleting, isFalse);
  });

  test('a successful delete clears the boxes and the import folder', () async {
    final screenshotsBox = await Hive.openBox('screenshots');
    await screenshotsBox.put('s1', {
      'id': 's1',
      'fileName': 'shot.png',
      'filePath': '/gallery/shot.png',
      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
    });
    final documents = Directory('${tempDir.path}/documents')..createSync();
    final importDir =
        Directory('${documents.path}/sift_imports')..createSync();
    File('${importDir.path}/copy.png').writeAsBytesSync([1, 2, 3]);

    final provider = ScreenshotProvider(
      documentsDirectoryLoader: () async => documents,
    );
    await provider.loadScreenshots();

    await provider.deleteEverything();

    expect(importDir.existsSync(), isFalse);
    expect(screenshotsBox.length, 0);
  });

  testWidgets('mounted ChatScreen clears its transcript after deletion',
      (tester) async {
    await Hive.openBox('screenshots');
    await Hive.openBox('chat');
    final provider = ScreenshotProvider();
    await provider.loadScreenshots();
    await Hive.box('chat').put('history', [
      ChatMessage(
        id: 'message-1',
        role: 'user',
        content: 'remember this',
        timestamp: DateTime(2026, 1, 1),
      ).toJson(),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<ScreenshotProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('remember this'), findsOneWidget);

    await provider.deleteEverything(
      importDir: Directory('${tempDir.path}/sift_imports'),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('remember this'), findsNothing);
    expect(find.text('What would you like to remember?'), findsOneWidget);
  });

  test('Settings surfaces a deletion failure instead of claiming success',
      () async {
    const path = 'lib/screens/settings_screen.dart';
    final source = await File(path).readAsString();

    const call = 'await provider.deleteEverything();';
    const failure = 'Could not delete everything. Some data may already be';
    final callIndex = source.indexOf(call);
    expect(callIndex, greaterThan(-1));
    // The call is guarded: a catch clause follows it directly, and the failure
    // copy is shown before any success snackbar or UI reset.
    expect(source.substring(callIndex, callIndex + 40), contains('catch'));
    expect(source, contains(failure));
    // The wipe can fail after the import folder or some boxes are already gone,
    // so the copy must not promise an untouched library.
    expect(source, isNot(contains('Nothing was deleted')));
    expect(
      source.indexOf(failure),
      lessThan(source.indexOf("Text('Everything deleted')")),
    );
    expect(
      source.indexOf(failure),
      lessThan(source.indexOf('navigator.popUntil((route) => route.isFirst)')),
    );
  });

  test('provider exposes a deletion revision for retained chat state', () async {
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider();
    final before = provider.deletionRevision;

    await provider.deleteEverything(
      importDir: Directory('${tempDir.path}/sift_imports'),
    );

    expect(provider.deletionRevision, before + 1);
    final source = await File('lib/screens/chat_screen.dart').readAsString();
    expect(source, contains('deletionRevision'));
    expect(source, contains('_onProviderChanged'));
    expect(source, contains('_clearInMemoryTranscript'));
    final mainSource = await File('lib/main.dart').readAsString();
    expect(mainSource, contains('setIngestStopHook(ingestService.stop)'));
  });
}
