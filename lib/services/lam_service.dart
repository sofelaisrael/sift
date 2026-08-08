import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Multi-provider free LLM service with fallback chain
class LAMService {
  String _lastError = '';

  // Provider configs (OpenAI-compatible endpoints)
  static const List<ProviderConfig> _providers = [
    // Free multimodal providers (support image input)
    ProviderConfig(
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-3.5-flash',
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
    ProviderConfig(
      name: 'NVIDIA',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.2-90b-vision-instruct',
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
    final mimeType = _mimeFromPath(imagePath);
    _lastError = '';

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
          final response = await _callProvider(p, base64Image: base64Image, mimeType: mimeType, apiKey: apiKey);
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
          final response = await _callProvider(p, base64Image: base64Image, mimeType: mimeType, apiKey: apiKey);
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
    String? mimeType,
  }) async {
    if (provider.format == ProviderFormat.gemini) {
      return _callGemini(provider, base64Image: base64Image, text: text, apiKey: apiKey!, mimeType: mimeType);
    } else {
      return _callOpenAI(provider, base64Image: base64Image, text: text, apiKey: apiKey, mimeType: mimeType);
    }
  }

  Future<LAMResponse?> _callGemini(
    ProviderConfig provider, {
    String? base64Image,
    String? text,
    required String apiKey,
    String? mimeType,
  }) async {
    final parts = <Map<String, dynamic>>[];

    if (text != null) {
      parts.add({'text': 'Screenshot text:\n$text'});
    }

    if (base64Image != null) {
      parts.add({
        'inlineData': {
          'mimeType': mimeType ?? 'image/png',
          'data': base64Image,
        },
      });
    }

    parts.add({'text': '\n\nAnalyze this. Return ONLY valid JSON, no explanation.'});

    final response = await _retry429(() => http.post(
          Uri.parse('${provider.baseUrl}/models/${provider.model}:generateContent?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [{'parts': parts}],
            'systemInstruction': {'parts': [{'text': _buildSystemPrompt()}]},
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': 4096,
            },
          }),
        ));

    if (response.statusCode != 200) {
      _lastError = '${provider.name} returned HTTP ${response.statusCode}';
      debugPrint('Gemini error: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // Thinking models can stream the answer across multiple parts; join them
    // all instead of reading only parts[0].
    final partsList = body['candidates']?[0]?['content']?['parts'] as List? ?? const [];
    final content = partsList
        .map((p) => (p is Map && p['text'] is String) ? p['text'] as String : '')
        .where((t) => t.isNotEmpty)
        .join('\n');
    if (content.isEmpty) {
      _lastError = '${provider.name} returned an empty response';
      return null;
    }

    return _parseResponse(content);
  }

  Future<LAMResponse?> _callOpenAI(
    ProviderConfig provider, {
    String? base64Image,
    String? text,
    String? apiKey,
    String? mimeType,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt()},
    ];

    if (base64Image != null) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Describe what you see in this screenshot — the scene, objects, and context — and extract all visible text. Return ONLY valid JSON.'},
          {'type': 'image_url', 'image_url': {'url': 'data:${mimeType ?? 'image/png'};base64,$base64Image'}},
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
      headers['X-Title'] = 'Sift';
    }

    final response = await _retry429(() => http.post(
          Uri.parse('${provider.baseUrl}/chat/completions'),
          headers: headers,
          body: jsonEncode({
            'model': provider.model,
            'messages': messages,
            'temperature': 0.1,
            'max_tokens': 1024,
          }),
        ));

