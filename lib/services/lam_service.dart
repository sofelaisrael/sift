import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class LAMService {
  static const _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';

  Future<LAMResponse> processScreenshot(String ocrText) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer ${AppConfig.openRouterApiKey}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://screensort.app',
          'X-Title': AppConfig.appName,
        },
        body: jsonEncode({
          'model': AppConfig.openRouterModel,
          'messages': [
            {
              'role': 'system',
              'content': '''
You are a Large Action Model (LAM). Analyze screenshot text and return ONLY valid JSON.

Rules:
1. Identify what the screenshot shows (flight, recipe, deadline, product, meeting, document, other)
2. Extract key information
3. Determine what action to take
4. Return JSON only, no explanation

Response format:
{
  "type": "flight|recipe|deadline|product|meeting|document|other",
  "confidence": 0.0-1.0,
  "summary": "Brief description",
  "extracted_data": {},
  "suggested_action": {
    "type": "add_calendar|create_reminder|create_shopping_list|create_task|none",
    "data": {}
  }
}

Examples:

Flight →
{"type":"flight","confidence":0.95,"summary":"Flight AA123 to NYC on Dec 15 at 3pm","extracted_data":{"airline":"American Airlines","flight_number":"AA123","destination":"NYC","date":"2024-12-15","time":"15:00"},"suggested_action":{"type":"add_calendar","data":{"title":"Flight to NYC - AA123","date":"2024-12-15","time":"15:00","reminder_days_before":1}}}

Recipe →
{"type":"recipe","confidence":0.9,"summary":"Chicken Tikka Masala - 45 min, serves 4","extracted_data":{"name":"Chicken Tikka Masala","cook_time":"45 min","servings":4,"ingredients":["chicken","yogurt","tomatoes","spices"]},"suggested_action":{"type":"create_shopping_list","data":{"list_name":"Chicken Tikka Masala Ingredients","items":["chicken","yogurt","tomatoes","spices"]}}}

Deadline →
{"type":"deadline","confidence":0.85,"summary":"Project proposal due Dec 20","extracted_data":{"event":"Project proposal","date":"2024-12-20"},"suggested_action":{"type":"create_reminder","data":{"title":"Project proposal due","date":"2024-12-20","remind_days_before":[3,1,0]}}}
''',
            },
            {'role': 'user', 'content': 'Screenshot text:\n$ocrText'},
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.1,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('OpenRouter error ${response.statusCode}: ${response.body}');
        return _fallbackResponse();
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return _fallbackResponse();

      final json = jsonDecode(content) as Map<String, dynamic>;
      return LAMResponse.fromJson(json);
    } catch (e) {
      debugPrint('LAM error: $e');
      return _fallbackResponse();
    }
  }

  LAMResponse _fallbackResponse() {
    return LAMResponse(
      type: 'other',
      confidence: 0.0,
      summary: 'Could not analyze screenshot',
      extractedData: {},
      suggestedAction: LAMAction(type: 'none', data: {}),
    );
  }
}

class LAMResponse {
  final String type;
  final double confidence;
  final String summary;
  final Map<String, dynamic> extractedData;
  final LAMAction suggestedAction;

  LAMResponse({
    required this.type,
    required this.confidence,
    required this.summary,
    required this.extractedData,
    required this.suggestedAction,
  });

  factory LAMResponse.fromJson(Map<String, dynamic> json) {
    return LAMResponse(
      type: json['type'] ?? 'other',
      confidence: (json['confidence'] ?? 0).toDouble(),
      summary: json['summary'] ?? '',
      extractedData: json['extracted_data'] ?? {},
      suggestedAction: LAMAction.fromJson(json['suggested_action'] ?? {}),
    );
  }

  String get typeEmoji {
    switch (type) {
      case 'flight': return '✈️';
      case 'recipe': return '🍳';
      case 'deadline': return '⏰';
      case 'product': return '🛒';
      case 'meeting': return '📅';
      case 'document': return '📄';
      default: return '📌';
    }
  }

  bool get isHighConfidence => confidence >= 0.7;
}

class LAMAction {
  final String type;
  final Map<String, dynamic> data;

  LAMAction({
    required this.type,
    required this.data,
  });

  factory LAMAction.fromJson(Map<String, dynamic> json) {
    return LAMAction(
      type: json['type'] ?? 'none',
      data: json['data'] ?? {},
    );
  }

  String get displayName {
    switch (type) {
      case 'add_calendar': return 'Add to Calendar';
      case 'create_reminder': return 'Create Reminder';
      case 'create_shopping_list': return 'Create Shopping List';
      case 'create_task': return 'Create Task';
      case 'none': return 'No Action';
      default: return 'Unknown';
    }
  }
}
