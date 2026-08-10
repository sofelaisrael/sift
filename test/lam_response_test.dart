import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/services/lam_service.dart';

void main() {
  group('LAMResponse.fromJson', () {
    test('parses every field from a full valid map', () {
      final json = <String, dynamic>{
        'type': 'flight',
        'confidence': 0.95,
        'summary': 'Flight booked',
        'description': 'A flight booking for the trip',
        'objects': ['airplane', 'seat map'],
        'recognitions': ['Google Flights'],
        'extracted_text': 'LAX → JFK',
        'extracted_data': {'price': 540, 'date': '2026-01-12'},
        'suggested_action': {'type': 'add_calendar', 'data': {'date': '2026-01-12'}},
      };

      final response = LAMResponse.fromJson(json);

      expect(response.type, 'flight');
      expect(response.confidence, 0.95);
      expect(response.summary, 'Flight booked');
      expect(response.description, 'A flight booking for the trip');
      expect(response.objects, ['airplane', 'seat map']);
      expect(response.recognitions, ['Google Flights']);
      expect(response.extractedText, 'LAX → JFK');
      expect(response.extractedData, {'price': 540, 'date': '2026-01-12'});
      expect(response.suggestedAction.type, 'add_calendar');
      expect(response.suggestedAction.data, {'date': '2026-01-12'});
    });

    test('clamps confidence to the [0, 1] range', () {
      final high = LAMResponse.fromJson({'confidence': 1.7, 'type': 'other'});
      final low = LAMResponse.fromJson({'confidence': -0.2, 'type': 'other'});

      expect(high.confidence, 1.0);
      expect(low.confidence, 0.0);
    });

    test('defaults missing optional fields', () {
      final response = LAMResponse.fromJson({'type': 'document'});

      expect(response.type, 'document');
      expect(response.objects, isEmpty);
      expect(response.recognitions, isEmpty);
      expect(response.extractedText, '');
      expect(response.extractedData, isEmpty);
      expect(response.suggestedAction.type, 'none');
      expect(response.suggestedAction.data, isEmpty);
    });

    test('isHighConfidence is true at 0.7', () {
      final threshold = LAMResponse.fromJson({'confidence': 0.7, 'type': 'other'});
      final below = LAMResponse.fromJson({'confidence': 0.6, 'type': 'other'});

      expect(threshold.isHighConfidence, isTrue);
      expect(below.isHighConfidence, isFalse);
    });
  });
}
