import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/screenshot.dart';
import 'lam_service.dart';
import 'local_chat_model.dart';
import 'web_lookup.dart';

/// Who wrote a [ChatReply]'s content.
///
/// This exists because a bool could not carry the fact. Local-only chat ends in
/// [ChatEngine.buildLocalReply] on seven different paths and in the on-device
/// model's own words on an eighth, and every one of them produces the same
/// shape of answer with the same evidence thumbnails underneath. That is why a
/// user who downloaded the model could report "same results as if I hadn't" and
/// be right: nothing on screen could tell them apart either.
///
/// One case per real branch of [ChatEngine._localReply], and
/// [ChatReply.source] has no default, so a branch that forgets to name one does
/// not compile. The widget layer switches over the whole enum, so adding a case
/// is a compile error there too.
enum ChatAnswerSource {
  /// A cloud provider wrote this. Provenance is not in doubt on that path -- the
  /// user chose the provider and was asked for consent -- so the widget layer
  /// says nothing extra about it.
  cloudAnswer,

  /// No cloud answer: the saved provider is not supported, or consent was
  /// refused. Neither from a model nor from the index.
  cloudUnavailable,

  /// The on-device model wrote this, from the screenshot context it was given.
  onDeviceModel,

  /// Nothing matched, so nothing was asked. The model is never probed with no
  /// context: it would spend a load on a question there is no evidence for.
  noResults,

  /// No on-device model is wired here: never downloaded, or no model service at
  /// all.
  noModel,

  /// A model is on this device but the engine is not in memory, and the load
  /// did not fail. Answered from the index with a model sitting right there,
  /// which is the case most worth being honest about.
  modelNotReady,

  /// The engine could not be created on this device. [ChatReply.loadFailure]
  /// carries the model's own fixed copy saying why.
  modelLoadFailed,

  /// The model threw while answering. The engine swallows that so a model
  /// failure can never become a chat error, which also means nothing about it
  /// reaches the user unless it is said here.
  modelFailed,

  /// The model answered with nothing usable.
  modelEmpty,
}

/// Result of a chat reply build: the assistant text, any related links, and
/// whether the reply was blocked (privacy consent denied).
class ChatReply {
  final String content;
  final List<Map<String, String>> relatedLinks;
  final bool blocked;

  /// Which path produced [content]. Required and undefaulted on purpose: the
  /// defect was a branch that quietly rendered like another one, so forgetting
  /// to name the path has to be a compile error rather than a silent default.
  final ChatAnswerSource source;

  /// The on-device model's own fixed explanation when the engine could not be
  /// loaded, or null. It rides out with the reply rather than staying in the
  /// settings row because the reply is where the user is looking when they
  /// wonder why the answer reads like a keyword list. Never a raw plugin,
  /// socket, or platform error -- that is what [LocalChatModel.statusMessage]
  /// already refuses to be.
  final String? loadFailure;

  const ChatReply({
    required this.content,
    required this.source,
    this.relatedLinks = const [],
    this.blocked = false,
    this.loadFailure,
  });

  /// Whether a model wrote [content], rather than the plain keyword list. A
  /// cloud provider counts: it is a model, and the user picked it.
  bool get answeredByModel =>
      source == ChatAnswerSource.onDeviceModel ||
      source == ChatAnswerSource.cloudAnswer;
}

/// Builds a chat reply from a query and the matching screenshots, outside the
/// widget layer so the whole pipeline is unit-testable with plain test()s.
class ChatEngine {
  final LAMService lam;
  final Future<bool> Function() consentCheck;

  /// On-device model for local-only chat. Null wherever no model is wired, and
  /// local-only then keeps the plain [buildLocalReply] answer. Injected as the
  /// interface so the widget layer owns the model and tests can fake it.
  final LocalChatModel? localModel;

  final Future<List<WebResult>> Function({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required List<String> objects,
    required String? youTubeApiKey,
  }) lookup;

