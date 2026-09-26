import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/services/chat_engine.dart';
import 'package:screensort_lam/services/lam_service.dart';
import 'package:screensort_lam/services/litert_local_chat_model.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/web_lookup.dart';

/// A stand-in for the on-device model. Records what the engine asked for so a
/// test can prove the question and the screenshot context both reached the
/// model, and can be pinned to any readiness state.
///
/// The grounding rules are no longer part of the prompt: they travel as the
/// runtime's system instruction inside the LiteRT-LM implementation, so a test
/// that wants to assert them looks at the spec constant instead.
class FakeLocalChatModel implements LocalChatModel {
  FakeLocalChatModel({
    this.status = LocalChatModelStatus.ready,
    this.statusMessage,
    this.answer = 'Your BA123 to Lisbon is on 12 March.',
    this.loadSucceeds = true,
    this.throwsOnGenerate = false,
  });

  @override
  LocalChatModelStatus status;
  @override
  String? statusMessage;
  String answer;
  bool loadSucceeds;
  bool throwsOnGenerate;

  final List<String> prompts = [];
  final List<String> contexts = [];
  final List<int> maxTokens = [];
  int loadCalls = 0;
  int removeCalls = 0;
  bool disposed = false;

  @override
  bool get isUsable => status == LocalChatModelStatus.ready;

  @override
  Future<bool> isInstalled() async =>
      status != LocalChatModelStatus.notInstalled;

