import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screensort_lam/services/lam_service.dart';

const validLamResponseJson =
    '{"type": "document", "confidence": 0.9, "summary": "Test summary", '
    '"description": "Test description", "objects": ["laptop"], '
    '"recognitions": ["MacBook"], "extracted_text": "Hello world", '
    '"extracted_data": {"price": 540}, '
    '"suggested_action": {"type": "none", "data": {}}}';

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('no_fan_out_');
    final file = File('${tempDir.path}/fake.png');
    await file.writeAsBytes(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    imagePath = file.path;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('analyzeImage makes exactly one request to Gemini with the key header', () async {
    final urls = <Uri>[];
    final headers = <Map<String, String>>[];

    final mock = MockClient((request) async {
      urls.add(request.url);
      headers.add(Map<String, String>.from(request.headers));
      if (request.url.host == 'generativelanguage.googleapis.com') {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': validLamResponseJson},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 500);
    });

    final lam = LAMService(client: mock);
    final result = await lam.analyzeImage(imagePath, apiKey: 'test', provider: 'Google Gemini');

    expect(result.type, 'document');
    expect(urls.length, 1);
    expect(urls.single.host, 'generativelanguage.googleapis.com');
    expect(urls.single.toString().contains('key='), isFalse);
    expect(headers.single['x-goog-api-key'], 'test');
  });

  test('analyzeImage makes exactly one request to NVIDIA', () async {
    final urls = <Uri>[];

    final mock = MockClient((request) async {
      urls.add(request.url);
      if (request.url.host == 'integrate.api.nvidia.com') {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': validLamResponseJson},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 500);
    });

    final lam = LAMService(client: mock);
    final result = await lam.analyzeImage(imagePath, apiKey: 'test', provider: 'NVIDIA');

    expect(result.type, 'document');
    expect(urls.length, 1);
    expect(urls.single.host, 'integrate.api.nvidia.com');
  });

  test('no request ever reaches Groq or any other host', () async {
    final urls = <Uri>[];

    final mock = MockClient((request) async {
      urls.add(request.url);
      if (request.url.host == 'generativelanguage.googleapis.com') {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': validLamResponseJson},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host == 'integrate.api.nvidia.com') {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': validLamResponseJson},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 500);
    });

    final lam = LAMService(client: mock);
    await lam.analyzeImage(imagePath, apiKey: 'test', provider: 'Google Gemini');
    await lam.analyzeImage(imagePath, apiKey: 'test', provider: 'NVIDIA');

    final hosts = urls.map((u) => u.host).toSet();
    expect(urls.length, 2);
    expect(hosts, {
      'generativelanguage.googleapis.com',
      'integrate.api.nvidia.com',
    });
    expect(hosts, isNot(contains('api.groq.com')));
  });
}
