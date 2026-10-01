import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

// ============================================================================
// SIFT RECALL HARNESS -- a baseline measurement tool, not a test.
//
// Purpose: turn "the ranking weights feel wrong" into a number. Phase 0 of
// `sift-product-plan.md` is a baseline, and a baseline is only worth anything
// if the *same* measurement can be re-run after the index changes. So all the
// logic lives here, in a reusable class, and `test/recall_harness_test.dart`
// only drives it.
//
// This file is under `test/support/` and is deliberately not named
// `*_test.dart`, so `flutter test` never collects it as a suite. It ships with
// the test tree because it needs the package's own dependencies (Hive, the
// provider) and nothing else.
//
// -- TWO QUERY CLASSES, REPORTED SEPARATELY ---------------------------------
//
//   Class 1 -- lexical probes. Derived automatically from tokens known to be in
//     each record. Measures: can the index get back a record that plainly
//     contains the word you typed? A property of the *index*.
//
//   Class 2 -- semantic queries. Hand-written, human-labelled phrases -- what a
//     user would actually type. Measures: can the index satisfy a real query?
//     A property of the index *and* the data, and where an OCR-and-labels-only
//     design is expected to lose.
//
// They are never averaged into one number. Class 1 has a ceiling of 1.0 on a
// library where the word is indexed; class 2 on a keyword index has a ceiling
// far below that, and no amount of weighting closes the gap. Blending them
// would hide the only interesting number in the report.
//
// -- WHAT IS PROBED, AND WHY (class 1) -------------------------------------
//
// Probed: `ocrText`, `objects`, `tags`. The three fields the local analyzer
// and the user actually fill.
//
// NOT probed:
//   * `summary` -- the first 80 characters of `ocrText`. Probing it would probe
//     the same characters twice and credit the index for a duplicate field.
//   * `fileName` -- real but thin. A screenshot's name is mostly a timestamp, so
//     most of its tokens are either non-discriminative (the date half of every
//     name) or already in the OCR or the labels.
//   * `searchKeywords`, `description`, `recognitions`, `extractedData` -- never
//     populated by the local analyzer, so their 11 weight units never fire.
//     Probing them would measure an empty field. [RecallFieldPolicy] checks them
//     against the records this run seeded, and that check is narrower than it
//     looks: seeding goes through `addFromBulkIngest` only, so what is confirmed
//     is "empty on the records seeded through `addFromBulkIngest`".
//     `processScreenshot` is the other local write path and is NOT exercised
//     here. Both are believed to leave these four fields empty, but that is a
//     review conclusion about code the harness does not run, not a measurement.
//     See the note on `zeroContributionFields` for the one way a real run can
//     legitimately show them firing.
//   * `lamType` -- the constant `'document'`, and deliberately not indexed at
//     all. There is no token to derive.
//   * the `'No text found'` summary placeholder -- display-only, gated out of
//     the index by `ScreenshotProvider._searchableText`. The harness does not
//     re-implement that gate; it never asks for a summary token, so there is
//     nothing to leak.
//
// -- DISCRIMINATIVENESS ----------------------------------------------------
//
// A probe is only informative if the owning record can win. A token in 40
// screenshots cannot be recalled by any of them -- the query has 40 legitimate
// answers -- so measuring it reports the corpus's vocabulary, not the index.
//
// [defaultDiscriminativenessCutoff] keeps a token whose *exact* token appears
// in at most that many records. Prefix broadening is counted separately as
// `matchCount`: records `search()` can actually reach with that query, because
// a query term matches every indexed term that *starts with* it. A probe whose
// matchCount is large is crowded even when ownerCount is 1, and the report
// prints that so a reader sees the crowding instead of inferring it.
//
// Tokens shared by several owners are KEPT, and each owner is measured
// separately. Two records holding `Dog` cannot both be rank 1, so at most one
// of the two observations can score; averaging that away would credit the sort
// for a coin flip. `ownerCount` is in the JSON per probe for that reason.
//
// Two more tokens are dropped before they reach the filter:
//   * single-character non-CJK tokens -- `search()` rejects any query shorter
//     than 2 chars unless it contains CJK, so such a probe returns [] by
//     construction. Scoring that as a miss would measure the harness's own bad
//     probe. A single CJK character is legal and is kept.
//   * tokens longer than 64 chars -- the indexer's word-length cap drops them,
//     so they can never be found.
//
// -- SEMANTIC QUERY FILE (class 2, optional) -------------------------------
//
// One JSON object per line. Blank lines and lines starting with `//` are
// ignored, so the file can carry comments.
//
//   {"q": "what did I pay for coffee", "expect": ["shot_0001.png"]}
//
// `q`      the query text, passed to `search()` verbatim. Subject to the same
//          rules as any user query: lowercased, split on non-[A-Za-z0-9]/CJK
//          separators, first 6 terms only, 2-char minimum (1 for CJK).
// `expect` file names a human would accept as a correct answer. A query counts
//          as a hit at rank k if ANY of them is in the top k -- "find the coffee
//          receipt" has two right answers and neither is an error.
//
// Default location: `tool/recall_queries.jsonl`, relative to the package root.
// Pass `semanticQueriesPath` to point elsewhere. If the file is absent, class 2
// is reported as "not supplied" and nothing else changes.
//
// A malformed line is reported, not thrown: this is a hand-edited file and a
// typo in it must not take the whole baseline down. An `expect` naming a file
// that is not in the corpus is reported too -- and kept in the metrics, so a
// typo can only lower recall, never flatter it.
//
// -- REAL CORPUS (sidecar format) ------------------------------------------
//
// The real corpus does not exist yet. This is the format it will need, so the
// harness is ready and nobody has to guess later.
//
//   <image-dir>/
//     shot_0001.png          <- the screenshots, one file per record
//     shot_0002.png
//     corpus.jsonl           <- the sidecar, one JSON object per line
//
// Each sidecar line describes one screenshot:
//
//   {"fileName":  "shot_0001.png",         // REQUIRED -- must exist in <image-dir>
//    "ocrText":   "Blue Bottle Coffee...",  // optional, what ML Kit read
//    "tags":      ["coffee", "work"],     // optional, the user's tags
//    "objects":   ["Receipt", "Food"],    // optional, ML Kit labels
//    "summary":   "Blue Bottle Coffee"}   // optional, VERIFIED not used
//
// `summary` is accepted and checked, not used. The local write paths derive
// `summary` from `ocrText` and nothing else, so the harness seeds through
// `addFromBulkIngest` and lets production do the deriving. A sidecar claiming a
// summary production would not produce is a broken sidecar, and that surfaces
// as `summaryMismatches` instead of silently skewing the weights.
//
// Point the harness at it:
//   await RecallHarness.runRealRecall(imageDirectory: Directory('.../corpus'));
// `null` comes back when the directory does not exist -- that is the whole
// "unconfigured" behaviour, so a caller skips with a null check.
//
// -- WHY THE HARNESS SEEDS THROUGH addFromBulkIngest -----------------------
//
// Seeding goes through `addFromBulkIngest` + `addTag`, the same two calls the
// app makes. That keeps the first-line/80-char slice, the `'No text found'`
// placeholder, the 2000-char OCR cap, the constant `lamType`, the label dedupe
// and the per-field weight rule all in `lib/`. A harness that wrote Screenshot
// rows itself would carry a second copy of that logic that drifts the first
// time production changes -- and a baseline that measures the wrong index is
// worse than no baseline.
//
// -- THE HASHES, AND WHAT EACH ONE ACTUALLY PROVES -------------------------
//
//   corpusHash              which records went in, and in what order
//   declaredIndexConfigHash the harness's *declared* model of the weights and
//                           tokenizer. Proves which configuration the harness
//                           believed it was measuring. It is a declaration, not
//                           an observation: the weights are private in
//                           `screenshot_provider.dart` and are mirrored here,
//                           so editing a weight in `lib/` does NOT move this
//                           hash. The canonical string ships in the JSON so
//                           the declaration is auditable by eye.
//   indexBehaviourHash      a fingerprint of what the live index actually did,
//                           built from a fixed canary of queries run through
//                           the real `search()`. The one that moves when
//                           someone changes a weight in `lib/`.
//
// Comparing two reports: same corpusHash means the same corpus; a changed
// indexBehaviourHash under an unchanged declaredIndexConfigHash means the index
// moved underneath a harness that was never told. That combination is the
// whole point of keeping both.
//
// The tokenizer is mirrored here rather than called, because it is private.
// The mirror is guarded by issuing every retained probe against the real
// `search()`: a mirror that drifted would return nothing and recall@1 would
// collapse. That catches the damaging divergence (different split rules). It
// cannot catch a divergence in a code path no probe reaches. Stated plainly,
// because it is a real limit of this tool.
//
// -- SCORE ATTRIBUTION: WHICH FIELDS PRODUCED THE RANKS ---------------------
//
// Phase 0 item 2 asks which fields produced each hit. `search()` returns ranked
// screenshots and no scores, so that was not answerable from outside `lib/` --
// and the fix was NOT to re-implement the scorer here, which would have made
// the measurement a fiction about the harness instead of about the index.
//
// `ScreenshotProvider.explainScores()` is the additive accessor that answers it.
// It runs the *same* private scorer `search()` runs: this file reads totals out
// of it and never computes one. The per-field split is a decomposition of that
// total, derived through the same `_indexedFields` table the index was built
// from, with the same weights, the same tokenizer and the same `_searchableText`
// gate. So there is one scorer in `lib/`, and this file adds none.
//
// Three things are therefore reported that a reader of the old report could not
// be told:
//
//   * the ranked distribution -- how much of the top 10 came from each field;
//   * the zero-contribution fields -- indexed and weighted, but credited to
//     nothing. This is the number that decides whether a weight is justified.
//     It is also the one number here that a real corpus can legitimately move:
//     see the caveat under "WHAT IS PROBED, AND WHY" above, and
//     [RecallFieldAttribution.zeroContributionFields];
//   * the expectation distribution -- the same thing restricted to the records
//     the observation was actually looking for, which is narrower and more
//     damning than the ranking-wide view.
//
// And the honesty mechanisms that come with it:
//
//   * every breakdown is checked against the total it claims to explain. A
//     mismatch is counted, warned about, and flagged in the table as making the
//     distribution a LOWER BOUND rather than a decomposition;
//   * `explainScores()` is cross-checked against the `search()` list this run
//     already took, so a disagreement between the two is reported rather than
//     silently resolved in favour of one;
//   * the tokenizer-mirror caveat above still stands for probe *derivation*.
//     Attribution does not use the mirror -- it reads the live index -- so the
//     two halves of this report now have different provenance, and that is worth
//     knowing: a wrong recall number is a mirror problem, a wrong attribution
//     is an index problem;
//   * a slot says what a result was MADE OF, not why it beat its neighbour. The
//     sort has no tiebreak, so two equal-score records are indistinguishable
//     here exactly as they are in the ranking.
// ============================================================================

/// Bumped when the JSON report's shape changes, so a stored report can be read
/// back without guessing.
const int recallReportSchemaVersion = 1;

/// The Hive box the production write path uses. The harness opens it if needed
/// and never closes it -- box lifecycle belongs to the caller's setUp/tearDown,
/// like every other provider test in this repo.
const String recallHarnessHiveBox = 'screenshots';

