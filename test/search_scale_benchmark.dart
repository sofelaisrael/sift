import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

/// Measures search latency at a library size a real install reaches.
///
/// This is a measurement, not a correctness test: it asserts a deliberately
/// loose ceiling so a genuine complexity regression fails, while ordinary
/// machine noise does not. The interesting number is the one it prints.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_scale_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('search stays fast on a realistically sized library', () async {
    await Hive.openBox('screenshots');
    await Hive.openBox('ingest');
    await Hive.openBox('hidden_paths');
    final provider =
        ScreenshotProvider(ocr: OCRService(extractOverride: (_) async => ''));
    await provider.loadScreenshots();

    const librarySize = 2000;
    final sw = Stopwatch()..start();
    for (var i = 0; i < librarySize; i++) {
      await provider.addFromBulkIngest(
        path: '/gallery/Screenshot_${20260000 + i}.png',
        capturedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ocrText:
            'Order $i confirmation total 42 dollars paid card ending 4417 '
            'merchant name downtown branch receipt items subtotal tax tip '
            'thank you very much customer copy',
        objects: ['receipt', 'food', 'table'],
      );
    }
    provider.flushBulkNotify();
    final buildMs = sw.elapsedMilliseconds;

    // A partially-typed word, which is what the as-you-type box holds most of
    // the time, plus a multi-word question that clears the six-term cap.
    const queries = [
      'down',
      'receipt',
      'order confirmation',
      'downtown branch receipt order',
      'thank',
      'merchant',
      'tot',
      'card',
      'items',
      'customer',
    ];

    // Warm-up so the first call is not charged for lazy setup.
    for (final q in queries) {
      provider.search(q);
    }

    final samples = <int>[];
    for (var round = 0; round < 5; round++) {
      for (final q in queries) {
        final t = Stopwatch()..start();
        provider.search(q);
        samples.add(t.elapsedMicroseconds);
      }
    }
    samples.sort();
    final p50 = samples[samples.length ~/ 2] / 1000;
    final p95 = samples[(samples.length * 0.95).floor()] / 1000;
    final maxMs = samples.last / 1000;

    debugPrint(
      'SEARCH_SCALE library=$librarySize build=${buildMs}ms '
      'p50=${p50.toStringAsFixed(2)}ms '
      'p95=${p95.toStringAsFixed(2)}ms '
      'max=${maxMs.toStringAsFixed(2)}ms',
    );

    // A ceiling, not a target. The as-you-type box debounces, so a single
    // query must stay in the low milliseconds; anything in the tens of
    // milliseconds means the hot path grew a linear scan.
    expect(
      p95,
      lessThan(50.0),
      reason: 'p95 search latency at $librarySize screenshots',
    );
  });
}