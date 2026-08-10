import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';

Screenshot _shot({
  required String id,
  String? summary,
  String? description,
  List<String> tags = const [],
  Map<String, dynamic>? extractedData,
}) {
  return Screenshot(
    id: id,
    fileName: '$id.png',
    filePath: '/gallery/$id.png',
    timestamp: DateTime(2026, 1, 1),
    summary: summary,
    description: description,
    tags: tags,
    extractedData: extractedData,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('search_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
  });

  test('search matches summary text and returns the hit first', () async {
    final box = await Hive.openBox('screenshots');
    await box.put(
      's1',
      _shot(
        id: 's1',
        summary: 'Lisbon itinerary',
        description: 'Tram 28 through Lisbon',
        tags: ['travel'],
      ).toJson(),
    );
    await box.put(
      's2',
      _shot(id: 's2', summary: 'Flight BA123', tags: ['flight']).toJson(),
    );
    await box.put(
      's3',
      _shot(id: 's3', extractedData: {'deadline': '2026-01-12'}).toJson(),
    );

    final provider = ScreenshotProvider();
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);

    final lisbon = provider.search('lisbon');
    expect(lisbon, isNotEmpty);
    expect(lisbon.first.id, 's1');
    expect(lisbon.length, 1);

    final flight = provider.search('flight');
    expect(flight, isNotEmpty);
    expect(flight.first.id, 's2');
    expect(flight.length, 1);
  });

  test('search matches via extractedData haystack', () async {
    final box = await Hive.openBox('screenshots');
    await box.put(
      's3',
      _shot(id: 's3', extractedData: {'deadline': '2026-01-12'}).toJson(),
    );
    await box.put(
      's1',
      _shot(id: 's1', summary: 'Lisbon itinerary').toJson(),
    );

    final provider = ScreenshotProvider();
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);

    final deadline = provider.search('deadline');
    expect(deadline, isNotEmpty);
    expect(deadline.first.id, 's3');
    expect(deadline.length, 1);
  });

  test('search returns empty for unmatched and blank queries', () async {
    final box = await Hive.openBox('screenshots');
    await box.put(
      's1',
      _shot(id: 's1', summary: 'Lisbon itinerary', tags: ['travel']).toJson(),
    );

    final provider = ScreenshotProvider();
    provider.loadScreenshots();
    await Future<void>.delayed(Duration.zero);

    expect(provider.search('zzz'), isEmpty);
    expect(provider.search(''), isEmpty);
  });
}