/// The placeholder `summary` the local analyzer stores for a text-free
/// screenshot. Display-only; the index gates it out. Named here so the report
/// can say so out loud instead of leaving it implicit. Held lowercased
/// because it is compared against a lowercased stored value, matching how
/// `ScreenshotProvider._displayOnlyValues` keeps its own registry.
const String noTextFoundPlaceholder = 'no text found';

/// The spelling the app actually stores and displays, for the report line that
/// quotes it back to the reader.
const String noTextFoundPlaceholderStored = 'No text found';

/// `search()`'s minimum query length for non-CJK queries.
const int recallMinQueryChars = 2;

/// The indexer's word-length cap. A longer token is dropped on the way in, so
/// it can never be found and is not a fair probe.
const int recallMaxWordLength = 64;

/// The indexer's OCR blob cap. Tokens past it are in the record but not in the
/// index, so probing them would be probing a string that was never stored.
const int recallOcrBlobCap = 2000;

// -- The harness's declared model of the index ------------------------------
//
// Mirrors `screenshot_provider.dart`. Written as sorted map literals on
// purpose: Dart map literals preserve insertion order, so a stable iteration
// order is what makes the canonical hash input reproducible.

/// Per-(term, field) weights, the values the indexer currently uses.
/// Unmeasured constants -- this harness records them, it does not change them.
const Map<String, int> declaredIndexWeights = <String, int>{
  'description': 4,
  'extractedData': 1,
  'fileName': 1,
  'objects': 2,
  'ocrText': 1,
  'recognitions': 2,
  'searchKeywords': 4,
  'summary': 5,
  'tags': 3,
};

/// Tokenizer and query-path configuration, as strings so the canonical hash
/// input has exactly one type.
const Map<String, String> declaredTokenizerConfig = <String, String>{
  'cjkRange': r'4e00-9fff',
  'displayOnlyValues': 'no text found',
  'indexedFields': 'summary description tags objects fileName ocrText',
  'lowercased': 'true',
  'matchMode': 'query-is-prefix-of-indexed-term',
  'maxQueryTerms': '6',
  'maxWordLength': '64',
  'minQueryChars': '2',
  'minQueryCharsCjk': '1',
  'notIndexedFields': 'lamType',
  'ocrBlobCap': '2000',
  'splitter': r'[^A-Za-z0-9\u4e00-\u9fff]+',
  'weightRule': 'once-per-term-per-field',
};

/// The splitter the index uses, as code. Raw string with the same `\uXXXX`
/// escapes production uses, so [recallWordSplitter.pattern] is byte-identical
/// to `ScreenshotProvider._wordSplitter.pattern` and the declaration in
/// [declaredTokenizerConfig] cannot drift from the behaviour below it.
final RegExp recallWordSplitter = RegExp(r'[^A-Za-z0-9\u4e00-\u9fff]+');

/// Matches any CJK character. `search()`'s minimum-query gate keys on exactly
/// this test, which is why a one-character CJK probe is legal and a
/// one-character Latin probe is not.
final RegExp recallCjk = RegExp(r'[\u4e00-\u9fff]');

/// Whether [value] contains a CJK character, mirroring `search()`'s gate.
bool recallHasCjk(String value) => recallCjk.hasMatch(value);

/// A query of [text] is rejected by `search()` before the index is consulted
/// when it is shorter than [recallMinQueryChars] and holds no CJK. Probes and
/// semantic queries that cannot survive this gate are not index failures.
bool recallIsBelowMinQuery(String text) =>
    text.trim().length < recallMinQueryChars && !recallHasCjk(text);

/// Lowercase, split on non-`[A-Za-z0-9]`/CJK separators, drop empties and drop
/// anything longer than the index's word-length cap.
///
/// Mirrors `ScreenshotProvider._tokenize`. It has to be a copy, because the
/// real one is private and this file may not change `lib/`. See the header note
/// for what that costs.
List<String> recallTokens(String text) {
  return text
      .toLowerCase()
      .split(recallWordSplitter)
      .where((String w) => w.isNotEmpty && w.length <= recallMaxWordLength)
      .toList();
}

/// True when [token] is a legal query on its own: long enough for the
/// minimum-query gate and not over the index's word-length cap.
bool recallTokenIsQueryable(String token) =>
    !recallIsBelowMinQuery(token) && token.length <= recallMaxWordLength;

/// The most records one token may appear in and still be treated as a probe.
/// Three is generous enough to keep multi-owner tokens visible and tight enough
/// to drop the vocabulary every screenshot shares.
const int defaultDiscriminativenessCutoff = 3;

/// Where class-2 queries are looked for unless told otherwise.
const String defaultSemanticQueriesPath = 'tool/recall_queries.jsonl';

/// Where the JSON report is written. `build/` is gitignored, so a report never
/// shows up as a repo change.
const String defaultRecallReportPath = 'build/recall_report.json';

/// Every field the indexer gives a weight to, sorted.
///
/// Used as the denominator of the score-attribution report: a field is *dead*
/// when it appears here and contributes to nothing. Derived from the declared
/// table rather than from the observations, so a weight that never fires is
/// named in the report instead of being silently absent from it.
final List<String> recallIndexedFieldNames = declaredIndexWeights.keys.toList()
  ..sort();

// ============================================================================
// Corpus
// ============================================================================

/// One record of a recall corpus: what a single screenshot contributes to the
/// index. `fileName` is the id -- it is what the index stores, what `search()`
/// returns, and what a semantic query's `expect` list names.
class RecallCorpusRecord {
  const RecallCorpusRecord({
    required this.fileName,
    this.ocrText,
    this.tags = const <String>[],
    this.objects = const <String>[],
    this.summary,
  });

  final String fileName;
  final String? ocrText;
  final List<String> tags;
  final List<String> objects;

  /// The `summary` production is expected to derive from [ocrText]. The harness
  /// verifies this when it is supplied and never writes it itself; see the
  /// sidecar note in the header.
  final String? summary;

  /// Stable serialization for the corpus hash. Sorted inside the list fields so
  /// a reordering of `tags` is not treated as a different corpus -- order is
  /// not meaningful for either list.
  List<String> canonicalParts() => <String>[
        'fileName=$fileName',
        'ocrText=${ocrText ?? ''}',
        'summary=${summary ?? ''}',
        'tags=${(List<String>.of(tags)..sort()).join(',')}',
        'objects=${(List<String>.of(objects)..sort()).join(',')}',
      ];
}

/// Which corpus a report describes. Printed on every report so a fixture number
/// can never be filed as a real baseline.
enum RecallCorpusMode {
  fixture,
  real;

  String get label => this == RecallCorpusMode.fixture ? 'FIXTURE' : 'REAL';
}

/// A corpus plus where it came from.
class RecallCorpus {
  const RecallCorpus({
    required this.label,
    required this.records,
    this.mode = RecallCorpusMode.fixture,
  });

  final String label;
  final List<RecallCorpusRecord> records;
  final RecallCorpusMode mode;

  bool get isFixture => mode == RecallCorpusMode.fixture;

  /// FNV-1a over every record's canonical parts, in list order. Two runs of the
  /// same corpus agree; a reordered or edited corpus does not.
  String get hash => recallStableHash(<String>[
        'recall-corpus-v1',
        label,
        for (final RecallCorpusRecord r in records) ...r.canonicalParts(),
      ]);
}

// ============================================================================
// Probe derivation
// ============================================================================

/// A query the harness invents from a record it can already see, plus the
/// evidence for why that query is a fair test.
class RecallProbe {
  const RecallProbe({
    required this.token,
    required this.ownerFileName,
    required this.ownerCount,
    required this.matchCount,
    required this.sourceFields,
  });

  /// The query text, as `search()` will receive it.
  final String token;

  /// The record this observation is about. When [ownerCount] > 1, several
  /// records share the token and each gets its own observation.
  final String ownerFileName;

  /// Records holding this exact token. A ceiling on what recall@1 can be here:
  /// with two owners, at most one of the two observations can be rank 1.
  final int ownerCount;

  /// Records `search()` can reach with this query, including those reached by
  /// prefix extension. Never smaller than [ownerCount].
  final int matchCount;

  /// Which probed fields carried the token, e.g. `['ocrText', 'tags']`. Cheap
  /// attribution: it says where the probe came from, not which field won the
  /// ranking. The field that won the ranking is a separate measurement, read
  /// from the live index -- see the score-attribution note in the header.
  final List<String> sourceFields;

  Map<String, Object?> toJson() => <String, Object?>{
        'token': token,
        'owner': ownerFileName,
        'ownerCount': ownerCount,
        'matchCount': matchCount,
        'sourceFields': sourceFields,
      };
}

/// One measurement: a query, what should have come back, and where it landed.
class RecallObservation {
  const RecallObservation({
    required this.query,
    required this.expectations,
    required this.returnedFileNames,
    required this.bestRank,
    this.probe,
  });

  final String query;

  /// File names that count as a correct answer. Always length 1 for a lexical
  /// probe; usually longer for a semantic query.
  final List<String> expectations;

  /// What `search()` actually returned, in rank order.
  final List<String> returnedFileNames;

  /// 1-based rank of the best [expectation] in [returnedFileNames], or null when
  /// none of them came back at all.
  final int? bestRank;

  /// Present for class 1 only.
  final RecallProbe? probe;

  bool isHitAt(int k) => bestRank != null && bestRank! <= k;

  Map<String, Object?> toJson() => <String, Object?>{
        'query': query,
        'expectations': expectations,
        'bestRank': bestRank,
        'resultCount': returnedFileNames.length,
        'returned': returnedFileNames,
        if (probe != null) ...probe!.toJson(),
      };
}

/// recall@k over a set of observations.
///
/// `recallAtK` is null rather than 0.0 when there are no observations at all, so
/// "nothing survived the filter" is never printed as "recall 0%".
class RecallMetrics {
  const RecallMetrics(this.observations);

  final List<RecallObservation> observations;

  int get total => observations.length;

  int get found =>
      observations.where((RecallObservation o) => o.bestRank != null).length;

  int get unfound => total - found;

  int _hitsAt(int k) =>
      observations.where((RecallObservation o) => o.isHitAt(k)).length;

  int get hitAt1 => _hitsAt(1);
  int get hitAt5 => _hitsAt(5);
  int get hitAt10 => _hitsAt(10);

  double? _recallAt(int k) => total == 0 ? null : _hitsAt(k) / total;

  double? get recallAt1 => _recallAt(1);
  double? get recallAt5 => _recallAt(5);
  double? get recallAt10 => _recallAt(10);

  /// Median rank over every observation, with an unreturned observation ranked
  /// below any real rank (corpus size + 1). The honest median: it cannot be
  /// flattered by dropping the misses.
  int? get medianRankAll {
    if (total == 0) return null;
    final List<int> ranks = observations
        .map((RecallObservation o) => o.bestRank ?? total + 1)
        .toList()
      ..sort();
    final int mid = ranks.length ~/ 2;
    return ranks.length.isOdd ? ranks[mid] : (ranks[mid - 1] + ranks[mid]) ~/ 2;
  }

