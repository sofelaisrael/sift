import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/web_lookup.dart';

void main() {
  group('WebLookupService.lookup', () {
    test('returns URLs extracted from the text without any network call', () async {
      final service = WebLookupService();

      final results = await service.lookup(
        extractedText: 'see https://a.com/x and https://b.com/y plus c.com',
        summary: 'x',
        recognitions: const [],
        youTubeApiKey: null,
      );

      expect(results, hasLength(2));
      expect(results[0].url, 'https://a.com/x');
      expect(results[1].url, 'https://b.com/y');
      expect(results[0].title, 'https://a.com/x');
      expect(results[1].title, 'https://b.com/y');
    });

    test('returns an empty list without any network call when nothing is found', () async {
      final service = WebLookupService();

      final results = await service.lookup(
        extractedText: '',
        summary: '',
        recognitions: const [],
        youTubeApiKey: null,
      );

      expect(results, isEmpty);
    });
  });
}
