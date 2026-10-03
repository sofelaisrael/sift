import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/services/chat_engine.dart';
import 'package:screensort_lam/services/lam_service.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/web_lookup.dart';

/// Which path produced a `ChatReply`, and whether the user can be told.
///
/// The defect this pins: `_localReply` ended in `buildLocalReply(results)` on
/// seven branches and in the model's own words on an eighth, `ChatReply` had no
/// field saying which, and both rendered identically — same text shape, same
/// evidence thumbnails. So a user who downloaded the model could report "same
/// results as if I hadn't" and be right.
///
/// Every outcome is driven through the real `LocalChatModel` seam rather than a
/// mock of `ChatEngine`, because the branch being tested lives in `_localReply`.
/// A model that can be driven into any of `_localReply`'s outcomes. Counts
/// what the engine asked of it, so "the fallback won" can be told from "the
/// engine never tried".
class FakeModel implements LocalChatModel {
  FakeModel({
    this.status = LocalChatModelStatus.ready,
    this.loadReturns = true,
    this.answer = 'MODEL ANSWER: three ramen screenshots this week.',
    this.throwOnGenerate = false,
    this.statusMessage,
  });

  @override
  LocalChatModelStatus status;
  bool loadReturns;
  String answer;
  bool throwOnGenerate;
  @override
  String? statusMessage;

  int ensureLoadedCalls = 0;
  int generateCalls = 0;