  /// Median rank over the observations that returned something. Always <=
  /// [medianRankAll] and always more flattering; reported next to it so the
  /// difference is visible rather than inferred.
  int? get medianRankFound {
    final List<int> ranks = observations
        .map((RecallObservation o) => o.bestRank)
        .whereType<int>()
        .toList()
      ..sort();
    if (ranks.isEmpty) return null;
    final int mid = ranks.length ~/ 2;
    return ranks.length.isOdd ? ranks[mid] : (ranks[mid - 1] + ranks[mid]) ~/ 2;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'observations': total,
        'found': found,
        'notFound': unfound,
        'recallAt1': recallAt1,
        'recallAt5': recallAt5,
        'recallAt10': recallAt10,
        'hits': <String, int>{'at1': hitAt1, 'at5': hitAt5, 'at10': hitAt10},
        'medianRankAll': medianRankAll,
        'medianRankAmongFound': medianRankFound,
      };
}

// ============================================================================
// Field policy -- what the harness refuses to probe, and the evidence
// ============================================================================

/// Which fields a probe may be derived from, and the recorded reason each of
/// the others is skipped. Exposed in the report so the omission is auditable
/// instead of implied by a missing number.
class RecallFieldPolicy {
  const RecallFieldPolicy({
    required this.probed,
    required this.skipped,
    required this.neverPopulatedConfirmed,
    required this.lamTypeValues,
    required this.placeholderSummaryCount,
    required this.summaryMismatches,
  });

  /// Fields probes are derived from.
  static const List<String> probedFields = <String>[
    'ocrText',
    'objects',
    'tags'
  ];

  /// Field name -> why it is not probed.
  ///
  /// The reasons naming an "empty" field are scoped to the records this run
  /// seeded through `addFromBulkIngest`. `processScreenshot` is the other local
  /// write path and is not exercised here, and a legacy Hive row written by an
  /// older build could legitimately carry these fields -- which is the one way a
  /// real-corpus run shows them contributing.
  static const Map<String, String> skippedFields = <String, String>{
    'description': 'null on every record seeded through addFromBulkIngest',
    'extractedData': 'null on every record seeded through addFromBulkIngest',
    'fileName': 'indexed, but mostly a timestamp; its distinctive tokens are '
        'already in the OCR or the labels',
    'lamType': "constant 'document', and not indexed at all",
    'recognitions':
        'empty list on every record seeded through addFromBulkIngest',
    'searchKeywords':
        'empty list on every record seeded through addFromBulkIngest',
    'summary': 'first 80 chars of ocrText; probing it would probe the same '
        'characters twice',
  };

  final List<String> probed;
  final Map<String, String> skipped;

  /// Checked against the records this run seeded: every `description` null,
  /// every `searchKeywords` / `recognitions` empty, every `extractedData` null.
  ///
  /// Read it as "confirmed empty on the records seeded through
  /// `addFromBulkIngest`", which is all it can see. `processScreenshot` is the
  /// other local write path and the harness does not exercise it. If a future
  /// change makes either path fill one of these fields, this goes false only if
  /// the seeded records changed too -- so the flag alone will not catch it. That
  /// is why the reasons in [skippedFields] name the seeding path rather than
  /// claiming a property of the app.
  final bool neverPopulatedConfirmed;

  /// Distinct `lamType` values seen. One value means it cannot discriminate.
  final List<String> lamTypeValues;

  /// Records whose stored `summary` is the display-only placeholder. None of
  /// their tokens is ever turned into a probe.
  final int placeholderSummaryCount;

  /// Sidecar records whose declared `summary` is not what production derives.
  final List<String> summaryMismatches;

  Map<String, Object?> toJson() => <String, Object?>{
        'probed': probed,
        'skipped': skipped,
        'neverPopulatedConfirmed': neverPopulatedConfirmed,
        'lamTypeValues': lamTypeValues,
        'placeholderSummaryCount': placeholderSummaryCount,
        'summaryMismatches': summaryMismatches,
      };
}

// ============================================================================
// Score attribution -- which field produced which rank
// ============================================================================

/// The query class an attributed result was measured under. Never merged: a
/// lexical probe and a semantic query answer different questions and their
/// attribution is reported separately, for the same reason their recall is.
enum RecallQueryClass {
  lexical,
  semantic;

  String get label => this == RecallQueryClass.lexical ? 'class 1' : 'class 2';
}

/// One result of one query, with the score `search()` ranked it on and the
/// per-field weights that added up to that score.
///
/// The score and the order come from
/// `ScreenshotProvider.explainScores`, which shares its scoring path with
/// `search()` — so [score] is the score that produced [rank], not a
/// reconstruction of it. The split is a decomposition of that score, and
/// [contributionsMatchScore] says whether it adds up; the harness counts the
/// misses and reports them rather than printing a breakdown it cannot vouch for.
class RecallAttributedResult {
  const RecallAttributedResult({
    required this.queryClass,
    required this.query,
    required this.rank,
    required this.fileName,
    required this.score,
    required this.fieldContributions,
    required this.contributionsSum,
    required this.contributionsMatchScore,
    required this.isExpectation,
    required this.tiedWithNeighbour,
  });

  final RecallQueryClass queryClass;
  final String query;

  /// 1-based, in the order `search()` returned it.
  final int rank;

  final String fileName;

  /// The total `search()` ranked this record on.
  final int score;

  /// Field -> weight units that field earned for this query. A field missing
  /// from the map earned nothing.
  final Map<String, int> fieldContributions;

  /// [fieldContributions] summed.
  final int contributionsSum;

  /// Whether [contributionsSum] equals [score].
  final bool contributionsMatchScore;

  /// Whether this result is one the observation was looking for. Attribution of
  /// *any* result and attribution of the *right* result are different questions,
  /// so this is tracked separately.
  final bool isExpectation;

  /// Whether an adjacent result in the same list has the identical score.
  ///
  /// The sort has no tiebreak and Dart does not specify [List.sort] as stable,
  /// so a tied rank is not decided by the score at all -- it is decided by
  /// whichever order the sort happened to produce. Recorded per row so the
  /// report can say how much of the top 10 was decided by something other than
  /// weight, instead of printing a tie caveat nobody can size.
  final bool tiedWithNeighbour;

  Map<String, Object?> toJson() => <String, Object?>{
        'queryClass': queryClass.name,
        'query': query,
        'rank': rank,
        'fileName': fileName,
        'score': score,
        'fieldContributions': fieldContributions,
        'contributionsSum': contributionsSum,
        'contributionsMatchScore': contributionsMatchScore,
        'isExpectation': isExpectation,
        'tiedWithNeighbour': tiedWithNeighbour,
      };
}

/// The per-field contribution distribution over a set of
/// [RecallAttributedResult]s.
///
/// Three views, because they answer three different questions and only one of
/// them is the headline:
///
///   * **top-10 slots** — every result that ranked 1..10 for a query. What the
///     ranking was made of.
///   * **rank-1 slots** — the same for first place alone.
///   * **expectations in the top 10** — only the records the observation was
///     looking for, when they landed in the top 10. What the *right answers*
///     were made of, which is the narrower and more damning number.
///
/// A slot credits a field when that field earned a non-zero weight for that
/// result, so one slot can credit several fields and the slot shares do not sum
/// to 100%. The unit shares are over the summed scores instead, and they do.
class RecallFieldAttribution {
  RecallFieldAttribution.from(List<RecallAttributedResult> rows) {
    for (final RecallAttributedResult r in rows) {
      queries.add(r.query);
      results++;
      if (!r.contributionsMatchScore) mismatchedResults++;
      if (r.rank > 10) continue;
      top10Slots++;
      top10Units += r.score;
      if (r.tiedWithNeighbour) tiedTop10Slots++;
      _tally(top10SlotsByField, top10UnitsByField, r);
      if (r.rank == 1) {
        top1Slots++;
        top1Units += r.score;
        _tally(top1SlotsByField, top1UnitsByField, r);
      }
      if (r.isExpectation) {
        expectationsInTop10++;
        expectationUnitsInTop10 += r.score;
        _tally(expectationSlotsByField, expectationUnitsByField, r);
      }
    }
    for (final Map<String, int> m in <Map<String, int>>[
      top10SlotsByField,
      top10UnitsByField,
      top1SlotsByField,
      top1UnitsByField,
      expectationSlotsByField,
      expectationUnitsByField,
    ]) {
      fieldsSeen.addAll(m.keys);
    }
  }

  final Set<String> queries = <String>{};

  /// Result rows read, at every rank — not just the top 10.
  int results = 0;

  /// Result rows that ranked 1..10 for their query.
  int top10Slots = 0;

  /// [top10Slots]' scores summed.
  int top10Units = 0;

  int top1Slots = 0;
  int top1Units = 0;

  /// Rows that were the observation's own expectation and landed in the top 10.
  /// Equals the class's hitAt10 count, and is reported next to the distribution
  /// so "which field won the ranking" can be read against "which field won the
  /// query".
  int expectationsInTop10 = 0;
  int expectationUnitsInTop10 = 0;

  /// Results whose per-field split did not sum to their score. Any non-zero
  /// value means part of every distribution below is unaccounted for.
  int mismatchedResults = 0;

  /// Top-10 slots that shared a score with a neighbour in the same result
  /// list. Their rank was not decided by the weights at all -- see
  /// [RecallAttributedResult.tiedWithNeighbour].
  int tiedTop10Slots = 0;

  final Map<String, int> top10SlotsByField = <String, int>{};
  final Map<String, int> top10UnitsByField = <String, int>{};
  final Map<String, int> top1SlotsByField = <String, int>{};
  final Map<String, int> top1UnitsByField = <String, int>{};
  final Map<String, int> expectationSlotsByField = <String, int>{};
  final Map<String, int> expectationUnitsByField = <String, int>{};
  final Set<String> fieldsSeen = <String>{};

  static void _tally(
    Map<String, int> slots,
    Map<String, int> units,
    RecallAttributedResult r,
  ) {
    r.fieldContributions.forEach((String field, int units_) {
      slots[field] = (slots[field] ?? 0) + 1;
      units[field] = (units[field] ?? 0) + units_;
    });
  }

  /// Fields the indexer weights that earned nothing in any top-10 slot.
  ///
  /// Enumerated from [recallIndexedFieldNames], not from what was seen, so this
  /// is a real answer and not an artefact of the observation set. A field here
  /// holds weight units that have never decided a rank.
  ///
  /// A non-empty list is NOT automatically a bug. `description`, `searchKeywords`,
  /// `recognitions` and `extractedData` are empty on records seeded through
  /// `addFromBulkIngest`, which is the only write path this harness exercises --
  /// but `_seedCorpus` does not clear the box, so a run against a library with
  /// pre-existing records can legitimately see those legacy Hive rows credit
  /// these fields, and non-zero contribution is then the CORRECT reading of the
  /// data in front of it.
  List<String> get zeroContributionFields => recallIndexedFieldNames
      .where((String f) => (top10SlotsByField[f] ?? 0) == 0)
      .toList();

  /// Fields the live index attributed to that the declared weight table does not
  /// list. Empty in a healthy run; non-empty means the declared table is stale,
  /// which moves [declaredIndexConfigHash] but not [indexBehaviourHash].
  List<String> get fieldsOutsideDeclaredTable => (fieldsSeen.toList()..sort())
      .where((String f) => !declaredIndexWeights.containsKey(f))
      .toList();

