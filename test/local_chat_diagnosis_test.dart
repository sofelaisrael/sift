import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/chat_engine.dart';
import 'package:screensort_lam/services/lam_service.dart';
import 'package:screensort_lam/services/litert_local_chat_model.dart';
import 'package:screensort_lam/services/local_chat_model.dart';
import 'package:screensort_lam/services/ocr_service.dart';
import 'package:screensort_lam/services/web_lookup.dart';

// MEASUREMENT ONLY. This file asserts the claims a source-reading diagnosis of
// "the on-device chat model does nothing" made, and it is deliberately written
// so a refuted claim FAILS rather than being quietly reworded to fit the code.
//
// Two deliberate choices, both about not faking the thing under test:
//
//  * The real `LiteRtLocalChatModel` is exercised through a fake `LiteRtGateway`
//    seam. The fake stands in for the native LiteRT-LM runtime only; every
//    piece of SIFT logic under test (status machine, `_loadFailed`, the load
//    call, the system instruction, prompt composition) is the real code.
//  * Claims 6 and 7 seed through `ScreenshotProvider.addFromBulkIngest`, the
//    production write path, so `summary`, `description` and the OCR handling are
//    derived by production rather than hand-written. A hand-built `Screenshot`
//    here would measure the test author, not the app.
//
// Claims 1-5 use a hand-built `Screenshot` on purpose: they are about the load
// and reply control flow, where the screenshot's content is irrelevant beyond
// being non-empty, and keeping Hive out of them isolates each failure mode.

const String kModelAnswer = 'MODEL ANSWER: three ramen screenshots this week.';

/// The on-device model's distinctive answer. Must not be reachable by the
/// fallback, or "the model's text won" cannot be told from "the fallback won".
const String kFallbackMarker = 'matching screenshots';

/// A stand-in for the LiteRT-LM runtime that counts what SIFT asked it and
/// captures what it was actually handed. It can be driven into any outcome, so
/// "the engine would have succeeded the second time" is expressible.
class DiagnosticGateway implements LiteRtGateway {
  DiagnosticGateway({this.installed = false, this.answer = kModelAnswer});

  /// Whether the runtime's model manager already holds the model on disk.
  bool installed;

  /// Thrown by `load` instead of completing, while set.
  Object? loadError;

  /// What the fake runtime answers.
  String answer;

  int isInstalledCalls = 0;
  int installCalls = 0;

  /// The claim-1/2/3/4/5 counter: how many times SIFT created the engine.
  int loadCalls = 0;

  int openSessionCalls = 0;
  int askCalls = 0;
  int sessionCloses = 0;
  int engineCloses = 0;

  final List<int> contextTokens = <int>[];
  final List<int> maxOutputTokens = <int>[];
  final List<String> systemInstructions = <String>[];
  final List<String> userTurns = <String>[];

  @override
  Future<bool> isInstalled(String modelFileName) async {
    isInstalledCalls++;
    return installed;
  }

  @override
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  }) async {
    installCalls++;
    onProgress(0);
    onProgress(100);
    installed = true;
  }

  @override
  Future<void> uninstall(String modelFileName) async {
    installed = false;
  }

  @override
  Future<void> clearActiveIdentity() async {}

  @override
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  }) async {
    loadCalls++;
    this.contextTokens.add(contextTokens);
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  }) async {
    openSessionCalls++;
    this.maxOutputTokens.add(maxOutputTokens);
    systemInstructions.add(systemInstruction);
    return _DiagnosticSession(gateway: this);
  }

  @override
  Future<void> close() async {
    engineCloses++;
  }
}

class _DiagnosticSession implements LiteRtSession {
  _DiagnosticSession({required this.gateway});

  final DiagnosticGateway gateway;

  @override
  Future<String> ask(String userText) async {
    gateway.askCalls++;
    gateway.userTurns.add(userText);
    return gateway.answer;
  }

