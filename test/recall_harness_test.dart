import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recall_fixture_corpus.dart';
import 'support/recall_harness.dart';

/// Tests for the recall *harness*, not for the index.
///
/// Everything here asserts the tool's own correctness: that the filters do what
/// they claim, that a probe finds the record it came from, that the artifacts
/// land and parse, and that the fingerprints are stable.
///
/// **No assertion in this file is about the quality of the index.** There is
/// deliberately no `recallAt10 >= 0.9`. Phase 0 of `sift-product-plan.md`
/// exists because the weights are unmeasured; a test that goes red when recall
/// is mediocre would push whoever runs it to either tune the index or delete
/// the baseline, and both destroy the point. The harness has to be able to
/// report a bad number without failing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('recall_harness_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Records in the fixture that carry no OCR, no tags and no labels, so their
  /// only stored `summary` is the display-only 'No text found' placeholder.
  const Set<String> contentlessFixtureRecords = <String>{
    'Screenshot_20260115_140000.png',
    'Screenshot_20260115_140100.png',
    'Screenshot_20260115_140200.png',
    'Screenshot_20260115_140300.png',
  };

  const RecallCorpus fixtureCorpus = RecallCorpus(
    label: 'recall_fixture_corpus.dart',
    records: recallFixtureCorpus,
    mode: RecallCorpusMode.fixture,
  );

  /// Run the harness over [corpus], collecting the printed lines instead of
  /// flooding the test log, and writing its JSON somewhere disposable so the
  /// test never depends on (or clobbers) `build/recall_report.json`.
  Future<_Run> run(
    RecallCorpus corpus, {
    int discriminativenessCutoff = defaultDiscriminativenessCutoff,
    String? semanticQueriesPath,
    String jsonName = 'recall_report.json',
  }) async {
    final List<String> lines = <String>[];
    final File json = File('${tempDir.path}/$jsonName');
    final RecallReport report = await RecallHarness(
      corpus: corpus,
      discriminativenessCutoff: discriminativenessCutoff,
      semanticQueriesPath:
          semanticQueriesPath ?? '${tempDir.path}/absent_queries.jsonl',
      reportPath: json.path,
      emit: lines.add,
    ).run();
    return _Run(report, lines.join('\n'), json);
  }

  Future<_Run> runFixture({
    int discriminativenessCutoff = defaultDiscriminativenessCutoff,
    String? semanticQueriesPath,
    String jsonName = 'recall_report.json',
  }) =>
      run(
        fixtureCorpus,
        discriminativenessCutoff: discriminativenessCutoff,
        semanticQueriesPath: semanticQueriesPath,
        jsonName: jsonName,
      );

  group('the discriminativeness filter', () {
    test('a token held by every record cannot survive as a probe', () {
      // Four records sharing one word. Above the cutoff of 3, so the word
      // cannot identify any of them -- measuring it would report the corpus's
      // vocabulary rather than the index.
      const List<RecallCorpusRecord> shared = <RecallCorpusRecord>[
        RecallCorpusRecord(fileName: 'a.png', ocrText: 'commonword alpha'),
        RecallCorpusRecord(fileName: 'b.png', ocrText: 'commonword bravo'),
        RecallCorpusRecord(fileName: 'c.png', ocrText: 'commonword charlie'),
        RecallCorpusRecord(fileName: 'd.png', ocrText: 'commonword delta'),
      ];
      final RecallProbeDerivation view =
          RecallHarness(corpus: const RecallCorpus(label: 's', records: shared))
              .deriveProbes();

      expect(
        view.probes.map((RecallProbe p) => p.token),
        isNot(contains('commonword')),
        reason: 'a word on every record is a constant, not a probe',
      );
      expect(
        view.probes.map((RecallProbe p) => p.token),
        containsAll(<String>['alpha', 'bravo', 'charlie', 'delta']),
      );
      expect(view.droppedNonDiscriminative, 1);
    });

    test('a token at the cutoff is kept and above it is dropped', () {
      List<RecallCorpusRecord> corpus(int n) => <RecallCorpusRecord>[
            for (int i = 0; i < n; i++)
              RecallCorpusRecord(fileName: 'f$i.png', ocrText: 'held unique$i'),
          ];

      final RecallProbeDerivation atCutoff =
          RecallHarness(corpus: RecallCorpus(label: 'at', records: corpus(3)))
              .deriveProbes();
      final RecallProbeDerivation aboveCutoff = RecallHarness(
              corpus: RecallCorpus(label: 'above', records: corpus(4)))
          .deriveProbes();

      expect(atCutoff.probes.map((RecallProbe p) => p.token), contains('held'));
      expect(atCutoff.droppedNonDiscriminative, 0);
      expect(
        aboveCutoff.probes.map((RecallProbe p) => p.token),
        isNot(contains('held')),
      );
      expect(aboveCutoff.droppedNonDiscriminative, 1);
    });

    test('a token shared by two owners yields one probe per owner', () {
      const List<RecallCorpusRecord> shared = <RecallCorpusRecord>[
        RecallCorpusRecord(fileName: 'puppy.png', objects: <String>['dog']),
        RecallCorpusRecord(fileName: 'beach.png', objects: <String>['dog']),
      ];
      final RecallProbeDerivation view =
          RecallHarness(corpus: const RecallCorpus(label: 's', records: shared))
              .deriveProbes();

      final List<RecallProbe> dog =
          view.probes.where((RecallProbe p) => p.token == 'dog').toList();
      expect(dog, hasLength(2),
          reason: 'both owners are measured separately; averaging them away '
              'would credit the sort for a coin flip');
      expect(
        dog.map((RecallProbe p) => p.ownerFileName).toSet(),
        <String>{'puppy.png', 'beach.png'},
      );
      expect(dog.every((RecallProbe p) => p.ownerCount == 2), isTrue,
          reason: 'ownerCount is the ceiling on recall@1 for this probe');
      expect(
          dog.every((RecallProbe p) => p.matchCount >= p.ownerCount), isTrue);
    });

    test('a one-character non-CJK token is never probed', () {
      // `search()` rejects any query under 2 chars unless it holds CJK, so
      // probing 'x' returns [] by construction. Scoring that as a miss would
      // measure the harness's own bad probe rather than the index.
      final RecallProbeDerivation view = RecallHarness(
        corpus: const RecallCorpus(
          label: 'short',
          records: <RecallCorpusRecord>[
            RecallCorpusRecord(fileName: 'a.png', ocrText: 'x zebra'),
          ],
        ),
      ).deriveProbes();

      expect(view.probes.map((RecallProbe p) => p.token), isNot(contains('x')));
      expect(view.droppedUnqueryable, greaterThanOrEqualTo(1));
    });
  });

  group('a probe finds the record it came from', () {
    test('a word on the first line is returned for its own record', () async {
      final _Run r = await runFixture();
      final RecallObservation coffee = r.observations.firstWhere(
        (RecallObservation o) =>
            o.expectations.single == 'Screenshot_20260112_084512.png' &&
            o.query == 'bottle',
        orElse: () => throw StateError('no probe for the coffee receipt'),
      );
      expect(
          coffee.returnedFileNames, contains('Screenshot_20260112_084512.png'));
      expect(coffee.bestRank, isNotNull);
    });

    test('a label-only record is reachable through objects', () async {
      final _Run r = await runFixture();
      final Iterable<RecallObservation> hits = r.observations.where(
        (RecallObservation o) =>
            o.expectations.single == 'skyline_sunset.png' &&
            o.query == 'sunset',
      );
      expect(hits, isNotEmpty);
      expect(hits.first.bestRank, isNotNull,
          reason: 'a screenshot with no OCR is reachable through `objects`, '
              'which is what Phase 2 is gated on');
    });

    test('a CJK run is probed whole and the tokenizer mirror holds', () async {
      final _Run r = await runFixture();
      final List<RecallObservation> menu = r.observations
          .where((RecallObservation o) =>
              o.expectations.single == 'Screenshot_20260103_101010.png')
          .toList();
      expect(menu, isNotEmpty);
      expect(menu.map((RecallObservation o) => o.query), contains('咖啡店的菜单'),
          reason: 'a CJK run is one token, so the whole phrase is the probe');
      expect(menu.every((RecallObservation o) => o.bestRank != null), isTrue,
          reason: 'the mirror tokenizer must agree with production, or these '
              'return nothing. This is where a mirror drift would surface.');
    });
  });

  group('fields that carry no content are not probed', () {
    test('the report names what it refuses to probe, and why', () async {
      final _Run r = await runFixture();
      expect(
          r.report.fieldPolicy.probed, <String>['ocrText', 'objects', 'tags']);
      for (final String field in <String>[
        'description',
        'extractedData',
        'fileName',
        'lamType',
        'recognitions',
        'searchKeywords',
        'summary',
      ]) {
        expect(r.report.fieldPolicy.skipped, contains(field));
        expect(r.report.fieldPolicy.skipped[field], isNotEmpty,
            reason: '$field must carry a reason, not just an omission');
      }
    });

    test('"never populated" is verified against the seeded records', () async {
      final _Run r = await runFixture();
      expect(r.report.fieldPolicy.neverPopulatedConfirmed, isTrue);

      // The flag only measures records seeded through addFromBulkIngest, so the
      // report has to say that rather than claiming a property of the app. A
      // reason that reads "on every locally written record" is a claim about
      // processScreenshot too, and the harness never calls it.
      for (final String field in <String>[
        'description',
        'extractedData',
        'recognitions',
        'searchKeywords',
      ]) {
        expect(
          r.report.fieldPolicy.skipped[field],
          contains('addFromBulkIngest'),
          reason: '$field must scope its "empty" claim to the write path the '
              'harness actually exercised',
        );
        expect(
          r.report.fieldPolicy.skipped[field],
          isNot(contains('locally written')),
          reason: '$field must not claim more than was measured',
        );
      }
      expect(
          r.text, contains('processScreenshot is the other local write path'));
    });

    test('the constant lamType is confirmed constant, so it cannot rank',
        () async {
      final _Run r = await runFixture();
      expect(r.report.fieldPolicy.lamTypeValues, <String>['document']);
    });

    test('the display-only placeholder is never turned into a probe', () async {
      final _Run r = await runFixture();

      // Production really did store the placeholder on the fixture's records that
      // have no OCR text, so there is something for the harness to avoid. More
      // than the four contentless records qualify: the label-only and tag-only
      // records have no OCR text either, so the app gave them the placeholder
      // as well. Only their labels and tags are searchable.
      expect(r.report.fieldPolicy.placeholderSummaryCount,
          greaterThanOrEqualTo(contentlessFixtureRecords.length));
      expect(r.report.fieldPolicy.placeholderSummaryCount, lessThan(53),
          reason: 'the placeholder must not be spread over every record, or '
              'nothing in this corpus is being read as content');

      final Set<String> probedRecords = r.observations
          .map((RecallObservation o) => o.expectations.single)
          .toSet();
      expect(
        probedRecords.intersection(contentlessFixtureRecords),
        isEmpty,
        reason: 'these records carry only the placeholder, which is '
            'display-only and indexed nowhere, so no probe can come from them',
      );

      final Set<String> probedTokens =
          r.observations.map((RecallObservation o) => o.query).toSet();
      expect(probedTokens, isNot(contains('found')),
          reason: "'found' exists in this corpus only inside the placeholder");
      expect(probedTokens, isNot(contains('no')));
    });
  });

  group('the artifacts land', () {
    test('the JSON report is written and parses', () async {
      final _Run r = await runFixture();
      expect(r.report.reportWritten, isTrue);
      expect(await r.json.exists(), isTrue);

      final Map<String, dynamic> parsed =
          jsonDecode(await r.json.readAsString()) as Map<String, dynamic>;
      expect(parsed['tool'], 'sift-recall-harness');
      expect(parsed['schemaVersion'], recallReportSchemaVersion);
      expect(parsed['mode'], 'fixture');
      expect(parsed['timestamp'], isNotEmpty);
      expect(
        parsed.keys,
        containsAll(<String>[
          'corpus',
          'indexFingerprint',
          'lexicalProbes',
          'semanticQueries',
          'warnings',
        ]),
      );
      // The two query classes are reported separately and never merged.
      expect(
        (parsed['lexicalProbes'] as Map<String, dynamic>)['metrics'],
        isNotNull,
      );
      expect(
        (parsed['semanticQueries'] as Map<String, dynamic>)['status'],
        'not supplied',
      );
    });

    test('the report is printed as text as well as written as JSON', () async {
      final _Run r = await runFixture();
      expect(r.text, contains('SIFT RECALL HARNESS'));
      expect(r.text, contains('CLASS 1'));
      expect(r.text, contains('CLASS 2'));
      expect(r.report.textReport, r.text);
    });

    test('sample size is reported, so a filtered number stays legible',
        () async {
      final _Run r = await runFixture();
      expect(r.report.probesRetained, greaterThan(0));

      // Every distinct token is accounted for: kept, unqueryable, or dropped as
      // non-discriminative. If that does not balance, a filter ran twice or a
      // token escaped one of them.
      expect(
        r.report.distinctTokensSeen,
        r.report.retainedTokens +
            r.report.droppedUnqueryable +
            r.report.droppedNonDiscriminative,
        reason: 'every distinct token is retained, unqueryable, or dropped',
      );
      expect(r.report.retainedTokens, greaterThan(0));
      // One observation per (token, owner), so a multi-owner token adds
      // observations without adding a token. Observations therefore sit at or
      // above the retained-token count, and never above it plus the owner
      // surplus those tokens contribute.
      expect(r.report.probesRetained,
          greaterThanOrEqualTo(r.report.retainedTokens));
      expect(
        r.report.probesRetained - r.report.retainedTokens,
        lessThanOrEqualTo(
          r.report.multiOwnerProbes * (defaultDiscriminativenessCutoff - 1),
        ),
        reason: 'each multi-owner token adds at most cutoff-1 extra owners',
      );

      expect(r.report.droppedUnqueryable, greaterThan(0),
          reason: 'the fixture has single-character tokens, which search() '
              'rejects');
      expect(r.report.droppedNonDiscriminative, greaterThan(0),
          reason: 'the fixture has tokens like "Receipt" and "Total" on many '
              'records');
      expect(r.report.multiOwnerProbes, greaterThan(0));

      expect(r.text, contains('observations (probes)'));
      expect(r.text, contains('tokens considered'));
    });
  });

  group('fingerprints', () {
    test('the declared weight/tokenizer hash is present and non-trivial',
        () async {
      final _Run r = await runFixture();
      expect(r.report.declaredIndexConfigHash, hasLength(8));
      expect(r.report.declaredIndexConfigCanonical, contains('summary=5'));
      expect(r.report.declaredIndexConfigCanonical, contains('objects=2'));
      expect(r.report.declaredIndexConfigCanonical, contains(r'\u4e00-\u9fff'));
    });

    test('the behaviour hash comes from live search(), not a declaration',
        () async {
      final _Run r = await runFixture();
      expect(r.report.indexBehaviourHash, hasLength(8));
      expect(r.report.behaviourCanary, isNotEmpty,
          reason: 'the canary is what makes this hash observed rather than '
              'declared');
      expect(r.report.behaviourCanary.first['returned'], isA<List<Object?>>());
      expect(r.text, contains('This is the hash that moves'));
    });

    test('the hashes and the corpus hash are stable across two runs', () async {
      final _Run a = await runFixture(jsonName: 'a.json');
      final _Run b = await runFixture(jsonName: 'b.json');

      expect(b.report.corpusHash, a.report.corpusHash);
      expect(
          b.report.declaredIndexConfigHash, a.report.declaredIndexConfigHash);
      expect(b.report.indexBehaviourHash, a.report.indexBehaviourHash);
      // ...and the numbers agree, so a diff of two reports means the index
      // moved rather than the corpus or the clock.
      expect(b.report.lexicalMetrics.recallAt10,
          a.report.lexicalMetrics.recallAt10);
      expect(
        b.report.lexicalMetrics.medianRankAll,
        a.report.lexicalMetrics.medianRankAll,
      );
      // A different corpus must not collide with this one.
      const RecallCorpus other = RecallCorpus(
        label: 'x',
        records: <RecallCorpusRecord>[
          RecallCorpusRecord(fileName: 'a.png', ocrText: 'hello'),
        ],
      );
      expect(b.report.corpusHash, isNot(other.hash));
    });

    test('the caveat travels with the hashes in the JSON', () async {
      final _Run r = await runFixture();
      final Map<String, dynamic> parsed =
          jsonDecode(await r.json.readAsString()) as Map<String, dynamic>;
      final Map<String, dynamic> fingerprint =
          parsed['indexFingerprint'] as Map<String, dynamic>;
      expect(fingerprint['declaredIndexConfigHash'],
          r.report.declaredIndexConfigHash);
      expect(fingerprint['indexBehaviourHash'], r.report.indexBehaviourHash);
      expect(fingerprint['caveat'], contains('does NOT move'),
          reason: 'a reader of the JSON alone must not be misled about which '
              'hash observes the live index');
    });
  });

  group('fixture mode is labelled as such', () {
    test('the printed report says FIXTURE and warns against quoting it',
        () async {
      final _Run r = await runFixture();
      expect(r.report.mode, RecallCorpusMode.fixture);
      expect(r.text, contains('FIXTURE'));
      expect(r.text, contains('NOT A BASELINE'));
      expect(r.text, contains('hand-written'));
      expect(r.report.warnings.any((String w) => w.contains('FIXTURE MODE')),
          isTrue);
    });

    test('a real corpus carries neither the FIXTURE label nor the warning',
        () async {
      final Directory images =
          await Directory('${tempDir.path}/corpus').create(recursive: true);
      await File('${images.path}/shot_0001.png').writeAsString('not a png');
      await File('${images.path}/corpus.jsonl').writeAsString(
        '{"fileName":"shot_0001.png",'
        '"ocrText":"Blue Bottle Coffee\\nOat flat white",'
        '"tags":["coffee"],"objects":["Receipt"]}\n',
      );

      final List<String> lines = <String>[];
      final RecallReport? report = await RecallHarness.runRealRecall(
        imageDirectory: images,
        semanticQueriesPath: '${tempDir.path}/absent.jsonl',
        reportPath: '${tempDir.path}/real.json',
        emit: lines.add,
      );

      expect(report, isNotNull);
      expect(report!.mode, RecallCorpusMode.real);
      expect(lines.join('\n'), contains('mode: REAL'));
      expect(lines.join('\n'), isNot(contains('NOT A BASELINE')));
      expect(
        report.warnings.where((String w) => w.contains('FIXTURE MODE')),
        isEmpty,
      );
    });
  });

  group('semantic queries', () {
    test('are reported as not supplied when the file is absent', () async {
      final _Run r = await runFixture();
      expect(r.report.semanticStatus, 'not supplied');
      expect(r.report.semanticMetrics, isNull);
      expect(r.text, contains('not supplied'));
      expect(r.report.semanticSource, endsWith('absent_queries.jsonl'));
    });

    test('are parsed, measured and reported per query when present', () async {
      // Written by the test, never shipped: a semantic query file against the
      // fixture corpus would be fixture data masquerading as a semantic
      // baseline. This exercises the parser, not the index.
      final File queries = File('${tempDir.path}/queries.jsonl');
      await queries.writeAsString(<String>[
        '// hand-written queries, one JSON object per line',
        '{"q": "flat white", "expect": ["Screenshot_20260112_084512.png"]}',
        '{"q": "hiking permit", "expect": ["mountains_hike.png"]}',
        'not json at all',
        '{"q": "no expectations"}',
      ].join('\n'));

      final _Run r = await runFixture(semanticQueriesPath: queries.path);

      expect(r.report.semanticStatus, 'measured');
      expect(r.report.semanticObservations, hasLength(2));
      expect(r.report.semanticParseIssues, hasLength(2),
          reason: 'a malformed line is reported, not thrown, and not silently '
              'dropped either');
      expect(r.report.semanticMetrics!.total, 2);
      expect(r.text, contains('flat white'));
      expect(r.text, contains('Screenshot_20260112_084512.png'));
      expect(r.text, contains('per query'));
    });

    test('an expectation naming no record is flagged but still counted',
        () async {
      final File queries = File('${tempDir.path}/queries.jsonl');
      await queries.writeAsString(
        '{"q": "zebra", "expect": ["no_such_screenshot.png"]}\n',
      );

      final _Run r = await runFixture(semanticQueriesPath: queries.path);

      expect(r.report.semanticUnknownExpectations,
          <String>['no_such_screenshot.png']);
      expect(r.report.semanticMetrics!.total, 1,
          reason: 'kept in the metrics, so a typo in a hand-written file can '
              'only lower recall');
    });
  });

  group('score attribution', () {
    test('every per-field breakdown adds up to the score that produced it',
        () async {
      final _Run r = await runFixture();

      expect(r.report.attributionResults, isNotEmpty);
      final Iterable<RecallAttributedResult> mismatched = r
          .report.attributionResults
          .where((RecallAttributedResult a) => !a.contributionsMatchScore);
      expect(mismatched, isEmpty,
          reason:
              'the accessor shares search()\'s scoring path, so a breakdown '
              'that does not add up means the split is incomplete and the '
              'whole distribution is a fiction: '
              '${mismatched.take(5).map((RecallAttributedResult a) => "${a.query}@${a.rank}")}');
      for (final RecallAttributedResult a in r.report.attributionResults) {
        expect(
          a.contributionsSum,
          a.fieldContributions.values.fold(0, (int x, int y) => x + y),
        );
        expect(a.contributionsSum, a.score,
            reason: 'the invariant: for "${a.query}" rank ${a.rank} '
                '(${a.fileName}) the per-field weights must account for the '
                'whole score');
      }
      expect(r.report.lexicalAttribution.mismatchedResults, 0);
      expect(r.report.lexicalAttribution.results,
          r.report.attributionResults.length,
          reason: 'with no semantic file the attribution is class 1 only');
    });

    test('the breakdown is the live index answering, not a second scorer',
        () async {
      final _Run r = await runFixture();

      // Every result the harness attributed must be a result the same run's
      // `search()` returned, at the same rank. If the accessor described its own
      // set of records the two would disagree here, and run() warns about it.
      final Map<String, List<String>> returned = <String, List<String>>{
        for (final RecallObservation o in r.observations)
          o.query: o.returnedFileNames,
      };
      for (final RecallAttributedResult a in r.report.attributionResults
          .where((RecallAttributedResult a) => a.rank <= 10)) {
        final List<String>? hits = returned[a.query];
        expect(hits, isNotNull, reason: 'no search() list for "${a.query}"');
        expect(a.rank, lessThanOrEqualTo(hits!.length));
        expect(a.fileName, hits[a.rank - 1],
            reason: 'rank ${a.rank} of "${a.query}" must be the same record '
                'search() returned at that rank');
      }
      expect(r.report.warnings.where((String w) => w.contains('disagreed')),
          isEmpty);
    });

    test(
        'the distribution is reported over every weighted field, dead ones named',
        () async {
      final _Run r = await runFixture();
      final RecallFieldAttribution a = r.report.lexicalAttribution;

      expect(a.top10Slots, greaterThan(0));
      expect(a.top10Units, greaterThan(0));
      // Ranked by contribution, so the most productive field is first.
      final List<String> ranked = a.rankedFields;
      expect(ranked, containsAll(<String>['summary', 'ocrText', 'objects']));
      for (int i = 1; i < ranked.length; i++) {
        expect((a.top10SlotsByField[ranked[i - 1]] ?? 0),
            greaterThanOrEqualTo(a.top10SlotsByField[ranked[i]] ?? 0));
      }
      // Slot shares are bounded but need not sum to 1: one slot can credit
      // several fields, and the test says so rather than forcing a total.
      expect(a.slotShareAt10('summary'), inInclusiveRange(0.0, 1.0));
      expect(
        a.top10SlotsByField.values.fold<int>(0, (int x, int y) => x + y),
        greaterThanOrEqualTo(a.top10Slots),
      );
      // Unit shares, on the other hand, are a partition of the summed score.
      expect(
        a.top10UnitsByField.values.fold<int>(0, (int x, int y) => x + y),
        a.top10Units,
      );

      // The point of the whole section: fields the index weights but that never
      // decided a top-10 rank are named, not omitted.
      final List<String> zero = a.zeroContributionFields;
      for (final String f in zero) {
        expect(declaredIndexWeights, contains(f),
            reason: 'a dead field must still be a weighted field, otherwise '
                '"zero contribution" is measuring nothing');
        expect(a.top10SlotsByField[f], anyOf(isNull, 0));
      }
      expect(zero, contains('description'),
          reason: 'the local write path never fills `description`, so it '
              'cannot have decided a single top-10 rank. If this ever goes '
              'green, a write path changed and the declared weight table is '
              'stale.');
      expect(zero, contains('searchKeywords'));
      expect(zero, contains('recognitions'));
      expect(zero, contains('extractedData'));
      expect(a.fieldsOutsideDeclaredTable, isEmpty);
    });

    test('the attribution is in the printed report and in the JSON', () async {
      final _Run r = await runFixture();
      expect(r.text, contains('SCORE ATTRIBUTION'));
      expect(r.text, contains('ZERO-CONTRIBUTION FIELDS'));
      expect(r.text, contains('same'));

      final Map<String, dynamic> parsed =
          jsonDecode(await r.json.readAsString()) as Map<String, dynamic>;
      // The existing contract is intact: same top-level keys, plus the new one.
      expect(
        parsed.keys,
        containsAll(<String>[
          'tool',
          'schemaVersion',
          'timestamp',
          'mode',
          'modeLabel',
          'corpus',
          'indexFingerprint',
          'lexicalProbes',
          'semanticQueries',
          'warnings',
          'reportPath',
        ]),
      );
      final Map<String, dynamic> attribution =
          parsed['scoreAttribution'] as Map<String, dynamic>;
      expect(attribution['lexical'], isNotNull);
      expect(attribution['semantic'], isNull,
          reason: 'no query file was supplied, so class 2 has no attribution '
              'and class 1 must not stand in for it');
      expect(attribution['indexedFieldNames'],
          containsAll(declaredIndexWeights.keys));
      expect(attribution['caveat'], contains('do not sum'),
          reason: 'a reader of the JSON alone must not read slot shares as a '
              'partition');
      expect(
        (attribution['perResult'] as List<Object?>),
        isNotEmpty,
        reason: 'the per-result rows are the evidence behind the distribution',
      );
      // Per-probe JSON is unchanged, so a diff of two reports still works.
      final List<Object?> probes = (parsed['lexicalProbes']
          as Map<String, dynamic>)['perProbe'] as List<Object?>;
      expect(probes, isNotEmpty);
      expect((probes.first as Map<String, dynamic>).keys,
          isNot(contains('fieldContributions')),
          reason: 'attribution lives under its own key so the existing '
              'per-probe rows stay byte-comparable across runs');
    });

    test('a tied rank is sized, not just caveated in prose', () async {
      final _Run r = await runFixture();
      final RecallFieldAttribution a = r.report.lexicalAttribution;

      // The fixture deliberately contains equal-score neighbours -- the bare
      // number probes match several records with the same weight -- so this is
      // a real number here, not a hypothetical.
      expect(a.tiedTop10Slots, greaterThan(0),
          reason: 'if this were ever 0 the tie caveat would be noise; while it '
              'is non-zero the field breakdown must not be read as the reason '
              'those records outranked their neighbours');

      // Every row marked tied really does have a neighbour with the same score,
      // and every row not marked tied really does not.
      final Map<String, List<RecallAttributedResult>> byQuery =
          <String, List<RecallAttributedResult>>{};
      for (final RecallAttributedResult row in r.report.attributionResults) {
        (byQuery[row.query] ??= <RecallAttributedResult>[]).add(row);
      }
      for (final List<RecallAttributedResult> rows in byQuery.values) {
        for (int i = 0; i < rows.length; i++) {
          final int score = rows[i].score;
          final bool expected = (i > 0 && rows[i - 1].score == score) ||
              (i + 1 < rows.length && rows[i + 1].score == score);
          expect(rows[i].tiedWithNeighbour, expected,
              reason: 'rank ${rows[i].rank} of "${rows[i].query}"');
        }
      }
      expect(r.text, contains('shared a score with a neighbour'));
    });

    test('class 2 attribution is measured when a query file is supplied',
        () async {
      final File queries = File('${tempDir.path}/attr_queries.jsonl');
      await queries.writeAsString(
        '{"q": "flat white", "expect": ["Screenshot_20260112_084512.png"]}\n',
      );
      final _Run r = await runFixture(semanticQueriesPath: queries.path);

      final RecallFieldAttribution? semantic = r.report.semanticAttribution;
      expect(semantic, isNotNull);
      expect(semantic!.results, greaterThan(0));
      expect(semantic.mismatchedResults, 0);
      expect(
        r.report.attributionResults
            .where((RecallAttributedResult a) =>
                a.queryClass == RecallQueryClass.semantic)
            .map((RecallAttributedResult a) => a.query)
            .toSet(),
        <String>{'flat white'},
        reason:
            'every result of the one semantic query is attributed, not just '
            'the one that happened to be the expectation',
      );
      // Still never merged: the two classes have their own distributions.
      expect(semantic.results, lessThan(r.report.lexicalAttribution.results));
      expect(r.text, contains('CLASS 2 -- SEMANTIC QUERIES'));
    });
  });

  group('real mode', () {
    test('skips cleanly when unconfigured', () async {
      final RecallReport? report = await RecallHarness.runRealRecall(
        imageDirectory: Directory('${tempDir.path}/does_not_exist'),
        reportPath: '${tempDir.path}/never.json',
        emit: (_) {},
      );
      expect(report, isNull);
    });

    test('a missing sidecar is loud', () {
      final Directory images = Directory('${tempDir.path}/no_sidecar')
        ..createSync(recursive: true);
      expect(
        () => RecallHarness.realCorpusFromDirectory(images),
        throwsStateError,
      );
    });

    test('a sidecar naming a file that is not there is loud', () {
      final Directory images = Directory('${tempDir.path}/bad_sidecar')
        ..createSync(recursive: true);
      File('${images.path}/corpus.jsonl')
          .writeAsStringSync('{"fileName":"absent.png"}\n');
      expect(
        () => RecallHarness.realCorpusFromDirectory(images),
        throwsStateError,
      );
    });

    test('the sidecar reader loads comments, tags, labels and OCR', () async {
      final Directory images = Directory('${tempDir.path}/ok')
        ..createSync(recursive: true);
      File('${images.path}/a.png').writeAsStringSync('x');
      File('${images.path}/b.png').writeAsStringSync('x');
      File('${images.path}/corpus.jsonl').writeAsStringSync(<String>[
        '{"fileName":"a.png","ocrText":"Blue Bottle Coffee",'
            '"tags":["coffee"],"objects":["Receipt"]}',
        '// a comment line is ignored',
        '',
        '{"fileName":"b.png","ocrText":"Train timetable"}',
      ].join('\n'));

      final RecallCorpus corpus = RecallHarness.realCorpusFromDirectory(images);
      expect(corpus.mode, RecallCorpusMode.real);
      expect(corpus.records, hasLength(2));
      expect(corpus.records.first.tags, <String>['coffee']);
      expect(corpus.records.first.objects, <String>['Receipt']);
      expect(corpus.records.last.tags, isEmpty);

      // And the same loader feeds a real measurement end to end.
      final _Run r = await run(corpus, jsonName: 'real_sidecar.json');
      expect(r.report.mode, RecallCorpusMode.real);
      expect(r.report.corpusSize, 2);
      expect(r.report.lexicalObservations, isNotEmpty);
    });

    test('a declared summary production would not derive is reported',
        () async {
      const RecallCorpus wrong = RecallCorpus(
        label: 'wrong-summary',
        mode: RecallCorpusMode.real,
        records: <RecallCorpusRecord>[
          RecallCorpusRecord(
            fileName: 'a.png',
            ocrText: 'Blue Bottle Coffee\nOat flat white',
            summary: 'something production would never produce',
          ),
        ],
      );
      final _Run r = await run(wrong, jsonName: 'wrong_summary.json');
      expect(r.report.fieldPolicy.summaryMismatches, hasLength(1));
      expect(r.report.fieldPolicy.summaryMismatches.single,
          contains('Blue Bottle Coffee'));
    });

    test('a declared summary that matches production is not flagged', () async {
      const RecallCorpus right = RecallCorpus(
        label: 'right-summary',
        mode: RecallCorpusMode.real,
        records: <RecallCorpusRecord>[
          RecallCorpusRecord(
            fileName: 'a.png',
            ocrText: 'Blue Bottle Coffee\nOat flat white',
            summary: 'Blue Bottle Coffee',
          ),
        ],
      );
      final _Run r = await run(right, jsonName: 'right_summary.json');
      expect(r.report.fieldPolicy.summaryMismatches, isEmpty);
    });
  });
}

/// One harness run: the report, the text it printed, and the JSON it wrote.
class _Run {
  const _Run(this.report, this.text, this.json);

  final RecallReport report;
  final String text;
  final File json;

  /// The lexical observations, named once so the assertions above read as
  /// "what did the probes find" rather than as plumbing.
  List<RecallObservation> get observations => report.lexicalObservations;
}
