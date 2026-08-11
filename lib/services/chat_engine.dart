import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/screenshot.dart';
import 'lam_service.dart';
import 'web_lookup.dart';

/// Result of a chat reply build: the assistant text, any related links, and
/// whether the reply was blocked (privacy consent denied).
class ChatReply {
  final String content;
  final List<Map<String, String>> relatedLinks;
  final bool blocked;

  const ChatReply({
    required this.content,
    this.relatedLinks = const [],
    this.blocked = false,
  });
}

/// Builds a chat reply from a query and the matching screenshots, outside the
/// widget layer so the whole pipeline is unit-testable with plain test()s.
class ChatEngine {
  final LAMService lam;
  final Future<bool> Function() consentCheck;
  final Future<List<WebResult>> Function({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required String? youTubeApiKey,
  }) lookup;

  ChatEngine({
    required this.lam,
    required this.consentCheck,
    Future<List<WebResult>> Function({
      required String extractedText,
      required String summary,
      required List<String> recognitions,
      required String? youTubeApiKey,
    })? lookup,
  }) : lookup = lookup ?? WebLookupService().lookup;

  Future<ChatReply> reply({
    required String text,
    required List<Screenshot> results,
    required bool localOnly,
  }) async {
    if (localOnly) {
      return ChatReply(content: buildLocalReply(results));
    }

    final ok = await consentCheck();
    if (!ok) {
      return const ChatReply(
        content:
            'Privacy consent is required before Sift sends anything to an AI provider. You can grant it the next time you analyze a screenshot, or enable Local-only mode in More.',
        blocked: true,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final providerName =
        prefs.getString('provider') ?? AppConfig.defaultProvider;
    final savedKey = prefs.getString('key_$providerName') ?? '';
    final apiKey =
        savedKey.isNotEmpty ? savedKey : AppConfig.apiKeyFor(providerName);
    // LLM answer and the web lookup for the top match run in parallel.
    // Future.wait joins both so neither future can be orphaned if the other
    // completes with an error (each already swallows its own failures).
    final replyFuture = lam.chat(
      text,
      context: buildContextText(results),
      apiKey: apiKey,
      provider: providerName,
    );
    final linksFuture = results.isEmpty
        ? Future.value(const <Map<String, String>>[])
        : _maybeLookupLinks(results.first);
    final joined = await Future.wait<Object>([replyFuture, linksFuture]);
    return ChatReply(
      content: joined[0] as String,
      relatedLinks: joined[1] as List<Map<String, String>>,
    );
  }

  /// Web links for the top match, grounded in real content: skipped when the
  /// screenshot has nothing substantive to search on, or the user is in
  /// Local-only mode (consent was already checked by the caller).
  Future<List<Map<String, String>>> _maybeLookupLinks(Screenshot top) async {
    final text = (top.ocrText ?? '').trim();
    final summary = (top.summary ?? '').trim();
    if (text.isEmpty && summary.isEmpty && top.recognitions.isEmpty) {
      return const [];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedYouTubeKey = prefs.getString('key_youtube') ?? '';
      final youTubeKey = savedYouTubeKey.isNotEmpty
          ? savedYouTubeKey
          : AppConfig.youTubeApiKey;
      final results = await lookup(
        extractedText: text,
        summary: summary == 'No text found' ? '' : summary,
        recognitions: top.recognitions,
        youTubeApiKey: youTubeKey,
      );
      return results
          .take(3)
          .map((r) => {'title': r.title, 'url': r.url})
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String buildContextText(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'No saved screenshots matched the query. Answer honestly that nothing matches.';
    }

    final sb = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final s = results[i];
      sb.writeln('[$i]');
      sb.writeln('  Summary: ${s.summary ?? 'No summary'}');
      if (s.description != null && s.description!.isNotEmpty) {
        sb.writeln('  Description: ${s.description}');
      }
      if (s.ocrText != null && s.ocrText!.isNotEmpty) {
        sb.writeln('  Text: ${s.ocrText}');
      }
      if (s.recognitions.isNotEmpty) {
        sb.writeln('  Recognitions: ${s.recognitions.join(', ')}');
      }
      if (s.objects.isNotEmpty) {
        sb.writeln('  Objects: ${s.objects.join(', ')}');
      }
      if (s.lamType != null) {
        sb.writeln('  Type: ${s.lamType}');
      }
      sb.writeln('  Taken: ${s.timestamp.toIso8601String()}');
      sb.writeln();
    }
    return sb.toString();
  }

  String buildLocalReply(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'Nothing found in your saved screenshots. '
          'Local-only mode searches on-device text only — no AI.';
    }
    final capped = results.take(5).toList();
    final sb = StringBuffer('Found ${results.length} matching screenshots:');
    for (final s in capped) {
      sb.write('\n• ${s.summary ?? 'No summary'}');
      if (s.recognitions.isNotEmpty) {
        sb.write(' (${s.recognitions.join(', ')})');
      }
    }
    return sb.toString();
  }
}
