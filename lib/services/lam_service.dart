import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class LAMService {
  static const _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';

  /// Analyze screenshot by sending the image directly to a multimodal model.
  /// Falls back to OCR text if image analysis fails.
  Future<LAMResponse> analyzeImage(String imagePath) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

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
              'content': _buildSystemPrompt(),
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'Analyze this screenshot. Extract all visible text and context. Return ONLY valid JSON, no explanation, no markdown.',
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/png;base64,$base64Image'},
                },
              ],
            },
          ],
          'temperature': 0.1,
          'max_tokens': 1024,
        }),
      );

      debugPrint('OpenRouter status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('OpenRouter error: ${response.body}');
        return _fallbackResponse('API error ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return _fallbackResponse('No content in response');

      debugPrint('Raw AI response: $content');
      return _parseResponse(content);
    } catch (e) {
      debugPrint('LAM analyzeImage error: $e');
      return _fallbackResponse(e.toString());
    }
  }

  /// Fallback: analyze via OCR text if multimodal fails
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
              'content': _buildSystemPrompt(),
            },
            {'role': 'user', 'content': 'Screenshot text:\n$ocrText'},
          ],
          'temperature': 0.1,
          'max_tokens': 1024,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('OpenRouter error: ${response.statusCode} ${response.body}');
        return _fallbackResponse('API error ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return _fallbackResponse('No content in response');

      debugPrint('Raw AI response: $content');
      return _parseResponse(content);
    } catch (e) {
      debugPrint('LAM processScreenshot error: $e');
      return _fallbackResponse(e.toString());
    }
  }

  LAMResponse _parseResponse(String content) {
    // Strip markdown code fences if present
    var cleaned = content.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
    }

    try {
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return LAMResponse.fromJson(json);
    } catch (e) {
      debugPrint('JSON parse failed: $e\nContent: $cleaned');
      return _fallbackResponse('JSON parse error');
    }
  }

  String _buildSystemPrompt() {
    return '''You are a Large Action Model (LAM) that analyzes screenshots and extracts actionable information.

RULES:
1. Look at the image carefully — read all text, buttons, dates, times, prices, lists
2. Identify what the screenshot shows
3. Extract ALL key information you can see
4. Determine the best action to suggest
5. Return ONLY valid JSON — no explanation, no markdown, no code fences

CONFIDENCE SCORING:
- 0.9-1.0: You clearly see flight details, calendar events, recipes with ingredients, product listings with prices
- 0.7-0.89: You see recognizable content (emails, messages, deadlines, meetings) but some details are unclear
- 0.5-0.69: You see text but aren't sure of the context
- 0.3-0.49: Very little readable text, mostly guessing
- 0.0-0.29: Cannot meaningfully analyze the content

RESPONSE FORMAT (JSON only):
{
  "type": "flight|recipe|deadline|product|meeting|shopping|document|other",
  "confidence": 0.0-1.0,
  "summary": "Brief description of what you see",
  "extracted_data": {
    "all relevant fields you can extract"
  },
  "suggested_action": {
    "type": "add_calendar|create_reminder|create_shopping_list|create_task|none",
    "data": {
      "fields needed for the action"
    }
  }
}

EXAMPLES:

Flight booking confirmation →
{"type":"flight","confidence":0.95,"summary":"Flight AA123 JFK to LAX on Mar 15 departing 3:45 PM","extracted_data":{"airline":"American Airlines","flight_number":"AA123","origin":"JFK","destination":"LAX","date":"2026-03-15","time":"15:45","passenger":"John Doe"},"suggested_action":{"type":"add_calendar","data":{"title":"Flight AA123 JFK→LAX","date":"2026-03-15","time":"15:45","reminder_days_before":1}}}

Recipe screenshot →
{"type":"recipe","confidence":0.9,"summary":"Chicken Stir Fry - 25 min, serves 4","extracted_data":{"name":"Chicken Stir Fry","cook_time":"25 min","servings":4,"ingredients":["chicken breast","soy sauce","garlic","ginger","bell peppers","rice"]},"suggested_action":{"type":"create_shopping_list","data":{"list_name":"Stir Fry Ingredients","items":["chicken breast","soy sauce","garlic","ginger","bell peppers"]}}}

Deadline or exam →
{"type":"deadline","confidence":0.85,"summary":"Final exam - Calculus II on Dec 20 at 9 AM","extracted_data":{"event":"Final exam - Calculus II","date":"2026-12-20","time":"09:00","location":"Room 301"},"suggested_action":{"type":"create_reminder","data":{"title":"Calculus II Final Exam","date":"2026-12-20","time":"09:00","remind_days_before":[7,3,1,0]}}}

Amazon product →
{"type":"product","confidence":0.88,"summary":"Sony WH-1000XM5 headphones - \$278","extracted_data":{"product":"Sony WH-1000XM5","price":"\$278","store":"Amazon","rating":"4.7/5"},"suggested_action":{"type":"none","data":{}}}

Grocery list →
{"type":"shopping","confidence":0.92,"summary":"Grocery list: milk, eggs, bread, butter, apples","extracted_data":{"items":["milk","eggs","bread","butter","apples"]},"suggested_action":{"type":"create_shopping_list","data":{"list_name":"Groceries","items":["milk","eggs","bread","butter","apples"]}}}

Meeting invite →
{"type":"meeting","confidence":0.87,"summary":"Team standup - Tomorrow 10:00 AM via Zoom","extracted_data":{"event":"Team standup","date":"2026-01-15","time":"10:00","location":"Zoom"},"suggested_action":{"type":"add_calendar","data":{"title":"Team standup","date":"2026-01-15","time":"10:00","location":"Zoom","reminder_days_before":0}}}

If you cannot determine the content well, still return JSON with low confidence and best guess. Never return non-JSON text.''';
  }

  LAMResponse _fallbackResponse(String reason) {
    debugPrint('LAM fallback triggered: $reason');
    return LAMResponse(
      type: 'other',
      confidence: 0.0,
      summary: 'Could not analyze screenshot: $reason',
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
      confidence: (json['confidence'] ?? 0).toDouble().clamp(0.0, 1.0),
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
      case 'shopping': return '🛒';
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
