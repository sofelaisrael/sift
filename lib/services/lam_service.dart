import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'action_model.dart';

export 'action_model.dart';

/// Hosted text chat service. Screenshot analysis stays on-device.
class LAMService {
  static const String unsupportedProviderReply =
      'Choose a supported provider in More to continue.';

  final http.Client _client;

  LAMService({http.Client? client}) : _client = client ?? http.Client();

  // Provider configs (OpenAI-compatible endpoints)
  static const List<ProviderConfig> _providers = [
    ProviderConfig(
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-3.5-flash',
      requiresKey: true,
      format: ProviderFormat.gemini,
    ),
    ProviderConfig(
      name: 'NVIDIA',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.2-90b-vision-instruct',
      requiresKey: true,
      format: ProviderFormat.openai,
    ),
    ProviderConfig(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      requiresKey: true,
      format: ProviderFormat.openai,
    ),
  ];

  /// Get list of available providers
  List<ProviderConfig> get availableProviders => _providers;

  /// Chat with the AI about the user's screenshots.
  /// [context] is pre-built text describing relevant screenshots.
  /// Calls the selected provider only.
  Future<String> chat(
    String message, {
    required String context,
    String? apiKey,
    String? provider,
  }) async {
    // Never route an unknown name to the first configured provider.
    final List<ProviderConfig> providers;
    if (provider != null) {
      final selected = _providers.where((p) => p.name == provider).toList();
      if (selected.isEmpty) return unsupportedProviderReply;
      providers = selected;
    } else {
      providers = _providers;
    }

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
    final response = await _client.post(
      Uri.parse('${provider.baseUrl}/models/${provider.model}:generateContent'),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
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

    final response = await _client.post(
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

/// Tolerantly extract a JSON object from a model response that may contain
/// markdown fences, prose, or multiple text parts. Returns null if no valid
/// JSON object can be found. When a leading balanced block fails to decode
/// (e.g. a truncated "thinking" part), later blocks are tried in turn.
Map<String, dynamic>? extractJsonObject(String content) {
  // 1. Strip markdown code fences (```json ... ```) if present.
  var cleaned = content.trim();
  cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s*```$', multiLine: true), '');
  cleaned = cleaned.trim();

  // 2. Walk each outermost { ... } block, ignoring any prose around it.
  var cursor = 0;
  while (cursor < cleaned.length) {
    final start = cleaned.indexOf('{', cursor);
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
        } else if (ch == '\\') {
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
      // Fall through and try the next candidate block.
    }
    cursor = end + 1;
  }
  return null;
}

enum ProviderFormat { openai, gemini }

class ProviderConfig {
  final String name;
  final String baseUrl;
  final String model;
  final bool requiresKey;
  final ProviderFormat format;

  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.requiresKey,
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
  final List<String> searchKeywords;
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
    this.searchKeywords = const [],
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
      searchKeywords: _toStringList(json['search_keywords']),
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