  /// Fields ordered by top-10 slot count, then by unit count, then by name, so
  /// the ranking is deterministic.
  List<String> get rankedFields {
    final List<String> all = <String>{
      ...recallIndexedFieldNames,
      ...fieldsSeen,
    }.toList();
    all.sort((String a, String b) {
      final int sa = top10SlotsByField[a] ?? 0;
      final int sb = top10SlotsByField[b] ?? 0;
      if (sa != sb) return sb.compareTo(sa);
      final int ua = top10UnitsByField[a] ?? 0;
      final int ub = top10UnitsByField[b] ?? 0;
      if (ua != ub) return ub.compareTo(ua);
      return a.compareTo(b);
    });
    return all;
  }

  double? _share(String field, Map<String, int> m, int denominator) =>
      denominator == 0 ? null : (m[field] ?? 0) / denominator;

  /// Share of the top-10 slots [field] contributed to. Null when there were no
  /// top-10 slots at all, so "nothing was measured" never prints as 0%.
  double? slotShareAt10(String field) =>
      _share(field, top10SlotsByField, top10Slots);

  /// Share of the summed top-10 score [field] earned.
  double? unitShareAt10(String field) =>
      _share(field, top10UnitsByField, top10Units);

  double? slotShareAt1(String field) =>
      _share(field, top1SlotsByField, top1Slots);

  double? unitShareAt1(String field) =>
      _share(field, top1UnitsByField, top1Units);

  double? expectationSlotShare(String field) =>
      _share(field, expectationSlotsByField, expectationsInTop10);

  Map<String, Object?> toJson() => <String, Object?>{
        'queries': queries.length,
        'results': results,
        'top10Slots': top10Slots,
        'top10Units': top10Units,
        'top1Slots': top1Slots,
        'top1Units': top1Units,
        'expectationsInTop10': expectationsInTop10,
        'expectationUnitsInTop10': expectationUnitsInTop10,
        'mismatchedResults': mismatchedResults,
        'tiedTop10Slots': tiedTop10Slots,
        'tiedTop10SlotShare':
            top10Slots == 0 ? null : tiedTop10Slots / top10Slots,
        'zeroContributionFields': zeroContributionFields,
        'fieldsOutsideDeclaredTable': fieldsOutsideDeclaredTable,
        'byField': <Map<String, Object?>>[
          for (final String f in rankedFields)
            <String, Object?>{
              'field': f,
              'top10Slots': top10SlotsByField[f] ?? 0,
              'top10SlotShare': slotShareAt10(f),
              'top10Units': top10UnitsByField[f] ?? 0,
              'top10UnitShare': unitShareAt10(f),
              'top1Slots': top1SlotsByField[f] ?? 0,
              'top1SlotShare': slotShareAt1(f),
              'top1Units': top1UnitsByField[f] ?? 0,
              'top1UnitShare': unitShareAt1(f),
              'expectationSlots': expectationSlotsByField[f] ?? 0,
              'expectationSlotShare': expectationSlotShare(f),
              'expectationUnits': expectationUnitsByField[f] ?? 0,
            },
        ],
      };
}

// ============================================================================
// Semantic queries
// ============================================================================

/// One hand-labelled line of the semantic query file.
class RecallSemanticQuery {
  const RecallSemanticQuery({required this.q, required this.expect, this.line});

  final String q;
  final List<String> expect;

  /// 1-based source line, for error messages.
  final int? line;
}

/// A line that could not be used, kept so the report can name it instead of
/// dropping it silently.
class RecallSemanticParseIssue {
  const RecallSemanticParseIssue({required this.line, required this.reason});

  final int line;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'line': line,
        'reason': reason,
      };
}

// ============================================================================
// The report
// ============================================================================

/// Everything one harness run produced. Serialized verbatim to
/// `build/recall_report.json`, so this shape is the contract.
///
/// Not `const` only because [reportWritten] is assigned after the file lands;
/// the constructor is otherwise the same immutable value type.
class RecallReport {
  RecallReport({
    required this.timestamp,
    required this.mode,
    required this.corpusLabel,
    required this.corpusSize,
    required this.corpusHash,
    required this.declaredIndexConfigHash,
    required this.declaredIndexConfigCanonical,
    required this.indexBehaviourHash,
    required this.behaviourCanary,
    required this.discriminativenessCutoff,
    required this.tokensConsidered,
    required this.distinctTokensSeen,
    required this.retainedTokens,
    required this.probesRetained,
    required this.droppedUnqueryable,
    required this.droppedNonDiscriminative,
    required this.multiOwnerProbes,
    required this.numericProbes,
    required this.lexicalMetrics,
    required this.lexicalObservations,
    required this.fieldPolicy,
    required this.semanticStatus,
    required this.semanticMetrics,
    required this.semanticObservations,
    required this.semanticParseIssues,
    required this.semanticUnknownExpectations,
    required this.semanticSource,
    required this.attributionResults,
    required this.lexicalAttribution,
    required this.semanticAttribution,
    required this.warnings,
    required this.textReport,
    required this.reportPath,
    required this.reportWritten,
  });

  final String timestamp;
  final RecallCorpusMode mode;
  final String corpusLabel;
  final int corpusSize;

  /// Identifies the records that went in.
  final String corpusHash;

  /// Identifies the weights and tokenizer the harness *declared* it was
  /// measuring. Not an observation of `lib/` -- see the header.
  final String declaredIndexConfigHash;
  final String declaredIndexConfigCanonical;

  /// Identifies what the live index actually did. The one that moves when a
  /// weight in `lib/` changes.
  final String indexBehaviourHash;
  final List<Map<String, Object?>> behaviourCanary;

  final int discriminativenessCutoff;
  final int tokensConsidered;
  final int distinctTokensSeen;

  /// Distinct token strings that became probes. The denominator; see
  /// [RecallProbeDerivation.retainedTokens] for why it can be lower than
  /// [probesRetained].
  final int retainedTokens;
  final int probesRetained;
  final int droppedUnqueryable;
  final int droppedNonDiscriminative;
  final int multiOwnerProbes;

  /// Retained probes whose token is all digits. Reported, never filtered: see
  /// [RecallProbeDerivation.numericProbes] for why they inflate recall@1.
  final int numericProbes;

  final RecallMetrics lexicalMetrics;
  final List<RecallObservation> lexicalObservations;
  final RecallFieldPolicy fieldPolicy;

  /// `not supplied`, `measured`, or a reason it could not be read.
  final String semanticStatus;
  final RecallMetrics? semanticMetrics;
  final List<RecallObservation> semanticObservations;
  final List<RecallSemanticParseIssue> semanticParseIssues;
  final List<String> semanticUnknownExpectations;
  final String semanticSource;

  /// Every measured result with its per-field score breakdown. Class 1 rows
  /// first, then class 2, each tagged with [RecallAttributedResult.queryClass].
  final List<RecallAttributedResult> attributionResults;

  /// The distribution over class 1 alone.
  final RecallFieldAttribution lexicalAttribution;

  /// The distribution over class 2, or null when no semantic query file was
  /// supplied. Never folded into [lexicalAttribution].
  final RecallFieldAttribution? semanticAttribution;

  final List<String> warnings;

  /// The same text that was printed, so the JSON can be diffed without
  /// re-running the harness.
  final String textReport;

  final String reportPath;

  /// Whether the JSON artifact actually landed on disk. Not part of `toJson()`
  /// -- if you are reading the JSON, it was written.
  bool reportWritten;

  Map<String, Object?> toJson() => <String, Object?>{
        'tool': 'sift-recall-harness',
        'schemaVersion': recallReportSchemaVersion,
        'timestamp': timestamp,
        'mode': mode.name,
        'modeLabel': mode.label,
        'corpus': <String, Object?>{
          'label': corpusLabel,
          'size': corpusSize,
          'hash': corpusHash,
        },
        'indexFingerprint': <String, Object?>{
          'declaredIndexConfigHash': declaredIndexConfigHash,
          'declaredIndexConfigCanonical': declaredIndexConfigCanonical,
          'declaredWeights': declaredIndexWeights,
          'declaredTokenizer': declaredTokenizerConfig,
          'indexBehaviourHash': indexBehaviourHash,
          'behaviourCanary': behaviourCanary,
          'caveat': 'declaredIndexConfigHash mirrors private constants in '
              'lib/providers/screenshot_provider.dart and does NOT move when '
              'they change. indexBehaviourHash is observed from the live '
              'search() and does.',
        },
        'lexicalProbes': <String, Object?>{
          'discriminativenessCutoff': discriminativenessCutoff,
          'tokensConsidered': tokensConsidered,
          'distinctTokensSeen': distinctTokensSeen,
          'retainedTokens': retainedTokens,
          'probesRetained': probesRetained,
          'droppedUnqueryable': droppedUnqueryable,
          'droppedNonDiscriminative': droppedNonDiscriminative,
          'multiOwnerProbes': multiOwnerProbes,
          'numericProbes': numericProbes,
          'metrics': lexicalMetrics.toJson(),
          'fieldPolicy': fieldPolicy.toJson(),
          'perProbe': lexicalObservations
              .map((RecallObservation o) => o.toJson())
              .toList(),
        },
        'semanticQueries': <String, Object?>{
          'status': semanticStatus,
          'source': semanticSource,
          'metrics': semanticMetrics?.toJson(),
          'parseIssues': semanticParseIssues
              .map((RecallSemanticParseIssue i) => i.toJson())
              .toList(),
          'unknownExpectations': semanticUnknownExpectations,
          'perQuery': semanticObservations
              .map((RecallObservation o) => o.toJson())
              .toList(),
        },
        // Phase 0 item 2: WHICH FIELDS produced each hit. Read from
        // ScreenshotProvider.explainScores(), which shares its scoring path
        // with search(), so these totals are the scores the ranking used.
        'scoreAttribution': <String, Object?>{
          'method': 'ScreenshotProvider.explainScores(), which calls the same '
              'private scorer as search(). Each row\'s `score` is the score '
              'that produced its rank; `fieldContributions` is that score '
              'decomposed back to the fields that earned it.',
          'caveat': 'A slot credits a field when the field earned a non-zero '
              'weight for that result, so slot shares across fields do not sum '
              'to 100%. Unit shares are over summed scores and do. A slot says '
              'what a result was made of, not why it beat its neighbour: with '
              'no tiebreak in the sort, two equal-score results are '
              'indistinguishable here.',
          'indexedFieldNames': recallIndexedFieldNames,
          'lexical': lexicalAttribution.toJson(),
          'semantic': semanticAttribution?.toJson(),
          'perResult': attributionResults
              .map((RecallAttributedResult r) => r.toJson())
              .toList(),
        },
        'warnings': warnings,
        'reportPath': reportPath,
      };
}

// ============================================================================
// The harness
// ============================================================================

/// Runs the recall measurement and reports it twice: as text on stdout, where
/// `flutter test` shows it, and as JSON at [reportPath], where a later run can
/// diff it.
///
/// Reusable on purpose. Phase 1 and Phase 2 are supposed to change the index and
/// re-run *this* measurement, so the only things that may differ between a
/// baseline and a candidate are the index and the corpus -- never the
/// measurement.
///
/// Requires `Hive.init()` to have been called by the caller, matching every
/// other provider test in this repo. The harness opens the `screenshots` box if
/// it is not already open, and never closes it.
///
/// The box is not cleared first, so a caller that opens a box already holding a
/// real library measures that library plus the seeded corpus. This matters for
/// one report field in particular: `description`, `searchKeywords`,
/// `recognitions` and `extractedData` are empty on everything seeded through
/// `addFromBulkIngest`, but a legacy Hive row written by an older build may
/// carry them. A run over such a library can legitimately report non-zero
/// contribution from those fields, and that is CORRECT behaviour, not a bug --
/// it means the report is describing real records that really do hold that
/// content.
class RecallHarness {
  RecallHarness({
    required this.corpus,
    this.discriminativenessCutoff = defaultDiscriminativenessCutoff,
    this.semanticQueriesPath = defaultSemanticQueriesPath,
    this.reportPath = defaultRecallReportPath,
    this.emit,
    this.now,
  });

