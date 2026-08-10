import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screensort_lam/services/lam_service.dart';

void main() {
  test('chat sends a single request to the selected Gemini provider', () async {
    final urls = <Uri>[];

    final mock = MockClient((request) async {
      urls.add(request.url);
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'hi there'},
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
      context: 'ctx',
      apiKey: 'test',
      provider: 'Google Gemini',
    );

    expect(reply, 'hi there');
    expect(urls.length, 1);
    expect(urls.single.host, 'generativelanguage.googleapis.com');
  });
}
