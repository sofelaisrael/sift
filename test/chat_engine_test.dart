import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/services/chat_engine.dart';
import 'package:screensort_lam/services/lam_service.dart';
import 'package:screensort_lam/services/web_lookup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'provider': 'Google Gemini',
      'key_Google Gemini': 'test-key',
      'key_youtube': 'test-youtube-key',
    });
  });

  Screenshot shot({
    String? ocrText,
    String? summary,
    List<String> recognitions = const [],
    List<String> objects = const [],
  }) =>
      Screenshot(
        id: 'shot1',
        fileName: 'flight.png',
        filePath: 'shots/flight.png',
        timestamp: DateTime(2026, 1, 1),
        ocrText: ocrText,
        summary: summary,
        recognitions: recognitions,
        objects: objects,
      );

  MockClient geminiMock() => MockClient((request) async {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Here is your answer.'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  test('local-only mode returns the local reply and never calls the AI',
      () async {
    var consentCalled = false;
    final mock = MockClient((request) async {
      fail('LAM must not be called in local-only mode');
    });

    final engine = ChatEngine(
      lam: LAMService(client: mock),
      consentCheck: () async {
        consentCalled = true;
        return true;
      },
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [
        shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking'),
      ],
      localOnly: true,
    );

    expect(reply.blocked, isFalse);
    expect(reply.relatedLinks, isEmpty);
    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
    expect(consentCalled, isFalse);
  });

  test('denied consent blocks the reply and skips the AI call', () async {
    final mock = MockClient((request) async {
      fail('LAM must not be called when consent is denied');
    });

    final engine = ChatEngine(
      lam: LAMService(client: mock),
      consentCheck: () async => false,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123 to Lisbon')],
      localOnly: false,
    );

    expect(reply.blocked, isTrue);
    expect(reply.content, contains('Privacy consent is required'));
    expect(reply.relatedLinks, isEmpty);
  });

  test('granted consent returns the LLM reply and the lookup links', () async {
    String? capturedExtractedText;
    String? capturedSummary;

    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        capturedExtractedText = extractedText;
        capturedSummary = summary;
        return const [
          WebResult(
            title: 'BA123 flight status',
            url: 'https://example.com/1',
          ),
          WebResult(title: 'Lisbon travel guide', url: 'https://example.com/2'),
        ];
      },
    );

    final reply = await engine.reply(
      text: 'What was that flight to Lisbon?',
      results: [shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking')],
      localOnly: false,
    );

    expect(reply.blocked, isFalse);
    expect(reply.content, 'Here is your answer.');
    expect(reply.relatedLinks, [
      {'title': 'BA123 flight status', 'url': 'https://example.com/1'},
      {'title': 'Lisbon travel guide', 'url': 'https://example.com/2'},
    ]);
    expect(capturedExtractedText, 'Flight BA123 to Lisbon');
    expect(capturedSummary, 'Flight booking');
  });

  test('an empty top screenshot skips the lookup entirely', () async {
    var lookupCalled = false;
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        lookupCalled = true;
        return const [WebResult(title: 'unexpected', url: 'https://example.com')];
      },
    );

    final reply = await engine.reply(
      text: 'anything',
      results: [shot(ocrText: null, summary: null, recognitions: const [])],
      localOnly: false,
    );

    expect(reply.relatedLinks, isEmpty);
    expect(lookupCalled, isFalse);
  });

  test("'No text found' summary still triggers a lookup with empty summary",
      () async {
    String? capturedSummary;
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        capturedSummary = summary;
        return const [WebResult(title: 'guide', url: 'https://example.com/1')];
      },
    );

    final reply = await engine.reply(
      text: 'q',
      results: [shot(ocrText: null, summary: 'No text found')],
      localOnly: false,
    );

    expect(capturedSummary, '');
    expect(reply.relatedLinks, [
      {'title': 'guide', 'url': 'https://example.com/1'},
    ]);
  });

  test('buildLocalReply keeps the exact local-only copy', () {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
    );

    expect(
      engine.buildLocalReply(const []),
      'Nothing found in your saved screenshots. '
          'Local-only mode searches on-device text only — no AI.',
    );
    expect(
      engine.buildLocalReply([
        shot(
          ocrText: 'Flight BA123 to Lisbon',
          summary: 'Flight booking',
          recognitions: ['Google Flights'],
        ),
      ]),
      'Found 1 matching screenshots:\n• Flight booking (Google Flights)',
    );
  });

  test('buildContextText renders every field and the no-match copy', () {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
    );

    expect(
      engine.buildContextText(const []),
      'No saved screenshots matched the query. Answer honestly that nothing matches.',
    );

    final context = engine.buildContextText([
      shot(
        ocrText: 'Flight BA123 to Lisbon',
        summary: 'Flight booking',
        recognitions: ['Google Flights'],
      ),
    ]);
    expect(context, contains('[0]'));
    expect(context, contains('  Summary: Flight booking'));
    expect(context, contains('  Text: Flight BA123 to Lisbon'));
    expect(context, contains('  Recognitions: Google Flights'));
    expect(context, contains('  Taken: 2026-01-01T00:00:00.000'));
  });

  test('a throwing lookup stub yields empty links but the reply still arrives',
      () async {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        throw Exception('lookup boom');
      },
    );

    final reply = await engine.reply(
      text: 'What was that flight?',
      results: [shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking')],
      localOnly: false,
    );

    expect(reply.content, 'Here is your answer.');
    expect(reply.relatedLinks, isEmpty);
  });

  test('lookup results are capped at 3 links', () async {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        return List.generate(
          5,
          (i) => WebResult(title: 'result $i', url: 'https://example.com/$i'),
        );
      },
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking')],
      localOnly: false,
    );

    expect(reply.relatedLinks, hasLength(3));
  });

  test('the provider key comes from prefs (not the AppConfig fallback)',
      () async {
    String? capturedKey;
    final mock = MockClient((request) async {
      capturedKey = request.headers['x-goog-api-key'];
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Keyed answer.'},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final engine = ChatEngine(
      lam: LAMService(client: mock),
      consentCheck: () async => true,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking')],
      localOnly: false,
    );

    expect(capturedKey, 'test-key');
    expect(reply.content, 'Keyed answer.');
  });

  test('no prefs key falls back to the AppConfig key and skips the provider',
      () async {
    SharedPreferences.setMockInitialValues({
      'provider': 'Google Gemini',
      'key_youtube': 'test-youtube-key',
    });
    var called = false;
    final mock = MockClient((request) async {
      called = true;
      fail('LAM must not be called without a key for a requiresKey provider');
    });

    final engine = ChatEngine(
      lam: LAMService(client: mock),
      consentCheck: () async => true,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123 to Lisbon')],
      localOnly: false,
    );

    expect(called, isFalse);
    expect(reply.content, contains('Sorry, I could not reach any AI provider'));
  });

  test('links come from the second result when the top has no content',
      () async {
    var lookupCalled = false;
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        lookupCalled = true;
        return const <WebResult>[];
      },
    );

    final reply = await engine.reply(
      text: 'the video',
      results: [
        shot(ocrText: null, summary: null),
        shot(ocrText: 'watch https://youtu.be/abc123 later'),
      ],
      localOnly: false,
    );

    // Phase B still runs (1 embedded link < 3) and mines the 2nd result.
    expect(lookupCalled, isTrue);
    expect(reply.relatedLinks, hasLength(1));
    expect(reply.relatedLinks.single['url'], 'https://youtu.be/abc123');
  });

  test('local-only mode returns embedded links with zero network', () async {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async =>
          fail('consent must not be checked in local-only mode'),
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async => fail('lookup must not run in local-only mode'),
    );

    final reply = await engine.reply(
      text: 'video',
      results: [shot(ocrText: 'https://youtu.be/abc123')],
      localOnly: true,
    );

    expect(reply.blocked, isFalse);
    expect(reply.relatedLinks, hasLength(1));
    expect(reply.relatedLinks.single['url'], 'https://youtu.be/abc123');
    // No thumbnails in local-only mode — nothing is fetched from the network.
    expect(reply.relatedLinks.single.containsKey('thumb'), isFalse);
  });

  test('embedded links are de-duplicated and capped at three', () async {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        return const <WebResult>[];
      },
    );

    final reply = await engine.reply(
      text: 'links',
      results: [
        shot(ocrText: 'https://a.com/1 https://a.com/1 https://a.com/2'),
        shot(ocrText: 'https://b.com/3 https://c.com/4'),
      ],
      localOnly: false,
    );

    expect(reply.relatedLinks, hasLength(3));
    expect(reply.relatedLinks.map((l) => l['url']).toSet(), {
      'https://a.com/1',
      'https://a.com/2',
      'https://b.com/3',
    });
  });

  test('exactly one lookup call per reply', () async {
    var lookupCalls = 0;
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        lookupCalls++;
        return const <WebResult>[];
      },
    );

    final reply = await engine.reply(
      text: 'recipes',
      results: [
        shot(ocrText: 'Chicken Tikka recipe', summary: 'dinner'),
        shot(ocrText: 'Grilled cheese recipe', summary: 'snack'),
      ],
      localOnly: false,
    );

    expect(lookupCalls, 1);
    expect(reply.relatedLinks, isEmpty);
  });

  test('enriched lookup results override bare embedded links with the same URL',
      () async {
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        return const [
          WebResult(
            title: 'The Real Video Title',
            url: 'https://youtu.be/abc123',
            thumbnail: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
          ),
        ];
      },
    );

    final reply = await engine.reply(
      text: 'video',
      results: [shot(ocrText: 'watch https://youtu.be/abc123')],
      localOnly: false,
    );

    expect(reply.relatedLinks, hasLength(1));
    expect(reply.relatedLinks.single['title'], 'The Real Video Title');
    expect(
      reply.relatedLinks.single['thumb'],
      'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
    );
  });

  test('a text-less screenshot with visual labels still triggers one lookup',
      () async {
    var lookupCalled = false;
    List<String>? capturedObjects;
    final engine = ChatEngine(
      lam: LAMService(client: geminiMock()),
      consentCheck: () async => true,
      lookup: ({
        required String extractedText,
        required String summary,
        required List<String> recognitions,
        required List<String> objects,
        required String? youTubeApiKey,
      }) async {
        lookupCalled = true;
        capturedObjects = objects;
        return const [
          WebResult(title: 'dog food guide', url: 'https://example.com/1'),
        ];
      },
    );

    final reply = await engine.reply(
      text: 'dog',
      results: [
        shot(
          ocrText: null,
          summary: null,
          recognitions: const [],
          objects: const ['dog', 'food', 'bowl'],
        ),
      ],
      localOnly: false,
    );

    // No text, no summary, no recognitions — but the labels are enough to
    // run the search, and they become the lookup input.
    expect(lookupCalled, isTrue);
    expect(capturedObjects, ['dog', 'food', 'bowl']);
    expect(reply.relatedLinks, [
      {'title': 'dog food guide', 'url': 'https://example.com/1'},
    ]);
  });
}