  @override
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) async {
    onProgress?.call(LocalChatDownloadProgress(50));
    status = LocalChatModelStatus.installed;
  }

  @override
  Future<bool> ensureLoaded() async {
    loadCalls++;
    if (!loadSucceeds) {
      status = LocalChatModelStatus.error;
      statusMessage = 'The model could not be loaded on this device.';
      return false;
    }
    if (status == LocalChatModelStatus.installed) {
      status = LocalChatModelStatus.ready;
    }
    return true;
  }

  @override
  Future<String> generate({
    required String prompt,
    required String context,
    int maxTokens = 256,
  }) async {
    prompts.add(prompt);
    contexts.add(context);
    this.maxTokens.add(maxTokens);
    if (throwsOnGenerate) throw StateError('model blew up');
    return answer;
  }

  @override
  Future<LocalModelRemoval> remove() async {
    removeCalls++;
    status = LocalChatModelStatus.notInstalled;
    return LocalModelRemoval.removed;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'provider': 'Google Gemini',
      'key_Google Gemini': 'test-key',
    });
  });

  Screenshot shot({
    String? ocrText,
    String? summary,
    List<String> recognitions = const [],
  }) =>
      Screenshot(
        id: 'shot1',
        fileName: 'flight.png',
        filePath: 'shots/flight.png',
        timestamp: DateTime(2026, 1, 1),
        ocrText: ocrText,
        summary: summary,
        recognitions: recognitions,
      );

  /// Any hosted request or source lookup is a failure in every local test.
  MockClient noNetworkClient() => MockClient((request) async {
        fail('local-only chat must make no request, saw ${request.url}');
      });

  Future<List<WebResult>> noLookup({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required List<String> objects,
    required String? youTubeApiKey,
  }) async {
    fail('local-only chat must not run a source lookup');
  }

  Future<bool> noConsent() async {
    fail('local-only chat must not ask for cloud consent');
  }

  test('a ready model answers from the screenshot context', () async {
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'What was that flight to Lisbon?',
      results: [
        shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking'),
      ],
      localOnly: true,
    );

    expect(reply.blocked, isFalse);
    expect(reply.content, 'Your BA123 to Lisbon is on 12 March.');
    // The fallback must not have won: the model's own text is the answer.
    expect(reply.content, isNot(contains('Found 1 matching screenshots')));
    expect(model.prompts, hasLength(1));
    expect(model.contexts, hasLength(1));
  });

  test('the prompt carries only the question; the rules ride with the model',
      () async {
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    await engine.reply(
      text: 'What was that flight to Lisbon?',
      results: [shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight')],
      localOnly: true,
    );

    final prompt = model.prompts.single;
    expect(prompt, 'QUESTION: What was that flight to Lisbon?');
    // The grounding rules must not be inlined into the user turn: LiteRT-LM
    // applies the model's own chat template, so a second copy in the prompt
    // would be duplicated by the runtime. They travel as the system
    // instruction, asserted against the spec constant in the model tests.
    expect(prompt, isNot(contains('RULES:')));
    expect(prompt, isNot(contains('Never invent a screenshot')));
  });

  test('the grounding rules are pinned as the runtime system instruction', () {
    // Kept here as well as in the model tests so a rewrite of either half of
    // the split (rules in the prompt, rules in the system instruction) is a
    // failing test rather than a silent behaviour change.
    expect(LiteRtLocalChatModel.systemInstruction,
        contains('Answer ONLY from the CONTEXT'));
    expect(LiteRtLocalChatModel.systemInstruction,
        contains('Never invent a screenshot'));
    expect(
      LiteRtLocalChatModel.systemInstruction,
      contains('say so plainly and stop'),
    );
    expect(LiteRtLocalChatModel.systemInstruction,
        contains('Be concise and plain text'));
  });

  test('the CONTEXT the model receives holds the matched screenshot text',
      () async {
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    await engine.reply(
      text: 'flight',
      results: [
        shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking'),
      ],
      localOnly: true,
    );

    // The engine passes the grounding block separately so an implementation
    // can trim it to its own context window.
    expect(model.contexts.single, contains('Flight BA123 to Lisbon'));
    expect(model.contexts.single, contains('  Summary: Flight booking'));
  });

  test('a missing model uses the plain local reply with zero network calls',
      () async {
    final model = FakeLocalChatModel(status: LocalChatModelStatus.notInstalled);

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [
        shot(ocrText: 'Flight BA123 to Lisbon', summary: 'Flight booking'),
      ],
      localOnly: true,
    );

    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
    // The model was probed for readiness but never asked to download or used.
    expect(model.loadCalls, 1);
    expect(model.prompts, isEmpty);
    expect(model.removeCalls, 0);
  });

  test('no model wired at all still answers with the plain local reply',
      () async {
    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: true,
    );

    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
  });

  test('a model that is still loading falls back without a second attempt',
      () async {
    final model = FakeLocalChatModel(
      status: LocalChatModelStatus.loading,
      loadSucceeds: false,
    );

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: true,
    );

    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
    expect(model.prompts, isEmpty);
  });

  test('a model in the error state falls back with zero network calls',
      () async {
    final model = FakeLocalChatModel(
      status: LocalChatModelStatus.error,
      statusMessage: 'The model could not be loaded on this device.',
    );

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: true,
    );

    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
    expect(model.prompts, isEmpty);
  });

  test('no matching screenshots keeps the no-match copy and skips the model',
      () async {
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: const [],
      localOnly: true,
    );

    expect(
      reply.content,
      'Nothing found in your saved screenshots. '
      'Local-only chat stays on-device; cloud chat and source lookup are disabled.',
    );
    expect(model.prompts, isEmpty);
    expect(model.loadCalls, 0);
  });

  test('a blank model answer degrades to the plain local reply', () async {
    final model = FakeLocalChatModel(answer: '   \n ');

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: true,
    );

    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
    expect(model.prompts, hasLength(1));
  });

  test('a throwing model degrades to the plain local reply', () async {
    final model = FakeLocalChatModel(throwsOnGenerate: true);

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: true,
    );

    expect(reply.blocked, isFalse);
    expect(reply.content, 'Found 1 matching screenshots:\n• Flight booking');
  });

  test('cloud mode never touches the local model', () async {
    var requests = 0;
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(
        client: MockClient((request) async {
          requests++;
          return http.Response(
            '{"candidates":[{"content":{"parts":[{"text":"Cloud answer."}]}}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
      consentCheck: () async => true,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'flight',
      results: [shot(ocrText: 'Flight BA123', summary: 'Flight booking')],
      localOnly: false,
    );

    expect(reply.content, 'Cloud answer.');
    expect(requests, 1);
    expect(model.prompts, isEmpty);
    expect(model.loadCalls, 0);
  });

  test('a local-only reply still returns embedded links without thumbnails',
      () async {
    final model = FakeLocalChatModel();

    final engine = ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

    final reply = await engine.reply(
      text: 'video',
      results: [shot(ocrText: 'https://youtu.be/abc123')],
      localOnly: true,
    );

    expect(reply.relatedLinks, hasLength(1));
    expect(reply.relatedLinks.single['url'], 'https://youtu.be/abc123');
    expect(reply.relatedLinks.single.containsKey('thumb'), isFalse);
  });
}
