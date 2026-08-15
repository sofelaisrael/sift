import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screensort_lam/services/web_lookup.dart';

/// A DuckDuckGo result anchor (absolute href with the uddg redirect).
String _ddgLink(String url, String title) {
  final encoded = Uri.encodeComponent(url);
  return '<a rel="nofollow" class="result__a" '
      'href="https://duckduckgo.com/l/?uddg=$encoded&rut=abc">'
      '$title</a>';
}

String _ddgHtml(List<String> links) =>
    '<html><body><div class="results">${links.join()}</div></body></html>';

void main() {
  group('WebLookupService.lookup', () {
    test('returns URLs extracted from the text without any network call',
        () async {
      final service = WebLookupService();

      final results = await service.lookup(
        extractedText: 'see https://a.com/x and https://b.com/y plus c.com',
        summary: 'x',
        recognitions: const [],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(results, hasLength(2));
      expect(results[0].url, 'https://a.com/x');
      expect(results[1].url, 'https://b.com/y');
      expect(results[0].title, 'https://a.com/x');
      expect(results[1].title, 'https://b.com/y');
    });

    test('returns an empty list without any network call when nothing is found',
        () async {
      final service = WebLookupService();

      final results = await service.lookup(
        extractedText: '',
        summary: '',
        recognitions: const [],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(results, isEmpty);
    });

    test('query is built from the OCR text title line (keyless video path)',
        () async {
      String? query;
      final client = MockClient((request) async {
        if (request.url.host == 'html.duckduckgo.com') {
          query = Uri.splitQueryString(request.body)['q'];
          return http.Response(
            _ddgHtml([_ddgLink('https://www.youtube.com/watch?v=abc123', 'Grilled Cheese Masterclass')]),
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText:
            'Grilled Cheese Masterclass\n123,456 views · 2 weeks ago',
        summary: 'YouTube video about cooking',
        recognitions: const ['YouTube'],
        objects: const [],
        youTubeApiKey: null,
      );

      // The title line leads the query; stopwords are dropped.
      expect(query, contains('site:youtube.com'));
      expect(query, contains('Grilled'));
      expect(query, contains('Cheese'));
      expect(query, contains('Masterclass'));
      expect(query, isNot(contains('about')));
      expect(results, isNotEmpty);
    });

    test('keyless video search keeps only watch/shorts YouTube URLs', () async {
      var ddgCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'html.duckduckgo.com') {
          ddgCalls++;
          return http.Response(
            _ddgHtml([
              _ddgLink('https://www.youtube.com/watch?v=abc123', 'Grilled Cheese Masterclass'),
              _ddgLink('https://www.youtube.com/channel/UCx', 'A Channel'),
              _ddgLink('https://www.youtube.com/results?search_query=x', 'Search page'),
              _ddgLink('https://www.youtube.com/shorts/xyz9', 'Short video'),
            ]),
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: 'Grilled Cheese Masterclass video',
        summary: 'YouTube',
        recognitions: const ['YouTube'],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(ddgCalls, 1);
      expect(results.map((r) => r.url).toList(), [
        'https://www.youtube.com/watch?v=abc123',
        'https://www.youtube.com/shorts/xyz9',
      ]);
      // Real DDG titles keep the link as-is; the thumbnail is derived from
      // the video id with no extra call.
      expect(results.first.title, 'Grilled Cheese Masterclass');
      expect(
        results.first.thumbnail,
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
      expect(
        results.last.thumbnail,
        'https://i.ytimg.com/vi/xyz9/hqdefault.jpg',
      );
    });

    test('extracted YouTube URLs get a real title + thumbnail via oEmbed',
        () async {
      var ddgCalled = false;
      final client = MockClient((request) async {
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/oembed') {
          return http.Response(
            jsonEncode({
              'title': 'How to Make Grilled Cheese',
              'thumbnail_url':
                  'https://i.ytimg.com/vi/abc123/maxresdefault.jpg',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'html.duckduckgo.com') {
          ddgCalled = true;
          return http.Response('{}', 500);
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: 'watch this https://youtu.be/abc123',
        summary: '',
        recognitions: const [],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(ddgCalled, isFalse);
      expect(results, hasLength(1));
      expect(results.first.title, 'How to Make Grilled Cheese');
      expect(
        results.first.thumbnail,
        'https://i.ytimg.com/vi/abc123/maxresdefault.jpg',
      );
    });

    test('YouTube Data API results carry thumbnails derived from the video id',
        () async {
      final client = MockClient((request) async {
        if (request.url.host == 'www.googleapis.com') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': {'videoId': 'xyz1'},
                  'snippet': {'title': 'Lisbon Travel Guide'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: 'flight booking',
        summary: 'Flight BA123 to Lisbon',
        recognitions: const ['Google Flights'],
        objects: const [],
        youTubeApiKey: 'test-key',
      );

      expect(results, hasLength(1));
      expect(results.first.title, 'Lisbon Travel Guide');
      expect(
        results.first.thumbnail,
        'https://i.ytimg.com/vi/xyz1/hqdefault.jpg',
      );
    });

    test('non-video content searches DuckDuckGo without the site: filter',
        () async {
      String? query;
      final client = MockClient((request) async {
        if (request.url.host == 'html.duckduckgo.com') {
          query = Uri.splitQueryString(request.body)['q'];
          return http.Response(
            _ddgHtml([_ddgLink('https://example.com/recipe', 'Recipe')]),
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: 'Chicken Tikka Masala recipe',
        summary: 'Recipe for dinner',
        recognitions: const ['Instagram'],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(query, isNot(contains('site:youtube.com')));
      expect(query, contains('Chicken'));
      expect(results.single.url, 'https://example.com/recipe');
    });

    test('an oEmbed failure keeps the bare link and never throws', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'www.youtube.com' &&
            request.url.path == '/oembed') {
          return http.Response('oops', 500);
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: 'https://www.youtube.com/watch?v=abc123',
        summary: '',
        recognitions: const [],
        objects: const [],
        youTubeApiKey: null,
      );

      expect(results, hasLength(1));
      expect(results.first.url, 'https://www.youtube.com/watch?v=abc123');
      expect(
        results.first.thumbnail,
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
    });

    test('a text-less screenshot searches with its on-device visual labels',
        () async {
      String? query;
      final client = MockClient((request) async {
        if (request.url.host == 'html.duckduckgo.com') {
          query = Uri.splitQueryString(request.body)['q'];
          return http.Response(
            _ddgHtml([_ddgLink('https://example.com/dog-food', 'Best Dog Food')]),
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('{}', 500);
      });
      final service = WebLookupService(client: client);

      final results = await service.lookup(
        extractedText: '',
        summary: '',
        recognitions: const [],
        objects: const ['dog', 'food', 'bowl'],
        youTubeApiKey: null,
      );

      // No text means no video signal: a plain DuckDuckGo search whose query
      // is built from the image labels.
      expect(query, isNot(contains('site:youtube.com')));
      expect(query, contains('dog'));
      expect(query, contains('food'));
      expect(query, contains('bowl'));
      expect(results.single.url, 'https://example.com/dog-food');
    });
  });
}
