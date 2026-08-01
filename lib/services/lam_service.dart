import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Multi-provider free LLM service with fallback chain
class LAMService {
  // Provider configs (OpenAI-compatible endpoints)
  static const List<ProviderConfig> _providers = [
    // Free multimodal providers (support image input)
    ProviderConfig(
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.5-flash',
      requiresKey: true,
      supportsImage: true,
      format: ProviderFormat.gemini,
    ),
    ProviderConfig(
      name: 'Cerebras',
      baseUrl: 'https://api.cerebras.ai/v1',
      model: 'gemma-4-31b',
      requiresKey: true,
      supportsImage: true,
      format: ProviderFormat.openai,
    ),
    ProviderConfig(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'google/gemma-4-31b-it:free',
      requiresKey: true,
      supportsImage: true,
      format: ProviderFormat.openai,
    ),
    // Free text-only providers (fallback)
    ProviderConfig(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      requiresKey: true,
      supportsImage: false,
      format: ProviderFormat.openai,
    ),
    ProviderConfig(
      name: 'OVHcloud',
      baseUrl: 'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1',
      model: 'Meta-Llama-3_3-70B-Instruct',
      requiresKey: false,
      supportsImage: false,
      format: ProviderFormat.openai,
    ),
  ];

  /// Analyze screenshot by sending the image directly to a multimodal model
  /// Falls back to OCR + text for text-only providers like Groq
  Future<LAMResponse> analyzeImage(String imagePath, {String? apiKey, String? provider}) async {
    final imageBytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);

    // Try the selected provider first
    if (provider != null) {
      final p = _providers.firstWhere(
        (p) => p.name == provider,
        orElse: () => _providers.first,
      );

      if (p.requiresKey && (apiKey == null || apiKey.isEmpty)) {
        debugPrint('${p.name} needs API key');
      } else if (p.supportsImage) {
        // Multimodal - send image directly
        debugPrint('Trying ${p.name} with image...');
        try {
          final response = await _callProvider(p, base64Image: base64Image, apiKey: apiKey);
          if (response != null) return response;
        } catch (e) {
          debugPrint('${p.name} failed: $e');
        }
      } else {
        // Text-only provider (like Groq) - need OCR first
        debugPrint('${p.name} is text-only, doing OCR first...');
        try {
          final ocrText = await _extractTextFromImage(imagePath);
          if (ocrText.isNotEmpty) {
            final response = await _callProvider(p, text: ocrText, apiKey: apiKey);
            if (response != null) return response;
          }
        } catch (e) {
          debugPrint('OCR + ${p.name} failed: $e');
        }
      }
    }

    // Fallback: try all providers
    for (final p in _providers) {
      if (p.requiresKey && (apiKey == null || apiKey.isEmpty)) continue;
      
      try {
        if (p.supportsImage) {
          debugPrint('Fallback: trying ${p.name} with image...');
          final response = await _callProvider(p, base64Image: base64Image, apiKey: apiKey);
          if (response != null) return response;
        } else {
          debugPrint('Fallback: trying ${p.name} with OCR...');
          final ocrText = await _extractTextFromImage(imagePath);
          if (ocrText.isNotEmpty) {
            final response = await _callProvider(p, text: ocrText, apiKey: apiKey);
            if (response != null) return response;
          }
        }
      } catch (e) {
        debugPrint('${p.name} fallback failed: $e');
        continue;
      }
    }

    return _fallbackResponse('No available provider');
  }

  /// Simple OCR using ML Kit
  Future<String> _extractTextFromImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();
      
      return result.text;
    } catch (e) {
      debugPrint('OCR failed: $e');
      return '';
    }
  }

  /// Analyze via OCR text (fallback when image fails)
  Future<LAMResponse> processScreenshot(String ocrText, {String? apiKey, String? provider}) async {
    for (final p in _providers) {
      if (provider != null && p.name != provider) continue;
      if (p.requiresKey && (apiKey == null || apiKey.isEmpty)) continue;

      debugPrint('Trying provider: ${p.name}');
      try {
        final response = await _callProvider(p, text: ocrText, apiKey: apiKey);
        if (response != null) return response;
      } catch (e) {
        debugPrint('${p.name} failed: $e');
        continue;
      }
    }

    return _fallbackResponse('No available provider');
  }

  Future<LAMResponse?> _callProvider(
    ProviderConfig provider, {
    String? base64Image,
    String? text,
    String? apiKey,
  }) async {
    if (provider.format == ProviderFormat.gemini) {
      return _callGemini(provider, base64Image: base64Image, text: text, apiKey: apiKey!);
    } else {
      return _callOpenAI(provider, base64Image: base64Image, text: text, apiKey: apiKey);
    }
  }

  Future<LAMResponse?> _callGemini(
    ProviderConfig provider, {
    String? base64Image,
    String? text,
    required String apiKey,
  }) async {
    final parts = <Map<String, dynamic>>[];

    if (text != null) {
      parts.add({'text': 'Screenshot text:\n$text'});
    }

    if (base64Image != null) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/png',
          'data': base64Image,
        },
      });
    }

    parts.add({'text': '\n\nAnalyze this. Return ONLY valid JSON, no explanation.'});

    final response = await http.post(
      Uri.parse('${provider.baseUrl}/models/${provider.model}:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': parts}],
        'systemInstruction': {'parts': [{'text': _buildSystemPrompt()}]},
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 1024,
        },
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('Gemini error: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (content == null) return null;

    return _parseResponse(content);
  }

  Future<LAMResponse?> _callOpenAI(
    ProviderConfig provider, {
    String? base64Image,
    String? text,
    String? apiKey,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt()},
    ];

    if (base64Image != null) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Analyze this screenshot. Extract all visible text and context. Return ONLY valid JSON.'},
          {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$base64Image'}},
        ],
      });
    } else if (text != null) {
      messages.add({'role': 'user', 'content': 'Screenshot text:\n$text'});
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    if (provider.name == 'OpenRouter') {
      headers['HTTP-Referer'] = 'https://screensort.app';
      headers['X-Title'] = 'ScreenSort';
    }

    final response = await http.post(
      Uri.parse('${provider.baseUrl}/chat/completions'),
      headers: headers,
      body: jsonEncode({
        'model': provider.model,
        'messages': messages,
        'temperature': 0.1,
        'max_tokens': 1024,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('${provider.name} error ${response.statusCode}: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null) return null;

    return _parseResponse(content);
  }

  LAMResponse _parseResponse(String content) {
    var cleaned = content.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
    }

    try {
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return LAMResponse.fromJson(json);
    } catch (e) {
      debugPrint('JSON parse failed: $e');
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

  /// Get list of available providers
  List<ProviderConfig> get availableProviders => _providers;
}

enum ProviderFormat { openai, gemini }

class ProviderConfig {
  final String name;
  final String baseUrl;
  final String model;
  final bool requiresKey;
  final bool supportsImage;
  final ProviderFormat format;

  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.requiresKey,
    required this.supportsImage,
    required this.format,
  });
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