  final RecallCorpus corpus;

  /// Maximum records one token may appear in to survive as a probe.
  final int discriminativenessCutoff;

  /// Class-2 query file. Absent file means class 2 is reported as not supplied.
  final String semanticQueriesPath;

  /// Where the JSON report is written.
  final String reportPath;

  /// Line sink. Defaults to stdout; a test passes a collector so it can assert
  /// on the wording.
  final void Function(String)? emit;

  /// Clock, injectable so a report can be made byte-stable in a test.
  final DateTime Function()? now;

  static final RegExp _pathUnsafe = RegExp(r'[^A-Za-z0-9.-]+');

  /// A token that is nothing but ASCII digits -- a date half, a time, a price.
  static final RegExp _allDigits = RegExp(r'^[0-9]+$');

  /// Probes are measured over a full-length result list so ranks and the median
  /// are real; the reported cut-offs are @1/@5/@10.
  int get _resultLimit => corpus.records.length + 1;

  void _say(String line) => (emit ?? _defaultEmit)(line);

  // ignore: avoid_print
  void _defaultEmit(String line) => print(line);

  // -- entry point ----------------------------------------------------------

  /// Measure, report, and return the report. The single entry point: Phase 1
  /// and Phase 2 call exactly this, with a different corpus if they need one.
  Future<RecallReport> run() async {
    final List<String> warnings = <String>[];
    if (corpus.isFixture) {
      warnings.add(
        'FIXTURE MODE. Every record in this corpus is a hand-written string in '
        'test/support/recall_fixture_corpus.dart. The numbers below describe '
        'that list and nothing else -- they are not a baseline for this user\'s '
        'library and must not be quoted as one. The real corpus is a directory '
        'of images plus a corpus.jsonl sidecar; see the header of '
        'test/support/recall_harness.dart for the format.',
      );
    }

    final ScreenshotProvider provider = await _seedCorpus(warnings);
    final RecallFieldPolicy fieldPolicy = _inspectFieldPolicy(provider);
    final RecallProbeDerivation derivation = deriveProbes();

    final List<RecallObservation> lexical = <RecallObservation>[];
    final List<RecallAttributedResult> lexicalRows = <RecallAttributedResult>[];
    for (final RecallProbe probe in derivation.probes) {
      final List<String> hits = _search(provider, probe.token);
      final int at = hits.indexOf(probe.ownerFileName);
      lexical.add(RecallObservation(
        query: probe.token,
        expectations: <String>[probe.ownerFileName],
        returnedFileNames: hits,
        bestRank: at < 0 ? null : at + 1,
        probe: probe,
      ));
      lexicalRows.addAll(_attribute(
        provider,
        probe.token,
        hits,
        queryClass: RecallQueryClass.lexical,
        expectations: <String>{probe.ownerFileName},
        warnings: warnings,
      ));
    }
    final RecallMetrics lexicalMetrics = RecallMetrics(lexical);

    if (derivation.numericProbes > 0) {
      warnings.add(
        '${derivation.numericProbes} of the ${derivation.probes.length} '
        'retained probes are bare numbers -- timestamps, seat numbers, prices. '
        'They are counted, not filtered: they really are in the index and '
        'really are discriminative, so excluding them would hide a property of '
        'it. But nobody types "14" to find a screenshot, so every hit they '
        'produce lifts recall@1 without corresponding to a query a user would '
        'make. Discount the class-1 headline by this much, and read class 2 '
        'for what a real query scores.',
      );
    }

    final _SemanticRun semantic = await _runSemantic(provider, warnings);

    final RecallFieldAttribution lexicalAttribution =
        RecallFieldAttribution.from(lexicalRows);
    final RecallFieldAttribution? semanticAttribution =
        semantic.attribution == null
            ? null
            : RecallFieldAttribution.from(semantic.attribution!);

    // The decomposition is checked, not assumed. If any result's per-field
    // weights fail to add up to the score that ranked it, part of every
    // distribution below is unaccounted for and the report has to say so rather
    // than present a partial split as a complete one.
    final int mismatched = lexicalAttribution.mismatchedResults +
        (semanticAttribution?.mismatchedResults ?? 0);
    if (mismatched > 0) {
      warnings.add(
        '$mismatched measured results had a per-field score split that did NOT '
        'sum to the score search() ranked them on. The attribution below is '
        'therefore incomplete for those results -- most likely a write path is '
        'indexing a field the split does not know about. Treat the '
        'distribution as a lower bound, not a decomposition.',
      );
    }
    final List<String> undeclared =
        lexicalAttribution.fieldsOutsideDeclaredTable;
    if (undeclared.isNotEmpty) {
      warnings.add(
        'The live index attributed hits to fields the harness\'s declared '
        'weight table does not list: ${undeclared.join(', ')}. '
        'declaredIndexConfigHash is therefore stale while indexBehaviourHash '
        'is not.',
      );
    }

    final List<Map<String, Object?>> canary =
        _behaviourCanary(provider, derivation.probes);
    final String behaviourHash = recallStableHash(<String>[
      'recall-behaviour-v1',
      for (final Map<String, Object?> row in canary)
        '${row['query']}=>${(row['returned']! as List<String>).join('|')}',
    ]);
    final String configCanonical = _canonicalIndexConfig();

    final String text = _renderText(
      derivation: derivation,
      lexical: lexical,
      fieldPolicy: fieldPolicy,
      semantic: semantic,
      canary: canary,
      configCanonical: configCanonical,
      behaviourHash: behaviourHash,
      lexicalAttribution: lexicalAttribution,
      semanticAttribution: semanticAttribution,
      warnings: warnings,
    );
    for (final String line in text.split('\n')) {
      _say(line);
    }

    final RecallReport report = RecallReport(
      timestamp: (now ?? DateTime.now)().toUtc().toIso8601String(),
      mode: corpus.mode,
      corpusLabel: corpus.label,
      corpusSize: corpus.records.length,
      corpusHash: corpus.hash,
      declaredIndexConfigHash: recallStableHash(<String>[configCanonical]),
      declaredIndexConfigCanonical: configCanonical,
      indexBehaviourHash: behaviourHash,
      behaviourCanary: canary,
      discriminativenessCutoff: discriminativenessCutoff,
      tokensConsidered: derivation.tokensConsidered,
      distinctTokensSeen: derivation.distinctTokensSeen,
      retainedTokens: derivation.retainedTokens,
      probesRetained: derivation.probes.length,
      droppedUnqueryable: derivation.droppedUnqueryable,
      droppedNonDiscriminative: derivation.droppedNonDiscriminative,
      multiOwnerProbes: derivation.multiOwnerProbes,
      numericProbes: derivation.numericProbes,
      lexicalMetrics: lexicalMetrics,
      lexicalObservations: lexical,
      fieldPolicy: fieldPolicy,
      semanticStatus: semantic.status,
      semanticMetrics: semantic.metrics,
      semanticObservations: semantic.observations,
      semanticParseIssues: semantic.issues,
      semanticUnknownExpectations: semantic.unknownExpectations,
      semanticSource: semanticQueriesPath,
      attributionResults: <RecallAttributedResult>[
        ...lexicalRows,
        ...?semantic.attribution,
      ],
      lexicalAttribution: lexicalAttribution,
      semanticAttribution: semanticAttribution,
      warnings: warnings,
      textReport: text,
      reportPath: reportPath,
      reportWritten: false,
    );

    report.reportWritten = await _writeJson(report.toJson());
    if (!report.reportWritten) {
      warnings.add('Could not write the JSON report to $reportPath.');
      _say('  ! could not write $reportPath');
    }

    return report;
  }

  // -- real mode ------------------------------------------------------------

  /// Load a real corpus from [imageDirectory] plus its sidecar, then measure it.
  ///
  /// Returns null when [imageDirectory] does not exist. That is the entire
  /// "not configured" behaviour, so a caller skips with a null check and never
  /// has to distinguish "no corpus" from "an error".
  ///
  /// The sidecar format is documented at the top of this file. [sidecar]
  /// defaults to `corpus.jsonl` inside [imageDirectory].
  static Future<RecallReport?> runRealRecall({
    required Directory imageDirectory,
    File? sidecar,
    int discriminativenessCutoff = defaultDiscriminativenessCutoff,
    String semanticQueriesPath = defaultSemanticQueriesPath,
    String reportPath = defaultRecallReportPath,
    void Function(String)? emit,
    DateTime Function()? now,
  }) async {
    if (!await imageDirectory.exists()) return null;
    final RecallCorpus corpus =
        realCorpusFromDirectory(imageDirectory, sidecar: sidecar);
    return RecallHarness(
      corpus: corpus,
      discriminativenessCutoff: discriminativenessCutoff,
      semanticQueriesPath: semanticQueriesPath,
      reportPath: reportPath,
      emit: emit,
      now: now,
    ).run();
  }

  /// Read a real corpus: every image in [imageDirectory] described by one line
  /// of the sidecar.
  ///
  /// Throws [StateError] when the sidecar is missing, when a line is not a JSON
  /// object, or when a line names a file that is not in the directory. All
  /// loud on purpose -- a sidecar that quietly describes three of the four
  /// hundred screenshots would produce a baseline that looks fine and measures
  /// almost nothing.
  static RecallCorpus realCorpusFromDirectory(
    Directory imageDirectory, {
    File? sidecar,
  }) {
    final File file = sidecar ??
        File('${imageDirectory.path}${Platform.pathSeparator}corpus.jsonl');
    if (!file.existsSync()) {
      throw StateError(
        'Real corpus sidecar not found: ${file.path}. See the header of '
        'test/support/recall_harness.dart for the expected JSONL format.',
      );
    }

    final Set<String> present = imageDirectory
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toSet();

    final List<RecallCorpusRecord> records = <RecallCorpusRecord>[];
    final Set<String> seen = <String>{};
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      final Object? decoded = _tryDecode(line);
      if (decoded is! Map) {
        throw StateError(
          'Sidecar ${file.path} line ${i + 1} is not a JSON object.',
        );
      }
      final Object? name = decoded['fileName'];
      if (name is! String || name.isEmpty) {
        throw StateError(
          'Sidecar ${file.path} line ${i + 1} has no "fileName".',
        );
      }
      if (!present.contains(name)) {
        throw StateError(
          'Sidecar ${file.path} line ${i + 1} names "$name", which is not a '
          'file in ${imageDirectory.path}.',
        );
      }
      if (!seen.add(name)) {
        throw StateError(
          'Sidecar ${file.path} describes "$name" more than once.',
        );
      }
      records.add(RecallCorpusRecord(
        fileName: name,
        ocrText: _optionalString(decoded['ocrText']),
        tags: _stringList(decoded['tags']),
        objects: _stringList(decoded['objects']),
        summary: _optionalString(decoded['summary']),
      ));
    }