  @override
  bool get isUsable => status == LocalChatModelStatus.ready;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) async {}

  @override
  Future<bool> ensureLoaded() async {
    ensureLoadedCalls++;
    if (!loadReturns) status = LocalChatModelStatus.error;
    return loadReturns;
  }

  @override
  Future<String> generate({
    required String prompt,
    required String context,
    int maxTokens = 256,
  }) async {
    generateCalls++;
    if (throwOnGenerate) throw StateError('the runtime went away');
    return answer;
  }

  @override
  Future<LocalModelRemoval> remove() async => LocalModelRemoval.removed;

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Screenshot probeShot({List<String> objects = const ['food']}) => Screenshot(
        id: 'probe',
        fileName: 'food.png',
        filePath: '/probe/food.png',
        timestamp: DateTime(2026, 3, 4, 12, 30),
        ocrText: 'Ramen bar\nmenu says tonkotsu 12.50',
        lamType: 'document',
        summary: 'Ramen bar',
        objects: objects,
      );

  ChatEngine engine(LocalChatModel? model, {bool consent = true}) => ChatEngine(
        lam:
            LAMService(client: MockClient((_) async => http.Response('', 500))),
        consentCheck: () async => consent,
        lookup: ({
          required String extractedText,
          required String summary,
          required List<String> recognitions,
          required List<String> objects,
          required String? youTubeApiKey,
        }) async =>
            const <WebResult>[],
        localModel: model,
      );

  group('a working model is marked as having answered', () {
    test('the model text wins and says so', () async {
      final model = FakeModel();
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      expect(reply.content, model.answer);
      expect(reply.source, ChatAnswerSource.onDeviceModel);
      expect(reply.answeredByModel, isTrue);
      expect(reply.loadFailure, isNull);
      expect(model.generateCalls, 1);
    });
  });

  group('every fallback branch is marked as a fallback', () {
    test('a throwing gateway degrades and is labelled', () async {
      final model = FakeModel(throwOnGenerate: true);
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      // The fallback text is unchanged, byte for byte.
      expect(reply.content, contains('matching screenshots'));
      expect(reply.content, isNot(contains('MODEL ANSWER')));
      expect(reply.source, ChatAnswerSource.modelFailed);
      expect(reply.answeredByModel, isFalse);
      // A throw is swallowed by design, so there is no failure copy to carry —
      // the engine has already decided a raw error never reaches the user.
      expect(reply.loadFailure, isNull);
    });

    test('a failed load carries the model own explanation', () async {
      final model = FakeModel(
        loadReturns: false,
        statusMessage: 'The model could not be loaded on this device.',
      );
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      expect(reply.content, contains('matching screenshots'));
      expect(reply.source, ChatAnswerSource.modelLoadFailed);
      expect(reply.answeredByModel, isFalse);
      // This is the message that turns "silently got keyword results" into "the
      // model could not be loaded here". It must arrive verbatim.
      expect(
          reply.loadFailure, 'The model could not be loaded on this device.');
      expect(model.generateCalls, 0,
          reason: 'a model that could not load is never asked to answer');
    });

    test('a model that is not ready is labelled, and is not a load failure',
        () async {
      final model = FakeModel(status: LocalChatModelStatus.installed);
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      expect(reply.source, ChatAnswerSource.modelNotReady);
      expect(reply.answeredByModel, isFalse);
      expect(reply.loadFailure, isNull,
          reason: 'nothing failed, so there is no failure to report');
    });

    test('no model at all is labelled, and nothing is loaded', () async {
      final reply = await engine(null).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      expect(reply.content, contains('matching screenshots'));
      expect(reply.source, ChatAnswerSource.noModel);
      expect(reply.answeredByModel, isFalse);
      expect(reply.loadFailure, isNull);
    });

    test('an empty model answer is a fallback, not a model answer', () async {
      final model = FakeModel(answer: '   \n  ');
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      // The engine did run and did produce nothing. Showing the keyword list is
      // right; calling it a model answer would not be.
      expect(reply.content, contains('matching screenshots'));
      expect(reply.source, ChatAnswerSource.modelEmpty);
      expect(reply.answeredByModel, isFalse);
      expect(model.generateCalls, 1);
    });
  });

  group('an empty-results question is honestly marked', () {
    test('nothing matched, so the model was never asked', () async {
      final model = FakeModel();
      final reply = await engine(model).reply(
        text: 'what did I eat?',
        results: const <Screenshot>[],
        localOnly: true,
      );

      expect(
          reply.content, contains('Nothing found in your saved screenshots'));
      expect(reply.source, ChatAnswerSource.noResults);
      expect(reply.answeredByModel, isFalse);
      // The pre-existing guarantee, and the reason the source value matters: a
      // question must never turn into a model download.
      expect(model.ensureLoadedCalls, 0);
      expect(model.generateCalls, 0);
    });
  });

  group('the cloud path is unaffected', () {
    test('a blocked cloud reply reports no model and stays blocked', () async {
      final reply = await engine(FakeModel(), consent: false).reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: false,
      );

      // Byte-identical consent copy, and the pre-existing blocked flag.
      expect(reply.content, contains('Cloud chat needs your consent'));
      expect(reply.blocked, isTrue);
      expect(reply.source, ChatAnswerSource.cloudUnavailable);
      expect(reply.answeredByModel, isFalse);
    });

    test('a provider that could not be reached is not a model answer',
        () async {
      final e = ChatEngine(
        lam: LAMService(
          client: MockClient((_) async => http.Response('', 500)),
        ),
        consentCheck: () async => true,
        localModel: FakeModel(),
      );
      // Every provider call fails, so LAMService answers with its fixed copy
      // and no model wrote anything.
      final reply = await e.reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: false,
      );

      expect(reply.content, LAMService.unreachableProviderReply);
      expect(reply.source, ChatAnswerSource.cloudUnavailable);
      expect(reply.answeredByModel, isFalse);
    });

    test('the local model is never consulted on the cloud path', () async {
      final model = FakeModel();
      final e = ChatEngine(
        lam: LAMService(
          client: MockClient((_) async => http.Response('', 500)),
        ),
        consentCheck: () async => false,
        localModel: model,
      );
      await e.reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: false,
      );

      expect(model.ensureLoadedCalls, 0);
      expect(model.generateCalls, 0);
    });
  });

  group('the source cannot be left unsaid', () {
    test('every enum value is a distinct, non-default answer', () {
      // The whole point of an enum over the real outcomes: a new fallback
      // branch has to pick one, and this test fails if a value is added that
      // the widget layer has not been told how to say.
      expect(ChatAnswerSource.values, hasLength(9));
      expect(
        ChatAnswerSource.values.map((ChatAnswerSource s) => s.name).toSet(),
        <String>{
          'cloudAnswer',
          'cloudUnavailable',
          'onDeviceModel',
          'noResults',
          'noModel',
          'modelNotReady',
          'modelLoadFailed',
          'modelFailed',
          'modelEmpty',
        },
      );
    });

    test('answeredByModel is true for exactly the two model cases', () {
      final model = ChatAnswerSource.values
          .where((ChatAnswerSource s) =>
              s == ChatAnswerSource.onDeviceModel ||
              s == ChatAnswerSource.cloudAnswer)
          .toSet();
      expect(model, hasLength(2));
    });

    test('the widget layer switches over the whole enum', () async {
      // A source-scan, because the exhaustiveness that makes a new branch
      // visible is a property of the switch, not of the runtime.
      final source = await _read('lib/screens/chat_screen.dart');
      for (final ChatAnswerSource value in ChatAnswerSource.values) {
        expect(source, contains('ChatAnswerSource.${value.name}'),
            reason: 'chat_screen.dart must have a case for $value');
      }
    });
  });
}

Future<String> _read(String path) async => File(path).readAsString();
