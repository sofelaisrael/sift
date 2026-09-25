import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/file_enumerator.dart';
import 'package:screensort_lam/services/image_labeler.dart';
import 'package:screensort_lam/services/ingest_service.dart';
import 'package:screensort_lam/services/ocr_service.dart';
import 'package:screensort_lam/services/screenshot_analyzer.dart';

class _FakeAnalyzer implements ScreenshotAnalyzer {
  _FakeAnalyzer(this.resultFor);

  final ScreenshotAnalysisResult Function(String imagePath) resultFor;
  final List<String> paths = [];
  int active = 0;
  int maxActive = 0;

  @override
  Future<ScreenshotAnalysisResult> analyze(String imagePath) async {
    paths.add(imagePath);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return resultFor(imagePath);
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory shotDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'localOnly': false,
      'privacy_consent': false,
    });
    tempDir = await Directory.systemTemp.createTemp('screenshot_analyzer_test_');
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

  test('awaited load exposes persisted local-only mode', () async {
    SharedPreferences.setMockInitialValues({'localOnly': true});
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider();

    expect(provider.localOnly, isTrue);
    await provider.loadScreenshots();

    expect(provider.localOnly, isTrue);
  });

  test('awaited load applies an explicit localOnly false', () async {
    SharedPreferences.setMockInitialValues({'localOnly': false});
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider();

    await provider.loadScreenshots();

    expect(provider.localOnly, isFalse);
  });

  test('a missing localOnly preference fails closed', () async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider();

    await provider.loadScreenshots();

    expect(provider.localOnly, isTrue);
  });

  test('preference-load failure fails closed to local-only', () async {
    SharedPreferences.setMockInitialValues({});
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider(
      localOnlyPreferenceLoader: () async =>
          throw StateError('preference store unavailable'),
    );

    await provider.loadScreenshots();

    expect(provider.localOnly, isTrue);
  });

  test('setLocalOnly persists each value and notifies once', () async {
    SharedPreferences.setMockInitialValues({'localOnly': true});
    final provider = ScreenshotProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setLocalOnly(false);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('localOnly'), isFalse);
    expect(provider.localOnly, isFalse);
    expect(notifications, 1);

    await provider.setLocalOnly(true);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('localOnly'), isTrue);
    expect(provider.localOnly, isTrue);
    expect(notifications, 2);
  });

  test('failed local-only persistence keeps state and stays silent', () async {
    SharedPreferences.setMockInitialValues({'localOnly': true});
    final provider = ScreenshotProvider(
      localOnlyPreferenceWriter: (_) async => false,
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    await expectLater(
      provider.setLocalOnly(false),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Could not save local-only preference.'),
        ),
      ),
    );
    expect(provider.localOnly, isTrue);
    expect(notifications, 0);
  });

  test('a successful toggle wins over an older settings read', () async {
    final loader = Completer<bool?>();
    final provider = ScreenshotProvider(
      localOnlyPreferenceLoader: () => loader.future,
      localOnlyPreferenceWriter: (_) async => true,
    );
    await Hive.openBox('screenshots');

    final load = provider.loadScreenshots();
    await provider.setLocalOnly(false);
    expect(provider.localOnly, isFalse);

    loader.complete(true);
    await load;

    expect(provider.localOnly, isFalse);
  });

  test(
    'home screenshot entry does not invoke the cloud consent gate',
    () async {
      final source = await File('lib/screens/home_screen.dart').readAsString();

      expect(source, isNot(contains('showPrivacyConsentIfNeeded')));
      expect(source, isNot(contains('privacy_gate.dart')));
    },
  );

  test(
    'runtime privacy copy describes the cloud chat boundary',
    () async {
      const paths = [
        'lib/screens/settings_screen.dart',
        'lib/screens/onboarding_screen.dart',
        'lib/screens/chat_screen.dart',
        'lib/services/chat_engine.dart',
        'lib/widgets/privacy_gate.dart',
      ];
      final sources = <String, String>{};
      for (final path in paths) {
        sources[path] = await File(path).readAsString();
      }

      for (final source in sources.values) {
        expect(source, isNot(contains('AI analysis sends images')));
        expect(
          source,
          isNot(contains('Everything lives on this device. Nothing leaves unless')),
        );
        expect(
          source,
          isNot(
            contains('Screenshots go to your chosen AI provider for analysis'),
          ),
        );
        expect(
          source,
          isNot(
            contains(
              'Privacy consent is required before Sift sends anything to an AI provider',
            ),
          ),
        );
        expect(source, contains('screenshot-derived text and context'));
        expect(source, contains('source lookup'));
        // No claim that Sift has no other setup-time network behavior.
        expect(source, isNot(contains('nothing is uploaded')));
        expect(source, isNot(contains('does not upload images for analysis')));
        expect(source, isNot(contains('Nothing leaves')));
        // Truthful ML Kit disclosure: Google Play services may download the
        // image-labeling model on first use, while the images and the
        // recognized text never leave the device.
        expect(source, contains('images and OCR text stay on this device'));
        expect(source, contains('image-labeling model on first use'));
      }
      expect(
        sources['lib/screens/settings_screen.dart'],
        contains('Local-only mode'),
      );
      expect(
        sources['lib/screens/onboarding_screen.dart'],
        contains('Local-only mode'),
      );
      expect(
        sources['lib/screens/chat_screen.dart'],
        contains('Local-only mode'),
      );
      expect(
        sources['lib/services/chat_engine.dart'],
        contains('Local-only mode'),
      );

      final about = await File('lib/widgets/about_dialog.dart').readAsString();
      expect(about, contains('images and OCR text stay on this device'));
      expect(about, contains('image-labeling model on first use'));

      final readme = await File('README.md').readAsString();
      expect(readme, contains('On-device OCR + visual labels'));
      expect(readme, isNot(contains('Gemini (LAM)')));
      expect(
        readme,
        isNot(contains('AI analysis uses your own Gemini API key')),
      );
      expect(readme, contains('image-labeling model on first use'));
    },
  );

  test('Settings and privacy defaults fail closed and await persistence',
      () async {
    final settings =
        await File('lib/screens/settings_screen.dart').readAsString();
    final privacy =
        await File('lib/widgets/privacy_gate.dart').readAsString();

    expect(settings, contains('bool _localOnly = true;'));
    expect(settings, contains("prefs.getBool('localOnly') ?? true"));
    expect(settings, contains('await provider.setLocalOnly(value);'));
    expect(
      settings.indexOf('await provider.setLocalOnly(value);'),
      lessThan(settings.indexOf('setState(() => _localOnly = value);')),
    );
    expect(settings, isNot(contains("setBool('localOnly', _localOnly)")));
    expect(privacy, contains("prefs.getBool('localOnly') ?? true"));
  });

  test('product copy describes local analysis and conditional actions', () async {
    final about = await File('lib/widgets/about_dialog.dart').readAsString();
    final settings = await File('lib/screens/settings_screen.dart').readAsString();
    final actionHistory =
        await File('lib/screens/actions_history_screen.dart').readAsString();
    final readme = await File('README.md').readAsString();

    expect(
      about,
      contains('On-device OCR, labels, indexing, and grounded chat'),
    );
    expect(about, contains('Only for records with a suggested action'));
    expect(about, isNot(contains('confidence')));
    expect(about, isNot(contains('Calendar, reminders, shopping lists')));
    expect(settings, contains('Actions you have run'));
    expect(actionHistory, contains('Actions you run will appear here.'));

    expect(
      readme,
      contains('Actions are available only when a record includes a suggested action'),
    );
    expect(readme, contains('on-device OCR and visual labels'));
    expect(readme, isNot(contains('Confidence threshold')));
    expect(readme, isNot(contains('**Extract** key information')));
  });

  test('ChatScreen sanitizes historical thumbnails at render time', () async {
    final source = await File('lib/screens/chat_screen.dart').readAsString();

    expect(source, contains('context.watch<ScreenshotProvider>().localOnly'));
    expect(source, contains('relatedLinksForDisplay(localOnly: localOnly)'));
    expect(
      source,
      isNot(contains('RelatedLinksStrip(links: message.relatedLinks)')),
    );
  });

  test('production code has no hosted image analysis API', () async {
    final entities = await Directory('lib').list(recursive: true).toList();
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      expect(
        await entity.readAsString(),
        isNot(contains('analyzeImage(')),
        reason: entity.path,
      );
    }
  });

  test('OCR reports a missing file before native recognition', () async {
    final missingPath = '${tempDir.path}/missing.png';

    await expectLater(
      OCRService().extractText(missingPath),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.path,
          'path',
          missingPath,
        ),
      ),
    );
  });

  test('OCR sanitizes a native error when the file still exists', () async {
    final existingPath = '${tempDir.path}/existing.png';
    await File(existingPath).writeAsString('not a real image');
    final ocr = OCRService(
      extractOverride: (_) async => throw PlatformException(
        code: 'OCR_NATIVE_ERROR',
        message: 'native detail',
      ),
    );

    try {
      await ocr.extractText(existingPath);
      fail('expected OCR to fail');
    } on FileSystemException {
      fail('an existing file must not be classified as missing');
    } catch (error) {
      expect(error.toString(), contains('OCR failed'));
      expect(error.toString(), isNot(contains('OCR_NATIVE_ERROR')));
    }
  });

  test(
    'ML Kit analyzer skips labels for rich OCR and includes them for text-poor OCR',
    () async {
      var labelCalls = 0;
      final ocr = OCRService(
        extractOverride: (path) async =>
            path.contains('rich') ? 'x' * 201 : 'short',
      );
      final labeler = ImageLabeler(
        labelOverride: (_) async {
          labelCalls++;
          return ['dog'];
        },
      );
      final analyzer = MLKitScreenshotAnalyzer(ocr: ocr, labeler: labeler);

      final rich = await analyzer.analyze('/rich.png');
      final textPoor = await analyzer.analyze('/poor.png');

      expect(rich.objects, isEmpty);
      expect(textPoor.objects, ['dog']);
      expect(labelCalls, 1);
    },
  );

  test('label failures stay non-fatal and OCR failures propagate', () async {
    final failingLabels = MLKitScreenshotAnalyzer(
      ocr: OCRService(extractOverride: (_) async => 'short'),
      labeler: ImageLabeler(
        labelOverride: (_) async => throw StateError('label boom'),
      ),
    );
    final noLabels = await failingLabels.analyze('/image.png');
    expect(noLabels.objects, isEmpty);

    final failingOcr = MLKitScreenshotAnalyzer(
      ocr: OCRService(
        extractOverride: (_) async => throw StateError('ocr boom'),
      ),
    );
    await expectLater(
      failingOcr.analyze('/image.png'),
      throwsA(isA<Exception>()),
    );
  });

  test('analysis result exposes an immutable visual-label list', () {
    final result = ScreenshotAnalysisResult(
      ocrText: 'text',
      labels: ['receipt'],
    );

    expect(result.objects, ['receipt']);
    expect(result.labels, same(result.objects));
    expect(() => result.objects.add('other'), throwsUnsupportedError);
  });

  test('a failed screenshots write returns false without a phantom record',
      () async {
    await Hive.openBox('screenshots');
    await Hive.box('screenshots').close();

    final analyzer = _FakeAnalyzer(
      (_) => ScreenshotAnalysisResult(ocrText: 'Should not be stored'),
    );
    final provider = ScreenshotProvider(analyzer: analyzer);

    final persisted = await provider.processScreenshot('/gallery/write-failure.png');

    expect(persisted, isFalse);
    expect(provider.screenshots, isEmpty);
    expect(provider.search('stored'), isEmpty);
  });

  test(
    'manual processing works without cloud consent and indexes the result',
    () async {
      await Hive.openBox('screenshots');
      final analyzer = _FakeAnalyzer(
        (_) => ScreenshotAnalysisResult(
          ocrText: 'Quarterly report',
          objects: ['report'],
        ),
      );
      final provider = ScreenshotProvider(analyzer: analyzer);

      final persisted = await provider.processScreenshot('/gallery/manual.png');

      expect(persisted, isTrue);
      expect(analyzer.paths, ['/gallery/manual.png']);
      expect(provider.screenshots, hasLength(1));
      final screenshot = provider.screenshots.single;
      expect(screenshot.ocrText, 'Quarterly report');
      expect(screenshot.objects, ['report']);
      expect(provider.search('report'), [screenshot]);
    },
  );

  test(
    'manual analysis and bulk ingest share and serialize the injected analyzer',
    () async {
      await Hive.openBox('screenshots');
      await Hive.openBox('ingest');

      final manualPath = '${tempDir.path}/manual.png';
      final bulkFile = File('${shotDir.path}/bulk.png');
      await bulkFile.writeAsString('bulk');
      final bulkPath = bulkFile.path.replaceAll('\\', '/');
      final analyzer = _FakeAnalyzer(
        (path) => path == manualPath
            ? ScreenshotAnalysisResult(
                ocrText: 'Manual text',
                objects: ['manual'],
              )
            : ScreenshotAnalysisResult(
                ocrText: 'Bulk text',
                objects: ['bulk'],
              ),
      );
      final provider = ScreenshotProvider(analyzer: analyzer);
      final ingest = IngestService(
        provider: provider,
        enumerator: FileEnumerator(folders: [shotDir.path]),
        retryDelays: const [],
      );

      expect(provider.analyzer, same(analyzer));

      final manualFuture = provider.processScreenshot(manualPath);
      final ingestFuture = ingest.start();
      await manualFuture;
      await ingestFuture;

      expect(analyzer.paths, containsAll(<String>[manualPath, bulkPath]));
      expect(analyzer.maxActive, 1);
      expect(provider.screenshots, hasLength(2));
      expect(
        provider.screenshots
            .firstWhere((screenshot) => screenshot.filePath == manualPath)
            .objects,
        ['manual'],
      );
      expect(
        provider.screenshots
            .firstWhere((screenshot) => screenshot.filePath == bulkPath)
            .objects,
        ['bulk'],
      );
    },
  );
}