    if (response.statusCode != 200) {
      _lastError = '${provider.name} returned HTTP ${response.statusCode}';
      debugPrint('${provider.name} error ${response.statusCode}: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    if (content == null) return null;

    return _parseResponse(content);
  }

  LAMResponse _parseResponse(String content) {
    final json = _extractJsonObject(content);
    if (json == null) {
      debugPrint('JSON parse failed. Raw content: ${content.substring(0, content.length > 400 ? 400 : content.length)}');
      return _fallbackResponse('JSON parse error');
    }

    try {
      return LAMResponse.fromJson(json);
    } catch (e) {
      debugPrint('JSON parse failed: $e');
      return _fallbackResponse('JSON parse error');
    }
  }

  /// Tolerantly extract a JSON object from a model response that may contain
  /// markdown fences, prose, or multiple text parts. Returns null if no valid
  /// JSON object can be found.
  Map<String, dynamic>? _extractJsonObject(String content) {
    // 1. Strip markdown code fences (```json ... ```) if present.
    var cleaned = content.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*```$', multiLine: true), '');
    cleaned = cleaned.trim();

    // 2. Find the outermost { ... } block, ignoring any prose around it.
    final start = cleaned.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    var end = -1;
    for (var i = start; i < cleaned.length; i++) {
      final ch = cleaned[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;

    try {
      final decoded = jsonDecode(cleaned.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  String _buildSystemPrompt() {
    return '''You are SIFT, a screenshot intelligence engine. You deeply understand screenshots — the scene, the context, and the objects — not just the text.

MISSION (in order):
1. DESCRIBE WHAT YOU SEE — open-ended visual understanding, whatever the image is: a photo, a screenshot, a poster, a receipt, a diagram. Describe the subjects, people, animals, objects, setting, composition, colors, and mood.
2. RECOGNIZE — identify anything recognizable: people, animals, places, landmarks, products, brands, artwork, movies/TV shows, or — if it's a screen — the app or website.
3. READ — if there is visible text, extract ALL of it verbatim where possible, including buttons, labels, dates, times, prices, lists, and URLs.
4. SUMMARIZE — write a short, natural-language summary of what the image shows and why it matters.
5. DETERMINE ACTION — if the content implies a useful action (calendar, reminder, shopping list, task), suggest it; otherwise use "none".

CONFIDENCE SCORING:
- 0.9-1.0: You clearly recognize the content (a flight booking, a recipe, a product page, a portrait, a known landmark) with high confidence
- 0.7-0.89: You see recognizable content but some details are unclear
- 0.5-0.69: You see content but aren't sure of the context
- 0.3-0.49: Very little recognizable content, mostly guessing
- 0.0-0.29: Cannot meaningfully analyze the image

RESPONSE FORMAT (JSON only — no explanation, no markdown, no code fences):
{
  "type": "flight|recipe|deadline|product|meeting|shopping|document|other",
  "confidence": 0.0-1.0,
  "summary": "One or two sentences: what this image is, in plain natural language",
  "description": "2-4 sentences describing the image in detail: subjects, objects, setting, composition, mood",
  "objects": ["visible objects or visual elements, e.g. 'dog', 'skyline', 'grocery cart', 'airplane seat map', 'movie poster'"],
  "recognitions": ["anything you recognize, e.g. 'Golden Retriever', 'Eiffel Tower', 'Starbucks', 'TikTok', 'Google Flights'"],
  "extracted_text": "All visible text from the image, kept verbatim where possible (empty string if none)",
  "extracted_data": {
    "all relevant structured fields you can extract"
  },
  "suggested_action": {
    "type": "add_calendar|create_reminder|create_shopping_list|create_task|none",
    "data": {
      "fields needed for the action"
    }
  }
}

If you cannot determine the content well, still return valid JSON with low confidence and your best guess. Never return non-JSON text.''';
  }

  LAMResponse _fallbackResponse(String reason) {
    final msg = _lastError.isNotEmpty ? '$_lastError.' : reason;
    debugPrint('LAM fallback triggered: $msg');
    return LAMResponse(
      type: 'other',
      confidence: 0.0,
      summary: 'Could not analyze screenshot: $msg',
      description: 'Analysis failed. $msg',
      extractedData: {},
      suggestedAction: LAMAction(type: 'none', data: {}),
    );
  }

  /// Detect the real image MIME type from the file extension, so we don't
  /// send JPEG/WebP bytes mismarked as PNG (which providers reject).
  String _mimeFromPath(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/png';
    }
  }

  /// Retry once after a short delay when a provider rate-limits us (429).
  Future<http.Response> _retry429(Future<http.Response> Function() post) async {
    var response = await post();
    if (response.statusCode == 429) {
      await Future.delayed(const Duration(seconds: 3));
      response = await post();
    }
    return response;
  }

  /// Get list of available providers
  List<ProviderConfig> get availableProviders => _providers;

  /// Chat with the AI about the user's screenshots.
  /// [context] is pre-built text describing relevant screenshots.
  /// Tries the selected provider, then falls back through the chain.
  Future<String> chat(
    String message, {
    required String context,
    String? apiKey,
    String? provider,
  }) async {
    final providers = provider != null
        ? [
            _providers.firstWhere(
              (p) => p.name == provider,
              orElse: () => _providers.first,
            ),
          ]
        : _providers;

    for (final p in providers) {
      if (p.requiresKey && (apiKey == null || apiKey.isEmpty)) continue;
      try {
        debugPrint('Chat: trying ${p.name}...');
        final reply = await _chatCall(p, message: message, context: context, apiKey: apiKey);
        if (reply != null && reply.isNotEmpty) return reply;
      } catch (e) {
        debugPrint('${p.name} chat failed: $e');
      }
    }

    return 'Sorry, I could not reach any AI provider right now. Check your API key in Settings.';
  }

  Future<String?> _chatCall(
    ProviderConfig provider, {
    required String message,
    required String context,
    String? apiKey,
  }) async {
    if (provider.format == ProviderFormat.gemini) {
      return _chatGemini(provider, message: message, context: context, apiKey: apiKey!);
    }
    return _chatOpenAI(provider, message: message, context: context, apiKey: apiKey);
  }

  Future<String?> _chatGemini(
    ProviderConfig provider, {
    required String message,
    required String context,
    required String apiKey,
  }) async {
    final response = await http.post(
      Uri.parse('${provider.baseUrl}/models/${provider.model}:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': _buildChatSystemPrompt()},
            ],
          },
          {
            'role': 'user',
            'parts': [
              {'text': 'CONTEXT (your screenshots):\n$context'},
            ],
          },
          {
            'role': 'user',
            'parts': [
              {'text': message},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 1024,
        },
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('Gemini chat error: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    return content?.trim();
  }

  Future<String?> _chatOpenAI(
    ProviderConfig provider, {
    required String message,
    required String context,
    String? apiKey,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    if (provider.name == 'OpenRouter') {
      headers['HTTP-Referer'] = 'https://screensort.app';
      headers['X-Title'] = 'Sift';
    }

    final response = await http.post(
      Uri.parse('${provider.baseUrl}/chat/completions'),
      headers: headers,
      body: jsonEncode({
        'model': provider.model,
        'messages': [
          {'role': 'system', 'content': _buildChatSystemPrompt()},
          {'role': 'user', 'content': 'CONTEXT (your screenshots):\n$context'},
          {'role': 'user', 'content': message},
        ],
        'temperature': 0.3,
        'max_tokens': 1024,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('${provider.name} chat error ${response.statusCode}: ${response.body}');
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content'] as String?;
    return content?.trim();
  }

  String _buildChatSystemPrompt() {
    return '''You are SIFT, an assistant that helps the user remember and find things from their saved screenshots.

You will be given CONTEXT — a list of the user's screenshots, most relevant first. Each entry includes a summary, a description, visible text, recognitions, and the date it was taken.

RULES:
1. Answer ONLY based on the provided context. Do not invent screenshots or details that are not there.
2. If the context does not answer the question, say so honestly and suggest what to look for.
3. Be concise and conversational. When relevant, tie the answer to a specific screenshot (e.g., "the TikTok you saved last week about...").
4. Do not mention that you are reading from a context list. Just answer naturally.''';
  }
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
  final String description;
  final List<String> objects;
  final List<String> recognitions;
  final String extractedText;
  final Map<String, dynamic> extractedData;
  final LAMAction suggestedAction;

  LAMResponse({
    required this.type,
    required this.confidence,
    required this.summary,
    this.description = '',
    this.objects = const [],
    this.recognitions = const [],
    this.extractedText = '',
    this.extractedData = const {},
    required this.suggestedAction,
  });

  factory LAMResponse.fromJson(Map<String, dynamic> json) {
    return LAMResponse(
      type: json['type'] ?? 'other',
      confidence: (json['confidence'] ?? 0).toDouble().clamp(0.0, 1.0),
      summary: json['summary'] ?? '',
      description: (json['description'] as String? ?? json['summary'] ?? ''),
      objects: _toStringList(json['objects']),
      recognitions: _toStringList(json['recognitions']),
      extractedText: json['extracted_text'] as String? ?? '',
      extractedData: json['extracted_data'] ?? {},
      suggestedAction: LAMAction.fromJson(json['suggested_action'] ?? {}),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    if (value is String && value.isNotEmpty) {
      return [value];
    }
    return const [];
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
