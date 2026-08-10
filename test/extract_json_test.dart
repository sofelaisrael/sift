import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/lam_service.dart';

void main() {
  group('extractJsonObject', () {
    test('extracts the JSON object from a ```json fenced block', () {
      const content = '''
Here is the analysis result:
```json
{"type": "flight", "confidence": 0.9, "summary": "A flight booking"}
```
That is all I know.
''';

      final result = extractJsonObject(content);

      expect(result, isNotNull);
      expect(result!['type'], 'flight');
      expect(result['confidence'], 0.9);
      expect(result['summary'], 'A flight booking');
    });

    test('extracts the JSON object surrounded by prose', () {
      const content =
          'Sure thing! {"type": "recipe", "confidence": 0.8, "summary": "Pasta carbonara"} hope that helps.';

      final result = extractJsonObject(content);

      expect(result, isNotNull);
      expect(result!['type'], 'recipe');
      expect(result['summary'], 'Pasta carbonara');
    });

    test('extracts JSON with nested braces and maps', () {
      const content =
          '{"type": "deadline", "extracted_data": {"date": "2026-01-12", '
          '"nested": {"a": [1, {"b": 2}]}}, "summary": "Nested"}';

      final result = extractJsonObject(content);

      expect(result, isNotNull);
      expect(result!['type'], 'deadline');
      final data = result['extracted_data'] as Map<String, dynamic>;
      expect(data['date'], '2026-01-12');
      final nested = data['nested'] as Map<String, dynamic>;
      expect(nested['a'], [1, {'b': 2}]);
    });

    test('returns null for garbage with no opening brace', () {
      const content = 'this is just plain text with no json at all';

      expect(extractJsonObject(content), isNull);
    });

    test('picks the valid JSON object when a leading block is invalid', () {
      const content =
          'part one {"oops": broken} part two '
          '{"type": "product", "confidence": 0.7, "summary": "Running shoes"}';

      final result = extractJsonObject(content);

      expect(result, isNotNull);
      expect(result!['type'], 'product');
      expect(result['summary'], 'Running shoes');
    });
  });
}