  @override
  Future<void> close() async {
    gateway.sessionCloses++;
  }
}

/// One hand-built record. Only claims 1-5 use it, and only its emptiness
/// matters: they measure the load/reply control flow, not the content.
Screenshot probeShot() => Screenshot(
      id: 'probe',
      fileName: 'food.png',
      filePath: '/probe/food.png',
      timestamp: DateTime(2026, 3, 4, 12, 30),
      ocrText: 'Ramen bar\nmenu says tonkotsu 12.50',
      lamType: 'document',
      summary: 'Ramen bar',
      objects: const ['food'],
    );

http.Client noNetworkClient() =>
    MockClient((request) async => fail('local-only chat must make no request, '
        'saw ${request.url}'));

Future<bool> noConsent() async =>
    fail('local-only chat must not ask for cloud consent');

Future<List<WebResult>> noLookup({
  required String extractedText,
  required String summary,
  required List<String> recognitions,
  required List<String> objects,
  required String? youTubeApiKey,
}) async =>
    fail('local-only chat must not run a source lookup');

ChatEngine localEngine(LocalChatModel? model) => ChatEngine(
      lam: LAMService(client: noNetworkClient()),
      consentCheck: noConsent,
      lookup: noLookup,
      localModel: model,
    );

/// A single long OCR line, no newlines, so production's `summary` derivation
/// (first non-empty line, capped at 80 chars) yields exactly the first 80 chars
/// of `ocrText` and the claim about `Summary:`/`Text:` duplication becomes
/// testable rather than assumed.
String longOcrLine(int i) {
  final buffer = StringBuffer('Receipt $i: ');
  var item = 1;
  while (buffer.length < 900) {
    buffer.write('item $item pad thai lime chilli total 12.50; ');
    item++;
  }
  return buffer.toString().substring(0, 900);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NOTE: SharedPreferences is deliberately NOT mocked anywhere in this file.
  // The control test below proves the unmocked plugin really does throw here,
  // which turns "the local-only path touches no prefs" from a claim into an
  // observation: a prefs read would raise MissingPluginException, and for
  // claims 2/4 that exception would be swallowed by `_localReply`'s catch and
  // show up as a fallback, so the assertions would fail.

  group('CLAIM 0 (control): the local-only path reaches no plugin', () {
    test('SharedPreferences is genuinely unavailable in this test', () async {
      await expectLater(
        SharedPreferences.getInstance(),
        throwsA(isA<MissingPluginException>()),
      );
      debugPrint('CONTROL: SharedPreferences.getInstance() throws '
          'MissingPluginException -> no prefs are mocked anywhere in this file');
    });
  });

  group('CLAIM 1: download() installs but does not load the engine', () {
    test('status installed, isUsable false, loadCalls 0', () async {
      final gateway = DiagnosticGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);

      await model.download();

      debugPrint('CLAIM 1 status after download(): ${model.status}');
      debugPrint('CLAIM 1 isUsable after download(): ${model.isUsable}');
      debugPrint('CLAIM 1 gateway.loadCalls after download(): '
          '${gateway.loadCalls}');
      debugPrint('CLAIM 1 gateway.installCalls: ${gateway.installCalls}');
      debugPrint('CLAIM 1 gateway.openSessionCalls: '
          '${gateway.openSessionCalls}');
      debugPrint('CLAIM 1 model.isInstalled(): ${await model.isInstalled()}');
      debugPrint('CLAIM 1 statusMessage: ${model.statusMessage}');

      expect(model.status, LocalChatModelStatus.installed);
      expect(model.isUsable, isFalse);
      expect(gateway.loadCalls, 0);
      expect(gateway.openSessionCalls, 0);
      expect(gateway.installCalls, 1);
      expect(await model.isInstalled(), isTrue);
    });
  });

  group('CLAIM 2: a working fake gateway answers the local-only question', () {
    test('model text wins, loadCalls 1, status ready, 2048 ctx', () async {
      final gateway = DiagnosticGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      expect(model.status, LocalChatModelStatus.installed);

      final engine = localEngine(model);
      final reply = await engine.reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      debugPrint('CLAIM 2 reply.content: ${reply.content}');
      debugPrint('CLAIM 2 reply.source: ${reply.source}');
      debugPrint('CLAIM 2 reply.answeredByModel: ${reply.answeredByModel}');
      debugPrint('CLAIM 2 reply.blocked: ${reply.blocked}');
      debugPrint('CLAIM 2 relatedLinks: ${reply.relatedLinks}');
      debugPrint('CLAIM 2 gateway.loadCalls: ${gateway.loadCalls}');
      debugPrint('CLAIM 2 gateway.contextTokens: ${gateway.contextTokens}');
      debugPrint('CLAIM 2 gateway.maxOutputTokens: ${gateway.maxOutputTokens}');
      debugPrint('CLAIM 2 model.status after reply: ${model.status}');
      debugPrint('CLAIM 2 model.isUsable after reply: ${model.isUsable}');
      debugPrint(
          'CLAIM 2 gateway.openSessionCalls: ${gateway.openSessionCalls}');
      debugPrint('CLAIM 2 gateway.askCalls: ${gateway.askCalls}');
      debugPrint('CLAIM 2 gateway.sessionCloses: ${gateway.sessionCloses}');
      debugPrint('CLAIM 2 system instruction sent: '
          '${gateway.systemInstructions}');
      debugPrint('CLAIM 2 system instruction == spec constant: '
          '${gateway.systemInstructions.single == LiteRtLocalChatModel.systemInstruction}');
      debugPrint('CLAIM 2 user turn: ${gateway.userTurns.single}');

      // The model's own text is the answer, not the fallback.
      expect(reply.content, kModelAnswer);
      expect(reply.content, isNot(contains(kFallbackMarker)));
      expect(reply.blocked, isFalse);
      expect(reply.relatedLinks, isEmpty);
      // And the reply now says so, which is the whole of the visibility fix.
      expect(reply.source, ChatAnswerSource.onDeviceModel);
      expect(reply.answeredByModel, isTrue);
      expect(reply.loadFailure, isNull);

      // Exactly one engine creation for one question: `ensureLoaded` is called
      // twice (once by the engine, once by `generate`) but the second call is a
      // cached true.
      expect(gateway.loadCalls, 1);
      expect(gateway.contextTokens, <int>[2048]);
      expect(gateway.openSessionCalls, 1);
      expect(gateway.askCalls, 1);
      expect(gateway.sessionCloses, 1);
      expect(model.status, LocalChatModelStatus.ready);
      expect(model.isUsable, isTrue);

      // The grounding contract arrives as the runtime system instruction.
      expect(gateway.systemInstructions, <String>[
        LiteRtLocalChatModel.systemInstruction,
      ]);
      expect(gateway.systemInstructions.single,
          contains('Answer ONLY from the CONTEXT'));
      expect(gateway.systemInstructions.single,
          contains('Never invent a screenshot'));

      final userTurn = gateway.userTurns.single;
      expect(userTurn, startsWith('QUESTION: what did I eat?'));
      expect(userTurn, contains('CONTEXT:'));
      // The rules ride with the runtime's template, not duplicated in the turn.
      expect(userTurn, isNot(contains('Never invent a screenshot')));
    });
  });

  group('CLAIM 3: a load that throws degrades to the fallback', () {
    test('fallback returned, no chat session ever opened', () async {
      final gateway = DiagnosticGateway()
        ..loadError = StateError('native engine could not be created');
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();

      final engine = localEngine(model);
      final reply = await engine.reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );

      debugPrint('CLAIM 3 reply.content: ${reply.content}');
      debugPrint('CLAIM 3 reply.source: ${reply.source}');
      debugPrint('CLAIM 3 reply.answeredByModel: ${reply.answeredByModel}');
      debugPrint('CLAIM 3 reply.loadFailure: ${reply.loadFailure}');
      debugPrint('CLAIM 3 gateway.loadCalls: ${gateway.loadCalls}');
      debugPrint(
          'CLAIM 3 gateway.openSessionCalls: ${gateway.openSessionCalls}');
      debugPrint('CLAIM 3 gateway.askCalls: ${gateway.askCalls}');
      debugPrint('CLAIM 3 model.status: ${model.status}');
      debugPrint('CLAIM 3 model.statusMessage: ${model.statusMessage}');
      debugPrint('CLAIM 3 model.isUsable: ${model.isUsable}');

      expect(reply.content, contains(kFallbackMarker));
      expect(reply.content, isNot(contains('MODEL ANSWER')));
      expect(gateway.loadCalls, 1);
      expect(gateway.openSessionCalls, 0);
      expect(gateway.askCalls, 0);
      expect(model.status, LocalChatModelStatus.error);
      expect(model.isUsable, isFalse);

      // The user is told which of the two answered, and why the other one did
      // not. Before this, both paths rendered identically.
      expect(reply.source, ChatAnswerSource.modelLoadFailed);
      expect(reply.answeredByModel, isFalse);
      expect(reply.loadFailure, isNotNull);
      expect(reply.loadFailure, model.statusMessage);
      expect(reply.loadFailure, isNot(contains('native engine')));
      expect(reply.loadFailure, isNot(contains('StateError')));
    });
  });

  group('CLAIM 4: _loadFailed is sticky for the rest of the session', () {
    test('a runtime that would now succeed is never retried', () async {
      final gateway = DiagnosticGateway()
        ..loadError = StateError('transient native failure');
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      final engine = localEngine(model);

      final first = await engine.reply(
        text: 'what did I eat?',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );
      debugPrint('CLAIM 4 question 1 content: ${first.content}');
      debugPrint('CLAIM 4 question 1 source: ${first.source}');
      debugPrint('CLAIM 4 question 1 status: ${model.status}');
      debugPrint('CLAIM 4 question 1 loadCalls: ${gateway.loadCalls}');

      // The failure clears: the runtime is now perfectly willing to load. Only
      // the flag SIFT kept should decide whether it is asked again.
      gateway.loadError = null;

      final second = await engine.reply(
        text: 'try again please',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );
      debugPrint('CLAIM 4 question 2 content: ${second.content}');
      debugPrint('CLAIM 4 question 2 source: ${second.source}');
      debugPrint('CLAIM 4 question 2 status: ${model.status}');
      debugPrint('CLAIM 4 question 2 statusMessage: ${model.statusMessage}');
      debugPrint('CLAIM 4 total loadCalls after 2 questions: '
          '${gateway.loadCalls}');
      debugPrint('CLAIM 4 total openSessionCalls: ${gateway.openSessionCalls}');
      debugPrint('CLAIM 4 total engineCloses: ${gateway.engineCloses}');

      expect(first.content, contains(kFallbackMarker));
      expect(second.content, contains(kFallbackMarker));
      expect(second.content, isNot(contains('MODEL ANSWER')));
      expect(first.source, ChatAnswerSource.modelLoadFailed);
      expect(second.source, ChatAnswerSource.modelLoadFailed);
      // The engine is never recreated: one attempt, two questions.
      expect(gateway.loadCalls, 1);
      expect(gateway.openSessionCalls, 0);
      expect(gateway.engineCloses, 0);
      expect(model.status, LocalChatModelStatus.error);

      // Bounded, though. The claim says "forever"; measure the escape hatches
      // rather than assuming them. A second `download()` (which is a no-op for
      // an already-installed model) clears the flag.
      await model.download();
      debugPrint('CLAIM 4 status after a second download(): ${model.status}');
      final third = await engine.reply(
        text: 'and once more',
        results: <Screenshot>[probeShot()],
        localOnly: true,
      );
      debugPrint('CLAIM 4 question 3 content: ${third.content}');
      debugPrint('CLAIM 4 question 3 source: ${third.source}');
      debugPrint('CLAIM 4 loadCalls after the flag was cleared: '
          '${gateway.loadCalls}');
      expect(third.content, kModelAnswer);
      expect(third.source, ChatAnswerSource.onDeviceModel);
      expect(gateway.loadCalls, 2);
    });
  });

  group('CLAIM 5: empty results never probe the model', () {
    test('fallback returned, ensureLoaded never called', () async {
      final gateway = DiagnosticGateway();
      final model = LiteRtLocalChatModel(gateway: gateway);
      await model.download();
      final engine = localEngine(model);

      final reply = await engine.reply(
        text: 'what did I eat?',
        results: const <Screenshot>[],
        localOnly: true,
      );

      debugPrint('CLAIM 5 reply.content: ${reply.content}');
      debugPrint('CLAIM 5 reply.source: ${reply.source}');
      debugPrint('CLAIM 5 gateway.loadCalls: ${gateway.loadCalls}');
      debugPrint(
          'CLAIM 5 gateway.openSessionCalls: ${gateway.openSessionCalls}');
      debugPrint('CLAIM 5 gateway.installCalls: ${gateway.installCalls}');
      debugPrint('CLAIM 5 model.status: ${model.status}');

      expect(reply.content, engine.buildLocalReply(const <Screenshot>[]));
      expect(reply.content, contains('Nothing found in your saved'));
      expect(gateway.loadCalls, 0);
      expect(gateway.openSessionCalls, 0);
      // A question must never become a 614 MB transfer.
      expect(gateway.installCalls, 1, reason: 'only the setup download above');
      // "Nothing found" is not a model answer, and it is not a model failure
      // either. The two are different facts and the screen now says which.
      expect(reply.source, ChatAnswerSource.noResults);
      expect(reply.answeredByModel, isFalse);
      expect(reply.loadFailure, isNull);
    });
  });

  group('CLAIM 6: what the model actually receives', () {
    test('12 long-OCR screenshots through the 4000-char cap', () async {
      final provider = await openSeededProvider();
      for (var i = 0; i < 12; i++) {
        final id = await provider.addFromBulkIngest(
          path: '/shots/$i.png',
          capturedAt: DateTime(2026, 1, i + 1),
          ocrText: longOcrLine(i),
        );
        expect(id, isNotNull);
      }

      final results = provider.screenshots;
      expect(results, hasLength(12));
      debugPrint('CLAIM 6 records seeded: ${results.length}');
      debugPrint('CLAIM 6 description values across every record: '
          '${results.map((Screenshot s) => s.description).toSet()}');
      debugPrint('CLAIM 6 ocrText length per record: '
          '${results.first.ocrText!.length}');
      debugPrint('CLAIM 6 summary production derived: '
          '"${results.first.summary}" (${results.first.summary!.length} chars)');

      final engine = localEngine(null);
      final context = engine.buildContextText(results);

      // One block per record that survived the cap.
      final blocks =
          RegExp(r'^\[\d+\]$', multiLine: true).allMatches(context).length;
      // One entry's worth of characters, measured from the real builder.
      final entryChars =
          engine.buildContextText(<Screenshot>[results.first]).length;

      debugPrint('CLAIM 6 _maxTotalContext: 4000');
      debugPrint('CLAIM 6 characters per rendered block: $entryChars');
      debugPrint('CLAIM 6 4000 / $entryChars = '
          '${4000 / entryChars} -> ${4000 ~/ entryChars} whole blocks fit');
      debugPrint('CLAIM 6 MEASURED BLOCKS SURVIVING: $blocks of '
          '${results.length}');
      debugPrint(
          'CLAIM 6 total characters sent to the model: ${context.length}');
      debugPrint('CLAIM 6 last block index present: '
          '${RegExp(r'^\[\d+\]$', multiLine: true).allMatches(context).last.group(0)}');
      debugPrint('CLAIM 6 context contains "Description:": '
          '${context.contains('Description:')}');

      // The cap, not something else, is what limits the count: the surviving
      // blocks fit, and one more would not.
      expect(blocks, lessThan(results.length),
          reason: 'the cap must actually drop records');
      expect(blocks * entryChars, lessThanOrEqualTo(4000));
      expect((blocks + 1) * entryChars, greaterThan(4000));

      // These records carry no visual labels -- `addFromBulkIngest` is handed
      // none -- and the derived description says only what the labels say, so
      // there is genuinely nothing to describe and the field stays empty. That
      // is the clean empty the derivation promises, not a gap in it: the same
      // records DO carry a description once any label is present, which
      // `description_derivation_test.dart` measures through the same write path.
      expect(results.every((Screenshot s) => s.description == null), isTrue);
      expect(context, isNot(contains('Description:')));

      // Summary and Text duplicate: the summary is the first 80 chars of the
      // OCR, and the Text line starts with the very same 80 chars. This is the
      // duplication that populating `description` was meant to address, and for
      // a label-free record it is still there.
      final summaries = RegExp(r'^  Summary: (.*)$', multiLine: true)
          .allMatches(context)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      final texts = RegExp(r'^  Text: (.*)$', multiLine: true)
          .allMatches(context)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      debugPrint('CLAIM 6 Summary lines rendered: ${summaries.length}');
      debugPrint('CLAIM 6 Text lines rendered: ${texts.length}');
      debugPrint('CLAIM 6 first Summary line: "${summaries.first}"');
      debugPrint('CLAIM 6 first Text line (first 120 chars): '
          '"${texts.first.substring(0, 120)}"');
      debugPrint(
          'CLAIM 6 Text line length incl. ellipsis: ${texts.first.length}');

      expect(summaries, hasLength(blocks));
      expect(texts, hasLength(blocks));
      for (var i = 0; i < blocks; i++) {
        expect(summaries[i], results[i].ocrText!.substring(0, 80),
            reason: 'block $i summary is the OCR prefix, not new content');
        expect(texts[i], startsWith(summaries[i]),
            reason: 'block $i repeats its summary inside the OCR text');
      }
    });
  });

  group('CLAIM 7: a question is scored on its content words, not its grammar',
      () {
    test(
        'the function words are not terms, and the content words reach the index',
        () async {
      const sentence = 'show me my food screenshots';
      const words = <String>['show', 'me', 'my', 'food', 'screenshots'];
      const longSentence =
          'can you please show me my food screenshots from last week';

      final provider = await openSeededProvider();
      // One record per candidate word, on the second line so the word reaches
      // `ocrText` and not the `summary` slice. The neutral header shares no
      // prefix with any candidate.
      for (var i = 0; i < words.length; i++) {
        await provider.addFromBulkIngest(
          path: '/probe/${words[i]}.png',
          capturedAt: DateTime(2026, 2, i + 1),
          ocrText: 'Header line\n${words[i]}',
        );
      }
      // A record reachable ONLY through the stop word 'me' by prefix
      // ('me' -> 'menu'). This is the real-world false positive.
      await provider.addFromBulkIngest(
        path: '/probe/menu.png',
        capturedAt: DateTime(2026, 2, 10),
        ocrText: 'Header line\nmenu item',
      );

      // Measure the term list the only way a private method can be measured: a
      // word is a live query term exactly when querying it reaches the record
      // that carries it.
      //
      // Probed in company with `zzzq`, a non-stop word nothing in this corpus
      // contains. Querying a stop word on its OWN cannot measure this: the
      // all-stop-words fallback restores the unfiltered list, so `show` alone
      // still finds its record and the probe would report a term that is not
      // one. With a second word present the filtered list is non-empty, the
      // fallback stays out of it, and a dropped word genuinely reaches nothing.
      final live = <String>[];
      for (final word in words) {
        final hits = provider.search('$word zzzq', limit: 50);
        final own = hits
            .where((Screenshot s) => s.filePath == '/probe/$word.png')
            .length;
        debugPrint('CLAIM 7 search("$word zzzq") -> ${hits.length} hit(s), '
            'own record $own time(s)');
        if (own == 1) live.add(word);
      }
      debugPrint('CLAIM 7 LIVE QUERY TERMS for "$sentence": $live');
      debugPrint('CLAIM 7 term count: ${live.length} of ${words.length} words');

      // The whole question, scored on `food` and `screenshots` and nothing else.
      final all = provider.search(sentence, limit: 50);
      debugPrint('CLAIM 7 search("$sentence") -> '
          '${all.map((Screenshot s) => s.filePath).toList()}');
      debugPrint(
          'CLAIM 7 records matched by the whole question: ${all.length}');

      // The two content words survive the filter.
      expect(live, <String>['food', 'screenshots']);
      expect(all.map((Screenshot s) => s.filePath),
          containsAll(<String>['/probe/food.png', '/probe/screenshots.png']));

      // And the grammar does not drag in a screenshot with no food and no
      // screenshot in it. `me` -> `menu` was the measured false positive.
      expect(
          all.any((Screenshot s) => s.filePath == '/probe/menu.png'), isFalse,
          reason: "the term 'me' prefix-matched 'menu'");
      expect(all, hasLength(2));

      // The fallback: a query made of nothing but stop words keeps searching
      // rather than silently matching nothing, which a user cannot tell from
      // "you have no such screenshot".
      final allStopWords = provider.search('show me please', limit: 50);
      debugPrint('CLAIM 7 search("show me please") -> '
          '${allStopWords.map((Screenshot s) => s.filePath).toList()}');
      expect(allStopWords, isNotEmpty,
          reason: 'an all-stop-word query must fall back to the unfiltered '
              'terms, not match nothing');
      expect(
          allStopWords.any((Screenshot s) => s.filePath == '/probe/show.png'),
          isTrue,
          reason: 'the fallback restores the original terms');

      // `_maxQueryTerms` is 6, and filtering happens BEFORE the cap. That
      // eleven-word question used to be scored on its first six words — all
      // grammar — so `food` and `screenshots` never became terms and the answer
      // was a list of screenshots that contained none of what was asked for.
      final capped = provider.search(longSentence, limit: 50);
      debugPrint('CLAIM 7 search("$longSentence") -> '
          '${capped.map((Screenshot s) => s.filePath).toList()}');
      expect(
          capped.any((Screenshot s) => s.filePath == '/probe/food.png'), isTrue,
          reason: 'the content words reach the index; the grammar does not '
              'consume the six-term budget');
      expect(
          capped.any((Screenshot s) => s.filePath == '/probe/screenshots.png'),
          isTrue);
      expect(capped.any((Screenshot s) => s.filePath == '/probe/menu.png'),
          isFalse,
          reason: 'no stop word may reach an unrelated record');
      // Exactly the two content records. Every other record in this corpus is
      // reachable through a stop word alone, so the length is a complete
      // statement of the term list: nothing else was a term.
      expect(capped, hasLength(2));
      expect(capped.map((Screenshot s) => s.filePath),
          <String>['/probe/food.png', '/probe/screenshots.png']);
    });
  });
}

/// A provider on a private Hive box in a temp directory, torn down with the
/// test. Nothing here mocks SharedPreferences or the network.
Future<ScreenshotProvider> openSeededProvider() async {
  final dir = await Directory.systemTemp.createTemp('sift_chat_diag_');
  Hive.init(dir.path);
  await Hive.openBox('screenshots');
  addTearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
  return ScreenshotProvider(ocr: OCRService(extractOverride: (_) async => ''));
}