    return RecallCorpus(
      label: imageDirectory.path,
      records: records,
      mode: RecallCorpusMode.real,
    );
  }

  // -- seeding --------------------------------------------------------------

  /// Write every record through the two production calls the app makes, so the
  /// summary slice, the placeholder, the OCR cap, the constant `lamType`, the
  /// label dedupe and the per-field weight rule all stay in `lib/`.
  Future<ScreenshotProvider> _seedCorpus(List<String> warnings) async {
    if (!Hive.isBoxOpen(recallHarnessHiveBox)) {
      await Hive.openBox(recallHarnessHiveBox);
    }
    final ScreenshotProvider provider = ScreenshotProvider(
      // No ML Kit: the harness never calls analyze(), and the override keeps
      // that true if a future write path does.
      ocr: OCRService(extractOverride: (_) async => ''),
    );

    for (int i = 0; i < corpus.records.length; i++) {
      final RecallCorpusRecord r = corpus.records[i];
      // Unique per record, forward slashes so the provider's basename split
      // works on Windows, and a slug the report can print readably.
      final String slug =
          r.fileName.replaceAllMapped(_pathUnsafe, (Match _) => '_');
      final String path = '/${corpus.hash.substring(0, 8)}/$i/$slug';
      final String? id = await provider.addFromBulkIngest(
        path: path,
        // Distinct and ordered, so provider insertion order is deterministic.
        capturedAt: DateTime.utc(2026).add(Duration(minutes: i)),
        ocrText: r.ocrText ?? '',
        objects: r.objects,
      );
      if (id == null) {
        throw StateError(
          'Corpus record "${r.fileName}" was rejected by the production '
          'write path.',
        );
      }
      for (final String tag in r.tags) {
        // addTag refuses a tag the record already carries. That is a corpus
        // bug, not an index failure, so it is reported rather than thrown --
        // but it does mean the record is not what the corpus said it was.
        final bool tagged = await provider.addTag(id, tag);
        if (!tagged) {
          warnings.add('Tag "$tag" was not applied to "${r.fileName}".');
        }
      }
    }
    return provider;
  }

  /// Confirm, against the records just written, the claims the harness makes
  /// about which fields carry content.
  ///
  /// "Just written" is the scope limit: this walks what `_seedCorpus` put in the
  /// box via `addFromBulkIngest`, and `processScreenshot` is never called. So
  /// [neverPopulatedConfirmed] going false means a seeded record carried one of
  /// the four fields -- not that any write path in the app was caught changing.
  RecallFieldPolicy _inspectFieldPolicy(ScreenshotProvider provider) {
    bool neverPopulated = true;
    final Set<String> lamTypes = <String>{};
    int placeholders = 0;
    final Map<String, String> storedSummary = <String, String>{};

    for (final Screenshot s in provider.screenshots) {
      if (s.description != null || s.searchKeywords.isNotEmpty) {
        neverPopulated = false;
      }
      if (s.recognitions.isNotEmpty || s.extractedData != null) {
        neverPopulated = false;
      }
      lamTypes.add(s.lamType ?? '');
      final String summary = s.summary ?? '';
      storedSummary[s.fileName] = summary;
      if (summary.toLowerCase() == noTextFoundPlaceholder) placeholders++;
    }

    final List<String> mismatches = <String>[];
    for (final RecallCorpusRecord r in corpus.records) {
      final String? declared = r.summary;
      final String? stored = storedSummary[r.fileName];
      if (declared == null || stored == null) continue;
      if (stored.toLowerCase() == noTextFoundPlaceholder) continue;
      if (stored.trim() != declared.trim()) {
        mismatches.add(
          '${r.fileName}: sidecar declares "$declared", production derives '
          '"${stored.trim()}"',
        );
      }
    }

    return RecallFieldPolicy(
      probed: RecallFieldPolicy.probedFields,
      skipped: RecallFieldPolicy.skippedFields,
      neverPopulatedConfirmed: neverPopulated,
      lamTypeValues: lamTypes.toList()..sort(),
      placeholderSummaryCount: placeholders,
      summaryMismatches: mismatches,
    );
  }

  // -- probe derivation -----------------------------------------------------

  /// Derive the class-1 probes from the corpus alone. Public so a test can
  /// inspect what the filter kept and what it threw away without running a full
  /// measurement.
  RecallProbeDerivation deriveProbes() {
    // token -> records holding that exact token.
    final Map<String, Set<String>> owners = <String, Set<String>>{};
    // record -> every token its probed fields contribute, so prefix broadening
    // can be counted without re-tokenizing.
    final Map<String, List<String>> perRecord = <String, List<String>>{};
    // token -> record -> which probed field carried it.
    final Map<String, Map<String, Set<String>>> origin =
        <String, Map<String, Set<String>>>{};

    int considered = 0;
    int unqueryable = 0;

    for (final RecallCorpusRecord r in corpus.records) {
      final List<String> all = <String>[];
      for (final String field in RecallFieldPolicy.probedFields) {
        final String? raw = _fieldValue(r, field);
        if (raw == null) continue;
        // A whole-field placeholder is display-only and reaches the index
        // nowhere; skip it rather than re-implementing the gate.
        if (raw.trim().toLowerCase() == noTextFoundPlaceholder) continue;
        // The indexer caps the OCR blob. Tokens past the cap are in the record
        // but not in the index, so they are not probes.
        final String text = raw.length > recallOcrBlobCap
            ? raw.substring(0, recallOcrBlobCap)
            : raw;
        // Deduped per field, mirroring the once-per-(term, field) weight rule:
        // a token repeated inside one field is one piece of evidence.
        for (final String token in recallTokens(text).toSet()) {
          all.add(token);
          (owners[token] ??= <String>{}).add(r.fileName);
          final Map<String, Set<String>> byRecord =
              origin[token] ??= <String, Set<String>>{};
          (byRecord[r.fileName] ??= <String>{}).add(field);
          considered++;
        }
      }
      perRecord[r.fileName] = all;
    }

    // Prefix broadening: the records `search()` can actually reach.
    int matchCount(String token) {
      int n = 0;
      for (final List<String> tokens in perRecord.values) {
        if (tokens.any((String t) => t.startsWith(token))) n++;
      }
      return n;
    }

    final List<RecallProbe> probes = <RecallProbe>[];
    int nonDiscriminative = 0;
    int multiOwner = 0;
    int retained = 0;
    int numeric = 0;

    // Sorted, so the probe list -- and therefore the report, the JSON and the
    // behaviour canary -- is identical on every machine.
    final List<String> sorted = owners.keys.toList()..sort();
    for (final String token in sorted) {
      if (!recallTokenIsQueryable(token)) {
        unqueryable++;
        continue;
      }
      final List<String> names = owners[token]!.toList()..sort();
      if (names.length > discriminativenessCutoff) {
        nonDiscriminative++;
        continue;
      }
      if (names.length > 1) multiOwner++;
      retained++;
      if (_allDigits.hasMatch(token)) numeric++;
      final int matches = matchCount(token);
      for (final String name in names) {
        probes.add(RecallProbe(
          token: token,
          ownerFileName: name,
          ownerCount: names.length,
          matchCount: matches,
          sourceFields: (origin[token]![name]!).toList()..sort(),
        ));
      }
    }

    return RecallProbeDerivation(
      probes: probes,
      tokensConsidered: considered,
      distinctTokensSeen: owners.length,
      retainedTokens: retained,
      droppedUnqueryable: unqueryable,
      droppedNonDiscriminative: nonDiscriminative,
      multiOwnerProbes: multiOwner,
      numericProbes: numeric,
    );
  }

  String? _fieldValue(RecallCorpusRecord r, String field) {
    switch (field) {
      case 'ocrText':
        return r.ocrText;
      case 'objects':
        return r.objects.isEmpty ? null : r.objects.join(' ');
      case 'tags':
        return r.tags.isEmpty ? null : r.tags.join(' ');
      case 'summary':
        return r.summary;
      case 'fileName':
        return r.fileName;
      default:
        return null;
    }
  }

  // -- semantic queries -----------------------------------------------------

  Future<_SemanticRun> _runSemantic(
    ScreenshotProvider provider,
    List<String> warnings,
  ) async {
    final File file = File(semanticQueriesPath);
    if (!await file.exists()) {
      return const _SemanticRun(
        status: 'not supplied',
        metrics: null,
        observations: <RecallObservation>[],
        issues: <RecallSemanticParseIssue>[],
        unknownExpectations: <String>[],
        attribution: null,
      );
    }

    final List<RecallSemanticQuery> queries = <RecallSemanticQuery>[];
    final List<RecallSemanticParseIssue> issues = <RecallSemanticParseIssue>[];
    final List<String> lines = await file.readAsLines();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      final Object? decoded = _tryDecode(line);
      if (decoded is! Map) {
        issues.add(RecallSemanticParseIssue(
          line: i + 1,
          reason: 'not a JSON object',
        ));
        continue;
      }
      final Object? q = decoded['q'];
      if (q is! String || q.trim().isEmpty) {
        issues.add(RecallSemanticParseIssue(
          line: i + 1,
          reason: 'missing or empty "q"',
        ));
        continue;
      }
      final List<String> expects = _stringList(decoded['expect']);
      if (expects.isEmpty) {
        issues.add(RecallSemanticParseIssue(
          line: i + 1,
          reason: 'missing or empty "expect"',
        ));
        continue;
      }
      queries.add(RecallSemanticQuery(
        q: q.trim(),
        expect: expects,
        line: i + 1,
      ));
    }

    if (queries.isEmpty) {
      return _SemanticRun(
        status: 'empty -- no usable lines in $semanticQueriesPath',
        metrics: null,
        observations: const <RecallObservation>[],
        issues: issues,
        unknownExpectations: const <String>[],
        attribution: const <RecallAttributedResult>[],
      );
    }

    final Set<String> corpusNames =
        corpus.records.map((RecallCorpusRecord r) => r.fileName).toSet();
    final List<String> unknown = <String>[];
    final List<RecallObservation> observations = <RecallObservation>[];
    final List<RecallAttributedResult> attribution = <RecallAttributedResult>[];
    for (final RecallSemanticQuery query in queries) {
      for (final String e in query.expect) {
        if (!corpusNames.contains(e) && !unknown.contains(e)) {
          unknown.add(e);
        }
      }
      final List<String> hits = _search(provider, query.q);
      int best = 0;
      for (final String e in query.expect) {
        final int at = hits.indexOf(e);
        if (at >= 0 && (best == 0 || at < best)) best = at + 1;
      }
      observations.add(RecallObservation(
        query: query.q,
        expectations: query.expect,
        returnedFileNames: hits,
        bestRank: best == 0 ? null : best,
      ));
      attribution.addAll(_attribute(
        provider,
        query.q,
        hits,
        queryClass: RecallQueryClass.semantic,
        expectations: query.expect.toSet(),
        warnings: warnings,
      ));
    }
    if (unknown.isNotEmpty) {
      // Kept in the metrics on purpose: dropping them would let a typo in a
      // hand-written file look like a better index.
      warnings.add(
        'Semantic expectations naming no record in the corpus (kept in the '
        'metrics, so they can only lower recall): ${unknown.join(', ')}',
      );
    }

    return _SemanticRun(
      status: 'measured',
      metrics: RecallMetrics(observations),
      observations: observations,
      issues: issues,
      unknownExpectations: unknown,
      attribution: attribution,
    );
  }

  // -- behaviour fingerprint ------------------------------------------------

  /// A fixed canary of real queries run through the live `search()`.
  ///
  /// Taken from the retained probes, sorted and evenly spaced, so it is
  /// deterministic for a given corpus and touches both the prefix path and the
  /// field weights. The resulting order is what
  /// [RecallReport.indexBehaviourHash] digests -- the one fingerprint that moves
  /// when `lib/` changes.
  List<Map<String, Object?>> _behaviourCanary(
    ScreenshotProvider provider,
    List<RecallProbe> probes,
  ) {
    final List<String> tokens =
        probes.map((RecallProbe p) => p.token).toSet().toList()..sort();
    const int size = 12;
    if (tokens.isEmpty) return <Map<String, Object?>>[];
    final List<String> chosen = <String>[];
    if (tokens.length <= size) {
      chosen.addAll(tokens);
    } else {
      for (int i = 0; i < size; i++) {
        chosen.add(tokens[(i * (tokens.length - 1)) ~/ (size - 1)]);
      }
    }
    return chosen
        .map((String t) => <String, Object?>{
              'query': t,
              'returned': _search(provider, t),
            })
        .toList();
  }

  // -- text -----------------------------------------------------------------

  String _renderText({
    required RecallProbeDerivation derivation,
    required List<RecallObservation> lexical,
    required RecallFieldPolicy fieldPolicy,
    required _SemanticRun semantic,
    required List<Map<String, Object?>> canary,
    required String configCanonical,
    required String behaviourHash,
    required RecallFieldAttribution lexicalAttribution,
    required RecallFieldAttribution? semanticAttribution,
    required List<String> warnings,
  }) {
    final StringBuffer b = StringBuffer();
    final String rule = '=' * 78;
    final RecallMetrics lexicalMetrics = RecallMetrics(lexical);
    void line(String s) => b.writeln(s);

    line(rule);
    line(' SIFT RECALL HARNESS   mode: ${corpus.mode.label}');
    line(rule);

    if (corpus.isFixture) {
      // Padded rather than hand-aligned: a hand-drawn box drifts the moment a
      // line is edited, and this banner is the one thing that must not be
      // misread.
      const int content = 62;
      void banner(String s) =>
          line('  ##  ${s.length >= content ? s : s.padRight(content)}  ##');
      line('');
      line('  ${'#' * 70}');
      banner('FIXTURE MODE -- THESE NUMBERS ARE NOT A BASELINE.');
      banner('');
      banner('The corpus is a hand-written list in');
      banner('test/support/recall_fixture_corpus.dart. It describes that');
      banner('list and nothing else. Do not quote it, do not diff a change');
      banner('against it, and do not file it as this user\'s recall.');
      banner('');
      banner('The real corpus is a directory of images plus a');
      banner('corpus.jsonl sidecar; see the header of');
      banner('test/support/recall_harness.dart.');
      line('  ${'#' * 70}');
    }

    line('');
    line('CORPUS');
    line('  label        ${corpus.label}');
    line('  records      ${corpus.records.length}');
    line('  corpusHash   ${corpus.hash}');
    line('');

    line('INDEX FINGERPRINT');
    line('  declared weights   ${_weightList()}');
    line('  declared tokenizer '
        '${declaredTokenizerConfig['splitter']} '
        '(query matches a prefix of an indexed term)');
    line('  declaredConfigHash '
        '${recallStableHash(<String>[configCanonical])}');
    line('    ^ the harness DECLARED these. They are private constants in');
    line('      lib/providers/screenshot_provider.dart, so this hash does NOT');
    line('      move if someone edits a weight there.');
    line('  indexBehaviourHash $behaviourHash');
    line('    ^ OBSERVED from the live search() over ${canary.length} '
        'canary queries.');
    line('      This is the hash that moves when the index changes.');
    line('');

    line('FIELD POLICY  (what a probe may be derived from)');
    line('  probed    ${fieldPolicy.probed.join(', ')}');
    RecallFieldPolicy.skippedFields.forEach((String field, String why) {
      line('  skipped   $field -- $why');
    });
    line('  confirmed description/searchKeywords/recognitions/extractedData '
        'empty on the addFromBulkIngest-seeded records: '
        '${fieldPolicy.neverPopulatedConfirmed}');
    line(
        '    ^ scoped to that write path. processScreenshot is the other local '
        'write path and is NOT');
    line('      exercised here. A legacy Hive row from an older build could '
        'carry these fields, which is');
    line(
        '      how a real-corpus run can legitimately show them contributing.');
    line('  confirmed lamType values: ${fieldPolicy.lamTypeValues.join(', ')} '
        '(${fieldPolicy.lamTypeValues.length == 1 ? 'constant -- cannot discriminate' : 'varies'})');
    line('  records whose summary is the "$noTextFoundPlaceholderStored" '
        'placeholder: ${fieldPolicy.placeholderSummaryCount} '
        '(never probed)');
    if (fieldPolicy.summaryMismatches.isEmpty) {
      line('  sidecar summary mismatches: none');
    } else {
      line('  sidecar summary mismatches: '
          '${fieldPolicy.summaryMismatches.length}');
      for (final String m in fieldPolicy.summaryMismatches) {
        line('    - $m');
      }
    }
    line('');

    line(
        'CLASS 1 -- LEXICAL PROBES  (derived from tokens known to be present)');
    line('  discriminativeness cutoff   $discriminativenessCutoff '
        'records per token');
    line('  tokens considered           ${derivation.tokensConsidered} '
        '(per record, per field, deduped)');
    line('  distinct tokens seen        ${derivation.distinctTokensSeen}');
    line('  dropped: unqueryable        ${derivation.droppedUnqueryable} '
        "(shorter than search()'s $recallMinQueryChars-char minimum and "
        'not CJK)');
    line('  dropped: non-discriminative ${derivation.droppedNonDiscriminative} '
        '(token held by more than $discriminativenessCutoff records)');
    line('  tokens retained             ${derivation.retainedTokens} '
        '(of the ${derivation.distinctTokensSeen} distinct)');
    line('  observations (probes)       ${derivation.probes.length} '
        '(sample size for every number below)');
    line('  of which multi-owner        ${derivation.multiOwnerProbes} '
        '(token in 2+ records; at most 1/ownerCount can be rank 1)');
    line('  of which bare numbers       ${derivation.numericProbes} '
        '(dates and prices: indexed and discriminative, but not a query '
        'anyone types -- see WARNINGS)');
    line('');
    _metricBlock(b, '  ', lexicalMetrics);
    line('');
    line('  worst probes (the full list is in the JSON report):');
    final List<RecallObservation> worst = lexical.toList()
      ..sort((RecallObservation a, RecallObservation c) {
        final int ra = a.bestRank ?? _never;
        final int rc = c.bestRank ?? _never;
        return rc.compareTo(ra);
      });
    for (final RecallObservation o in worst.take(10)) {
      final String rank = o.bestRank?.toString() ?? 'not found';
      final RecallProbe? p = o.probe;
      final String crowded = p != null && p.ownerCount > 1
          ? '  (owners: ${p.ownerCount}, reachable: ${p.matchCount})'
          : '';
      line('    ${rank.padLeft(9)}  "${o.query}" -> ${o.expectations.first}'
          '$crowded');
    }
    if (worst.length > 10) {
      line('    ... and ${worst.length - 10} more, in the JSON report.');
    }
    line('');

    line('CLASS 2 -- SEMANTIC QUERIES  (hand-written, human-labelled)');
    line('  source $semanticQueriesPath');
    if (semantic.status != 'measured') {
      line('  status ${semantic.status}');
      line('  Class 2 measures something different from class 1 and is never');
      line(
          '  averaged into it. With no query file there is no semantic number');
      line('  at all, which is the honest answer: none has been written.');
    } else {
      line('  status ${semantic.status} -- ${semantic.observations.length} '
          'queries');
      _metricBlock(b, '  ', semantic.metrics!);
      line('');
      line('  per query (at small N this is worth more than the aggregate):');
      for (final RecallObservation o in semantic.observations) {
        line('    ${o.bestRank?.toString() ?? 'not found'}  "${o.query}"');
        line('        expected ${o.expectations.join(', ')}');
        line(
            '        returned ${o.returnedFileNames.isEmpty ? '(nothing)' : o.returnedFileNames.join(', ')}');
      }
    }
    for (final RecallSemanticParseIssue i in semantic.issues) {
      line('  ! line ${i.line}: ${i.reason} (skipped)');
    }
    if (semantic.unknownExpectations.isNotEmpty) {
      line('  ! expectations naming no record in the corpus: '
          '${semantic.unknownExpectations.join(', ')}');
      line('    kept in the metrics, so a typo can only lower recall');
    }
    line('');

    line('SCORE ATTRIBUTION  (which fields produced the ranks)');
    line('  read from ScreenshotProvider.explainScores(), which runs the same');
    line('  private scorer as search(): every score below is the score that');
    line('  produced the rank next to it, not a reconstruction of it.');
    line(
        '  A slot credits a field when that field earned a non-zero weight for');
    line(
        '  that result, so slot shares across fields do NOT sum to 100%. Unit');
    line('  shares are over summed scores and do.');
    line('');
    _attributionBlock(
      b,
      '  CLASS 1 -- LEXICAL PROBES',
      lexicalAttribution,
    );
    if (semanticAttribution != null) {
      _attributionBlock(
        b,
        '  CLASS 2 -- SEMANTIC QUERIES',
        semanticAttribution,
      );
    } else {
      line('');
      line('  CLASS 2 -- SEMANTIC QUERIES');
      line('    not measured -- no query file supplied, so no attribution');
      line('    either. Class 1 is not widened to stand in for it.');
    }
    line('');
    line('WARNINGS');
    for (final String w in warnings) {
      for (final String part in _wrap(w, 74)) {
        line('  $part');
      }
    }
    line(
        '  Score ties are broken by the index\'s own sort, which Dart does not');
    line(
        '  specify as stable. Two records with identical scores can swap places');
    line('  between runs or platforms; ownerCount and matchCount are in the');
    line('  JSON per probe, so a crowded query is visible rather than');
    line('  mysterious.');
    line('');
    line(rule);
    line(' JSON report -> $reportPath');
    line(rule);
    return b.toString();
  }

  // -- plumbing -------------------------------------------------------------

  /// Sentinel rank for "never found" when sorting the worst-probe list.
  static const int _never = 0x7fffffff;

  List<String> _search(ScreenshotProvider provider, String query) {
    return provider
        .search(query, limit: _resultLimit)
        .map((Screenshot s) => s.fileName)
        .toList();
  }

  /// Read the per-field breakdown the live index used for [query], one row per
  /// result, in the rank order `search()` returned it.
  ///
  /// `explainScores()` runs the same scorer `search()` runs, so each row's score
  /// is the score that produced its rank -- this is the live index answering,
  /// not the harness re-deriving anything. The rows are cross-checked against
  /// the `search()` list this run already took: a different length or a
  /// different order means the two disagreed, which is warned about rather than
  /// papered over.
  List<RecallAttributedResult> _attribute(
    ScreenshotProvider provider,
    String query,
    List<String> searchedFileNames, {
    required RecallQueryClass queryClass,
    required Set<String> expectations,
    required List<String> warnings,
  }) {
    final SearchExplanation explanation =
        provider.explainScores(query, limit: _resultLimit);
    final List<String> explained = explanation.results
        .map((SearchScoreExplanation r) => r.fileName)
        .toList();
    if (explained.length != searchedFileNames.length ||
        !_sameOrder(explained, searchedFileNames)) {
      warnings.add(
        'explainScores() and search() disagreed for query "$query" '
        '(${explained.length} explained vs ${searchedFileNames.length} '
        'returned). The attribution for this query is reported from '
        'explainScores(); treat the ranking it explains with suspicion.',
      );
    }
    return <RecallAttributedResult>[
      for (int i = 0; i < explanation.results.length; i++)
        RecallAttributedResult(
          queryClass: queryClass,
          query: query,
          rank: i + 1,
          fileName: explanation.results[i].fileName,
          score: explanation.results[i].score,
          fieldContributions: explanation.results[i].fieldContributions,
          contributionsSum: explanation.results[i].contributionsSum,
          contributionsMatchScore:
              explanation.results[i].contributionsMatchScore,
          isExpectation: expectations.contains(explained[i]),
          tiedWithNeighbour: _tiedAt(explanation.results, i),
        ),
    ];
  }

  /// Whether result [i] shares its score with the row above or below it. The
  /// ranking has no tiebreak, so such a rank was decided by the sort's internal
  /// order rather than by the weights -- which is exactly what a per-field
  /// attribution must not be read as explaining.
  static bool _tiedAt(List<SearchScoreExplanation> results, int i) {
    final int score = results[i].score;
    if (i > 0 && results[i - 1].score == score) return true;
    return i + 1 < results.length && results[i + 1].score == score;
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _weightList() => declaredIndexWeights.entries
      .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
      .join(' ');

  String _canonicalIndexConfig() => <String>[
        'weights:${declaredIndexWeights.entries.map((MapEntry<String, int> e) => '${e.key}=${e.value}').join(',')}',
        'tokenizer:${declaredTokenizerConfig.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join(',')}',
        'splitterCode=${recallWordSplitter.pattern}',
        'cjkCode=${recallCjk.pattern}',
        'probedFields=${RecallFieldPolicy.probedFields.join(',')}',
        'skippedFields=${RecallFieldPolicy.skippedFields.keys.join(',')}',
      ].join('|');

  Future<bool> _writeJson(Map<String, Object?> payload) async {
    try {
      final File file = File(reportPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
        flush: true,
      );
      return true;
    } catch (_) {
      // A read-only checkout must not fail a measurement run. The text report
      // is the primary output; the caller warns that the artifact is missing.
      return false;
    }
  }
}

// ============================================================================
// Internals
// ============================================================================

/// What probe derivation produced, including the counts that let a reader see
/// how much was discarded before any metric was computed.
class RecallProbeDerivation {
  const RecallProbeDerivation({
    required this.probes,
    required this.tokensConsidered,
    required this.distinctTokensSeen,
    required this.retainedTokens,
    required this.droppedUnqueryable,
    required this.droppedNonDiscriminative,
    required this.multiOwnerProbes,
    required this.numericProbes,
  });

  final List<RecallProbe> probes;

  /// (record, field, token) triples, deduped within each field.
  final int tokensConsidered;

  /// Distinct token strings seen across every probed field.
  final int distinctTokensSeen;

  /// Distinct token strings that became probes. Equals `probes.length` only when
  /// no token has more than one owner; a multi-owner token contributes one
  /// probe per owner, so this is the denominator, and `probesRetained` is the
  /// numerator of the same ratio.
  final int retainedTokens;

  final int droppedUnqueryable;
  final int droppedNonDiscriminative;

  /// Retained tokens held by more than one record.
  final int multiOwnerProbes;

  /// Retained tokens that are nothing but ASCII digits.
  ///
  /// Counted and reported, never filtered. A timestamp half or a price is
  /// genuinely indexed and genuinely discriminative -- "14" really is on only
  /// three records -- so dropping it would hide a real property of the index.
  /// But no user types "14" to find a screenshot, so these probes inflate
  /// recall@1 with hits that do not correspond to a real query. The number is
  /// reported so a reader can discount the headline, and the JSON carries each
  /// probe so the split can be recomputed.
  final int numericProbes;
}

class _SemanticRun {
  const _SemanticRun({
    required this.status,
    required this.metrics,
    required this.observations,
    required this.issues,
    required this.unknownExpectations,
    required this.attribution,
  });

  final String status;
  final RecallMetrics? metrics;
  final List<RecallObservation> observations;
  final List<RecallSemanticParseIssue> issues;
  final List<String> unknownExpectations;

  /// Per-field breakdown per result, or null when no query file was supplied.
  final List<RecallAttributedResult>? attribution;
}

// -- small shared helpers ---------------------------------------------------

/// 32-bit FNV-1a, hex. A fingerprint, not a security hash: it exists to make
/// "were these two reports produced by the same configuration" a yes/no
/// question. Every hash the report carries also ships the canonical string it
/// was taken from, so a collision would be visible rather than believed.
///
/// 32 bits keeps every intermediate inside Dart's exact integer range on every
/// platform -- `h * 0x01000193` never exceeds 2^56 -- which a 64-bit variant
/// would not: the VM's `int` is a wrapped 64-bit, and the masking needed to
/// make that deterministic is easy to get subtly wrong.
String recallStableHash(Iterable<String> parts) {
  int h = 0x811c9dc5;
  for (final String part in parts) {
    for (final int byte in utf8.encode(part)) {
      h = (h ^ byte) * 0x01000193 & 0xFFFFFFFF;
    }
    // 0x1e (record separator) so ('ab','c') and ('a','bc') cannot land on the
    // same byte stream.
    h = (h ^ 0x1e) * 0x01000193 & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

Object? _tryDecode(String line) {
  try {
    return jsonDecode(line);
  } catch (_) {
    return null;
  }
}

String? _optionalString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

List<String> _stringList(Object? value) {
  if (value is List) return value.whereType<String>().toList();
  return const <String>[];
}

/// One class's per-field distribution, printed as a ranked table plus the
/// zero-contribution line. Hand-aligned with padRight rather than boxed, so an
/// edited field name cannot break the frame.
void _attributionBlock(
  StringBuffer b,
  String label,
  RecallFieldAttribution a,
) {
  void line(String s) => b.writeln(s);
  String pct(double? v) =>
      v == null ? '  n/a' : '${(v * 100).toStringAsFixed(0)}%'.padLeft(5);

  line(label);
  if (a.results == 0) {
    line('    no results to attribute');
    return;
  }
  line('    queries ${a.queries.length}, results read ${a.results}, '
      'top-10 slots ${a.top10Slots}, rank-1 slots ${a.top1Slots}');
  line('    summed score over top-10 slots ${a.top10Units}; '
      'expected record inside the top 10 for ${a.expectationsInTop10} of them');
  line('    split sums to the score for '
      '${a.results - a.mismatchedResults}/${a.results} results'
      '${a.mismatchedResults == 0 ? '' : '  <-- ${a.mismatchedResults} MISMATCHED, '
          'this distribution is a LOWER BOUND'}');
  line('');
  line('    ${'field'.padRight(19)}'
      '${'slots'.padLeft(6)}${'%slots'.padLeft(8)}'
      '${'units'.padLeft(7)}${'%units'.padLeft(8)}'
      '${'rk1'.padLeft(5)}${'%rk1'.padLeft(7)}'
      '${'exp'.padLeft(5)}${'%exp'.padLeft(7)}');
  for (final String f in a.rankedFields) {
    line('    ${f.padRight(19)}'
        '${(a.top10SlotsByField[f] ?? 0).toString().padLeft(6)}'
        '${pct(a.slotShareAt10(f))}'
        '${(a.top10UnitsByField[f] ?? 0).toString().padLeft(7)}'
        '${pct(a.unitShareAt10(f))}'
        '${(a.top1SlotsByField[f] ?? 0).toString().padLeft(5)}'
        '${pct(a.slotShareAt1(f))}'
        '${(a.expectationSlotsByField[f] ?? 0).toString().padLeft(5)}'
        '${pct(a.expectationSlotShare(f))}');
  }
  line('    slots = top-10 result slots the field earned weight in;');
  line('    rk1   = the same over first places only;');
  line('    exp   = slots where the record was the one being looked for.');
  final String tiedShare = a.top10Slots == 0
      ? 'n/a'
      : '${(a.tiedTop10Slots / a.top10Slots * 100).toStringAsFixed(0)}%';
  line('    ${a.tiedTop10Slots} of the ${a.top10Slots} top-10 slots '
      '($tiedShare) shared a score with a neighbour.');
  line('    Those ranks were NOT decided by any weight -- the sort has no');
  line('    tiebreak -- so do not read the field breakdown as the reason');
  line('    such a record won its position.');
  line('');
  final List<String> zero = a.zeroContributionFields;
  if (zero.isEmpty) {
    line('    ZERO-CONTRIBUTION FIELDS: none -- every weighted field earned');
    line('    at least one top-10 slot in this class.');
  } else {
    line('    ZERO-CONTRIBUTION FIELDS (weighted by the index, credited to');
    line('    nothing in the top 10): ${zero.join(', ')}');
    for (final String f in zero) {
      line("      $f = weight ${declaredIndexWeights[f]}, and it did not "
          'decide a single top-10 rank');
    }
  }
}

void _metricBlock(StringBuffer b, String indent, RecallMetrics m) {
  void row(String label, double? value, String detail) {
    final String shown = value == null ? 'n/a' : value.toStringAsFixed(2);
    b.writeln('$indent${label.padRight(11)} ${shown.padLeft(5)}  $detail');
  }

  if (m.total == 0) {
    b.writeln('${indent}no observations -- nothing to report');
    return;
  }
  row('recall@1', m.recallAt1, '(${m.hitAt1}/${m.total})');
  row('recall@5', m.recallAt5, '(${m.hitAt5}/${m.total})');
  row('recall@10', m.recallAt10, '(${m.hitAt10}/${m.total})');
  row('found', m.total == 0 ? null : m.found / m.total,
      '(${m.found}/${m.total})');
  b.writeln('$indent${'not found'.padRight(11)} '
      '${m.unfound.toString().padLeft(5)}  in the whole result list');
  b.writeln('$indent${'median rank'.padRight(11)} '
      '${(m.medianRankAll?.toString() ?? 'n/a').padLeft(5)}  '
      '(unreturned ranked below every real rank; among-found: '
      '${m.medianRankFound ?? 'n/a'})');
}

/// Naive word wrap for the warning block. The warnings are hand-written prose
/// with no line breaks in them, and a 300-character paragraph printed on one
/// line is unreadable in a test log.
List<String> _wrap(String text, int width) {
  final List<String> out = <String>[];
  StringBuffer current = StringBuffer();
  for (final String word in text.split(' ')) {
    if (current.isEmpty) {
      current.write(word);
    } else if (current.length + 1 + word.length <= width) {
      current.write(' $word');
    } else {
      out.add(current.toString());
      current = StringBuffer(word);
    }
  }
  if (current.isNotEmpty) out.add(current.toString());
  return out;
}