  ChatEngine({
    required this.lam,
    required this.consentCheck,
    this.localModel,
    Future<List<WebResult>> Function({
      required String extractedText,
      required String summary,
      required List<String> recognitions,
      required List<String> objects,
      required String? youTubeApiKey,
    })? lookup,
  }) : lookup = lookup ?? WebLookupService().lookup;

  Future<ChatReply> reply({
    required String text,
    required List<Screenshot> results,
    required bool localOnly,
  }) async {
    // Phase A: URLs embedded in the matched screenshots' own text. Pure
    // local reads — safe in Local-only mode, and thumbnails are stripped
    // there so nothing is ever fetched from the network.
    final embedded = _embeddedLinks(results, includeThumbs: !localOnly);

    if (localOnly) {
      // Local-only is the mode where the two paths are indistinguishable, so
      // the reply carries which one ran. Nothing here is conditional on it:
      // every branch below already knew, and only the answer was being thrown
      // away.
      final local = await _localReply(text, results);
      return ChatReply(
        content: local.content,
        relatedLinks: embedded,
        source: local.source,
        loadFailure: local.loadFailure,
      );
    }

    // Resolve no key until the persisted name is known to be supported.
    final prefs = await SharedPreferences.getInstance();
    final providerName =
        prefs.getString('provider') ?? AppConfig.defaultProvider;
    if (!lam.availableProviders.any((p) => p.name == providerName)) {
      return const ChatReply(
        content: LAMService.unsupportedProviderReply,
        source: ChatAnswerSource.cloudUnavailable,
      );
    }

    final ok = await consentCheck();
    if (!ok) {
      return const ChatReply(
        content:
            'Cloud chat needs your consent before it sends screenshot-derived text and context to the selected provider. Optional source lookup can also query the web. Local-only mode keeps both on-device. Screenshot images and OCR text stay on this device; Google Play services may download the small image-labeling model on first use. The optional on-device chat model is not bundled: SIFT downloads it once from Hugging Face when you set it up, then runs it on this device with LiteRT-LM.',
        blocked: true,
        source: ChatAnswerSource.cloudUnavailable,
      );
    }

    // Only a key the user saved counts. There is no bundled or CI-injected
    // fallback, so no saved key means no hosted request.
    final savedKey = (prefs.getString('key_$providerName') ?? '').trim();
    final apiKey = savedKey.isEmpty ? null : savedKey;
    // LLM answer and the link hunt run in parallel. Future.wait joins both
    // so neither future can be orphaned if the other completes with an error
    // (each already swallows its own failures).
    final replyFuture = lam.chat(
      text,
      context: buildContextText(results),
      apiKey: apiKey,
      provider: providerName,
    );
    final linksFuture = _lookupLinks(results);
    final joined = await Future.wait<Object>([replyFuture, linksFuture]);
    final cloudText = joined[0] as String;
    return ChatReply(
      content: cloudText,
      relatedLinks: joined[1] as List<Map<String, String>>,
      // `LAMService.chat` swallows its own errors and answers with fixed copy,
      // so the only way to tell a provider that answered from a provider that
      // could not be reached is to compare against that copy. Reporting the
      // failure as [ChatAnswerSource.cloudAnswer] would be the same defect as
      // the local one this field was added to fix: a failure rendered as though
      // a model had written it.
      source: cloudText == LAMService.unreachableProviderReply
          ? ChatAnswerSource.cloudUnavailable
          : ChatAnswerSource.cloudAnswer,
    );
  }

