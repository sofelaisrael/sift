import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screensort_lam/services/lam_service.dart';

void main() {
  test('chat sends text and context without an image payload', () async {
    late String requestBody;
    late Uri requestUrl;
    late String apiKeyHeader;
    var requestCount = 0;

    final mock = MockClient((request) async {
      requestCount++;
      requestBody = request.body;
      requestUrl = request.url;
      apiKeyHeader = request.headers['x-goog-api-key'] ?? '';
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'text reply'},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final lam = LAMService(client: mock);
    final reply = await lam.chat(
      'hello',
      context: 'OCR and labels from a local screenshot',
      apiKey: 'test',
      provider: 'Google Gemini',
    );

    expect(reply, 'text reply');
    expect(requestCount, 1);
    expect(requestUrl.host, 'generativelanguage.googleapis.com');
    expect(apiKeyHeader, 'test');
    final encodedBody = jsonEncode(jsonDecode(requestBody));
    expect(encodedBody, isNot(contains('inlineData')));
    expect(encodedBody, isNot(contains('image_url')));
    expect(encodedBody, isNot(contains('data:image')));
    expect(encodedBody, isNot(contains('base64')));
  });

  test('chat rejects an unknown provider without sending its key', () async {
    var requests = 0;
    final mock = MockClient((request) async {
      requests++;
      return http.Response('{}', 500);
    });

    final reply = await LAMService(client: mock).chat(
      'hello',
      context: 'ctx',
      apiKey: 'secret-do-not-leak',
      provider: 'UnknownProvider',
    );

    expect(reply, contains('supported provider'));
    expect(reply, isNot(contains('secret-do-not-leak')));
    expect(requests, 0);
  });
}