  /// Phase A: URLs embedded in every matched screenshot's text, in rank
  /// order, de-duplicated, capped at three. Never touches the network.
  List<Map<String, String>> _embeddedLinks(
    List<Screenshot> results, {
    required bool includeThumbs,
  }) {
    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final s in results) {
      for (final r in WebLookupService.extractUrlsFromText(s.ocrText ?? '')) {
        if (!seen.add(r.url)) continue;
        out.add({
          'title': r.title,
          'url': r.url,
          if (includeThumbs && r.thumbnail.isNotEmpty) 'thumb': r.thumbnail,
        });
        if (out.length >= 3) return out;
      }
    }
    return out;
  }

  /// The full link set for a reply: embedded URLs from every matched
  /// screenshot, then — only when that comes up short — a single online
  /// lookup on the first result with real searchable content. Enriched
  /// results (real titles/thumbnails) override bare embedded links with the
  /// same URL. Exactly one lookup call per reply, at most.
  Future<List<Map<String, String>>> _lookupLinks(
    List<Screenshot> results,
  ) async {
    final merged = <String, Map<String, String>>{};
    for (final r in _embeddedLinks(results, includeThumbs: true)) {
      merged[r['url']!] = r;
    }
    if (merged.length >= 3) return merged.values.take(3).toList();

    for (final s in results) {
      final text = (s.ocrText ?? '').trim();
      final summary = (s.summary ?? '').trim();
      if (text.isEmpty &&
          summary.isEmpty &&
          s.recognitions.isEmpty &&
          s.objects.isEmpty) {
        continue;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedYouTubeKey = (prefs.getString('key_youtube') ?? '').trim();
        final youTubeKey = savedYouTubeKey.isEmpty ? null : savedYouTubeKey;
        final found = await lookup(
          extractedText: text,
          summary: summary == 'No text found' ? '' : summary,
          recognitions: s.recognitions,
          objects: s.objects,
          youTubeApiKey: youTubeKey,
        );
        for (final r in found) {
          merged[r.url] = {
            'title': r.title,
            'url': r.url,
            if (r.thumbnail.isNotEmpty) 'thumb': r.thumbnail,
          };
        }
        return merged.values.take(3).toList();
      } catch (_) {
        return merged.values.take(3).toList();
      }
    }
    return merged.values.take(3).toList();
  }

  /// Answer for local-only mode. The on-device model is preferred when it is
  /// usable and there is screenshot context to ground it; every other case —
  /// no model, not installed, still loading, failed, empty answer, or a throw
  /// — keeps the existing plain local reply. Nothing here reaches the network,
  /// and a missing model is never downloaded on the user's behalf.
  ///
  /// Returns which of those it was next to the text, because the text alone is
  /// the defect this whole change exists for: every branch below renders the
  /// same way, so a user could not tell a model answer from a keyword list, and
  /// neither could the screen. [ChatAnswerSource] carries one case per branch
  /// and [ChatReply.source] is undefaulted, so a new branch cannot join that
  /// list quietly.
  ///
  /// `loadFailure` is populated only where the model itself explained the
  /// failure in fixed copy. A throw is not one of those: the engine has already
  /// decided a raw error never reaches the user, so it stays swallowed and the
  /// branch reports only that the model did not answer.
  Future<({String content, ChatAnswerSource source, String? loadFailure})>
      _localReply(
    String text,
    List<Screenshot> results,
  ) async {
    final fallback = buildLocalReply(results);
    final model = localModel;
    // Decided before any load is attempted, for two separate reasons that were
    // previously collapsed into one `||`. No model: there is nothing to try.
    // No results: there is no context to ground an answer in, and a load would
    // turn a question with no evidence into the most expensive thing SIFT can
    // do. Which one it was is the difference between "you have not set the
    // model up" and "there is nothing to answer", and the user is told which.
    if (model == null) {
      return (
        content: fallback,
        source: ChatAnswerSource.noModel,
        loadFailure: null,
      );
    }
    if (results.isEmpty) {
      return (
        content: fallback,
        source: ChatAnswerSource.noResults,
        loadFailure: null,
      );
    }
    try {
      if (!await model.ensureLoaded()) {
        // A failed load leaves the model in `error` carrying fixed copy that
        // says why in plain words. That copy is the only thing the user can act
        // on, and without it the failure is invisible: the fallback looks
        // exactly like a model that simply had nothing to add. A false here
        // without `error` is a model that is not on this device at all.
        final failed = model.status == LocalChatModelStatus.error;
        return (
          content: fallback,
          source: failed
              ? ChatAnswerSource.modelLoadFailed
              : ChatAnswerSource.modelNotReady,
          loadFailure: failed ? model.statusMessage : null,
        );
      }
      if (!model.isUsable) {
        return (
          content: fallback,
          source: ChatAnswerSource.modelNotReady,
          loadFailure: model.status == LocalChatModelStatus.error
              ? model.statusMessage
              : null,
        );
      }
      final answer = await model.generate(
        prompt: _buildLocalPrompt(text),
        context: buildContextText(results),
      );
      final trimmed = answer.trim();
      // An empty answer is not an answer. Falling back to the keyword list
      // rather than showing a blank bubble is right; labelling that blank as a
      // model answer would not be.
      if (trimmed.isEmpty) {
        return (
          content: fallback,
          source: ChatAnswerSource.modelEmpty,
          loadFailure: null,
        );
      }
      return (
        content: trimmed,
        source: ChatAnswerSource.onDeviceModel,
        loadFailure: null,
      );
    } catch (_) {
      // The engine owns the fallback: a model failure must degrade to the
      // plain local reply, never surface as a chat error. The branch is still
      // named, because "it degraded" and "the model wrote this" are different
      // facts and the widget layer now says which one happened.
      return (
        content: fallback,
        source: ChatAnswerSource.modelFailed,
        loadFailure: null,
      );
    }
  }

  /// The question, as the model's one user turn. The grounding rules ride
  /// along as the model's system instruction inside the on-device
  /// implementation, so LiteRT-LM applies the model's own chat template around
  /// them; only the question itself is built here.
  String _buildLocalPrompt(String question) => 'QUESTION: $question';

  /// Max characters of OCR text to include per screenshot. Keeps context
  /// focused without losing the signal that matters.
  static const int _ocrCharsPerScreenshot = 500;

  /// Max total context characters sent to the LLM. Prevents token waste
  /// and keeps responses fast and focused.
  static const int _maxTotalContext = 4000;

  String buildContextText(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'No saved screenshots matched the query. Answer honestly that nothing matches.';
    }

    final sb = StringBuffer();
    var totalChars = 0;
    for (var i = 0; i < results.length; i++) {
      final s = results[i];
      final entry = StringBuffer();
      entry.writeln('[$i]');
      entry.writeln('  Summary: ${s.summary ?? 'No summary'}');
      if (s.description != null && s.description!.isNotEmpty) {
        entry.writeln('  Description: ${s.description}');
      }
      if (s.ocrText != null && s.ocrText!.isNotEmpty) {
        final ocr = s.ocrText!;
        final truncated = ocr.length > _ocrCharsPerScreenshot
            ? '${ocr.substring(0, _ocrCharsPerScreenshot)}…'
            : ocr;
        entry.writeln('  Text: $truncated');
      }
      if (s.recognitions.isNotEmpty) {
        entry.writeln('  Recognitions: ${s.recognitions.join(', ')}');
      }
      if (s.objects.isNotEmpty) {
        entry.writeln('  Objects: ${s.objects.join(', ')}');
      }
      if (s.lamType != null) {
        entry.writeln('  Type: ${s.lamType}');
      }
      entry.writeln('  Taken: ${s.timestamp.toIso8601String()}');
      entry.writeln();

      // Skip this screenshot if adding it would exceed the total context cap.
      if (totalChars + entry.length > _maxTotalContext && i > 0) break;
      totalChars += entry.length;
      sb.write(entry);
    }
    return sb.toString();
  }

  String buildLocalReply(List<Screenshot> results) {
    if (results.isEmpty) {
      return 'Nothing found in your saved screenshots. '
          'Local-only chat stays on-device; cloud chat and source lookup are disabled.';
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
