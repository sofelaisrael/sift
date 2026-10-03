import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/ocr_service.dart';

/// What `ScreenshotProvider._queryTerms` derives from a *question*, as opposed
/// to a search-box query.
///
/// The bug this file pins: `_maxQueryTerms` keeps the FIRST six words of a
/// query, so "can you please show me my food screenshots from last week" was
/// scored on `can you please show me my` and `food` / `screenshots` were
/// dropped before the index was ever read. Worse, those six function words were
/// the only terms, and a term matches every indexed word that *starts* with it,
/// so `me` reached an unrelated `menu` record. The on-device model was handed
/// screenshots chosen by grammar.
///
/// `_queryTerms` is private, so every assertion here is made through
/// `search()`: one record per candidate word, each reachable by exactly one
/// term, and the set of returned paths *is* the term list. A word that is not
/// returned was not a term. That is stronger than asserting on a term list,
/// because it fails if the filter stops matching or if prefix matching stops
/// working, and it cannot be satisfied by a filter that only looks right.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('query_terms_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// One record per candidate word.
  ///
  /// The word goes on the SECOND line so it reaches `ocrText` and not the
  /// `summary` slice production derives from the first line. `Header` shares no
  /// prefix with any candidate, and `png` (from the file name, on every record)
  /// is never queried.
  ///
  /// `canteen`, `youtube`, `menu`, `mybank`, `invoice` and `android` exist only
  /// to be reached by PREFIX from the stop word that precedes them — `can`,
  /// `you`, `me`, `my`, `in`, `an`. Those are the real-world false positives,
  /// and they are the reason a record's word is chosen to *start with* the stop
  /// word rather than to be it: an exact word would also be dropped by the
  /// filter, so the prefix is what makes the false positive reachable at all.
  /// `stillshot` carries the literal word `screenshot`, which is what the
  /// all-stop-word fallback has to find.
  const Map<String, String> corpus = <String, String>{
    // Content words the long question must still reach.
    'food': 'food',
    'screenshots': 'screenshots',
    'week': 'week',
    // Reachable by prefix from a stop word only: must NOT be reached.
    'canteen': 'canteen',
    'youtube': 'youtube',
    'menu': 'menu item',
    'mybank': 'mybank',
    'invoice': 'invoice',
    'android': 'android',
    // The stop words themselves, as literal words: also must NOT be reached.
    'last': 'last',
    'show': 'show',
    // Real content, for the search-box controls.
    'bagel': 'everything bagel everything',
    'receipt': 'receipt',
    // Content words for the one-character filter: a query of several words must
    // not lose a content word to a bare `s` from an apostrophe.
    'shopping': 'shopping',
    'list': 'list',
    // Reachable by prefix from a bare `s` alone, which is what proves the
    // one-character filter ran: nothing else in these two queries starts with s.
    'shelf': 'shelf',
    'sourdough': 'sourdough',
    // Reachable only through the literal index word `screenshot`.
    'stillshot': 'screenshot',
    'cjk': '截图',
    // Seven content words, for the cap.
    'alpha': 'alpha',
    'bravo': 'bravo',
    'charlie': 'charlie',
    'delta': 'delta',
    'echo': 'echo',
    'foxtrot': 'foxtrot',
    'golf': 'golf',
  };

  Future<ScreenshotProvider> seeded() async {
    await Hive.openBox('screenshots');
    final provider = ScreenshotProvider(
      ocr: OCRService(extractOverride: (_) async => ''),
    );
    var day = 1;
    for (final entry in corpus.entries) {
      final id = await provider.addFromBulkIngest(
        path: '/probe/${entry.key}.png',
        capturedAt: DateTime(2026, 3, day++),
        ocrText: 'Header line\n${entry.value}',
      );
      expect(id, isNotNull, reason: 'seed ${entry.key}');
    }
    expect(provider.screenshots, hasLength(corpus.length));
    return provider;
  }

  /// The paths `provider.search(query)` returned, as an unordered set.
  Set<String> found(ScreenshotProvider provider, String query,
          {int limit = 50}) =>
      provider
          .search(query, limit: limit)
          .map((Screenshot s) => s.filePath)
          .toSet();

  group('the measured question: the cap no longer eats the content words', () {
    test('a long question keeps `food` and `screenshots`, drops the grammar',
        () async {
      final provider = await seeded();

      const longQuestion =
          'can you please show me my food screenshots from last week';
      final hits = found(provider, longQuestion);
      debugPrint('QUERY "$longQuestion"');
      debugPrint('  -> $hits');

      // The content words reached the index.
      expect(hits, contains('/probe/food.png'));
      expect(hits, contains('/probe/screenshots.png'));
      expect(hits, contains('/probe/week.png'),
          reason: '`week` is content inside "last week"; `last` and `from` '
              'are the grammar around it');

      // The function words did not.
      expect(hits, isNot(contains('/probe/canteen.png')),
          reason: 'reachable only by `can` -> `canteen`');
      expect(hits, isNot(contains('/probe/youtube.png')),
          reason: 'reachable only by `you` -> `youtube`');
      expect(hits, isNot(contains('/probe/menu.png')),
          reason:
              "reachable only by `me` -> `menu`: the measured false positive");
      expect(hits, isNot(contains('/probe/mybank.png')),
          reason: 'reachable only by `my` -> `mybank`');
      expect(hits, isNot(contains('/probe/invoice.png')),
          reason: 'this query has no `in`, so `invoice` must not be reached '
              'either — it is here to prove the CJK test below is sharp');
      expect(hits, isNot(contains('/probe/android.png')),
          reason: 'reachable only by `an` -> `android`');
      expect(hits, isNot(contains('/probe/show.png')),
          reason: '`show` is the asking-verb');
      expect(hits, isNot(contains('/probe/last.png')),
          reason: '`last` is a time preposition; `week` is the content');

      // Exactly the three content words. Since every other record in the corpus
      // is reachable through a stop word alone, this length is a complete
      // statement of the term list: [food, screenshots, week].
      expect(hits, hasLength(3));
    });

    test('"show me my food screenshots" reduces to the content words',
        () async {
      final provider = await seeded();

      const question = 'show me my food screenshots';
      final hits = found(provider, question);
      debugPrint('QUERY "$question"');
      debugPrint('  -> $hits');

      expect(hits, contains('/probe/food.png'));
      expect(hits, contains('/probe/screenshots.png'));
      expect(hits, isNot(contains('/probe/menu.png')),
          reason: "`me` -> `menu`");
      expect(hits, isNot(contains('/probe/mybank.png')),
          reason: "`my` -> `mybank`");
      expect(hits, isNot(contains('/probe/show.png')),
          reason: '`show` is the asking-verb, not the subject');
      expect(hits, hasLength(2));
    });
  });

  group('a query made only of stop words still searches', () {
    test('the fallback uses the unfiltered terms', () async {
      final provider = await seeded();

      // Every word here is dropped by the filter: `show`, `me`, `please`.
      const allStopWords = 'show me please';
      final hits = found(provider, allStopWords);
      debugPrint('QUERY "$allStopWords" (all stop words)');
      debugPrint('  -> $hits');

      expect(hits, isNotEmpty,
          reason: 'filtering to nothing must not silently match nothing');
      expect(hits, contains('/probe/show.png'),
          reason: 'the fallback keeps the original term `show`');
      expect(hits, contains('/probe/menu.png'),
          reason: 'the fallback keeps the original term `me` -> `menu`; this '
              'false positive is the price of not returning nothing at all');
      expect(hits, hasLength(2),
          reason: '`please` is a term again too, and nothing in the corpus '
              'starts with it');
    });

    test('"screenshot" alone still searches', () async {
      final provider = await seeded();

      final hits = found(provider, 'screenshot');
      debugPrint('QUERY "screenshot" (an app noun, dropped by the filter)');
      debugPrint('  -> $hits');

      expect(hits, contains('/probe/stillshot.png'),
          reason: '`screenshot` is filtered away, then restored by the '
              'fallback, so the record carrying that literal word is found');
      expect(hits, contains('/probe/screenshots.png'),
          reason: 'prefix matching is unchanged: the term `screenshot` still '
              'completes to `screenshots`');
      expect(hits, hasLength(2));
    });
  });

  group('the gates that must not move', () {
    test('a single-character query is still rejected by the length gate',
        () async {
      final provider = await seeded();

      // `a` is both a stop word AND one character, so this alone would not say
      // which rule rejected it. `my` is also a stop word but passes the gate.
      expect(provider.search('a'), isEmpty);
      expect(provider.search('I'), isEmpty,
          reason: 'the gate is case-insensitive like the rest of the splitter');
      expect(provider.search(' '), isEmpty);

      final twoChar = found(provider, 'my');
      expect(twoChar, contains('/probe/mybank.png'),
          reason: 'a two-character stop word passes the gate and the filter '
              'falls back, so it is the length gate and not the filter that '
              'rejects a one-character query');
    });

    test('a CJK query is untouched, stop words included', () async {
      final provider = await seeded();

      final pure = found(provider, '截图');
      debugPrint('QUERY "截图" -> $pure');
      expect(pure, contains('/probe/cjk.png'));

      // The sharp case. `in` and `me` are stop words and `截图` is one whole
      // term, so if the filter ran on a CJK query the list would become just
      // ['截图'] and both English records would vanish. They do not vanish:
      // the CJK path keeps the unfiltered list, which is exactly what it did
      // before the filter existed.
      const mixed = 'in 截图 me';
      final hits = found(provider, mixed);
      debugPrint('QUERY "$mixed" -> $hits');
      expect(hits, contains('/probe/cjk.png'),
          reason: 'the CJK run is still one term and still matches');
      expect(hits, contains('/probe/invoice.png'),
          reason: '`in` survives: the CJK path is not filtered');
      expect(hits, contains('/probe/menu.png'),
          reason: '`me` survives: the CJK path is not filtered');
      expect(hits, hasLength(3));
    });
  });

  group('one-character terms are not terms', () {
    test('"week\'s" does not search for every word starting with s', () async {
      final provider = await seeded();

      // `_wordSplitter` breaks on the apostrophe, so this tokenises to
      // ['week', 's']. `s` is not a stop word, and prefix matching turns it into
      // a query for every indexed word that begins with `s`. The corpus has four
      // of those and one of them is the subject of the query, so an unfiltered
      // `s` is visible here and not merely theoretical.
      const query = "week's";
      final hits = found(provider, query);
      debugPrint('QUERY "$query" -> $hits');

      expect(hits, contains('/probe/week.png'),
          reason: 'the content word survives');
      expect(hits, hasLength(1),
          reason:
              'the bare `s` must not reach shelf/sourdough/screenshots/show');
      expect(hits, isNot(contains('/probe/shelf.png')));
      expect(hits, isNot(contains('/probe/sourdough.png')));
      expect(hits, isNot(contains('/probe/screenshots.png')));
      expect(hits, isNot(contains('/probe/show.png')));
    });

    test('"what\'s in my shopping list" keeps the content words', () async {
      final provider = await seeded();

      // Six words, three of which the stop-word filter takes, plus the bare `s`.
      // Without the one-character filter that is six terms and the cap at
      // [_maxQueryTerms] — with it, two content words and the whole budget.
      const query = "what's in my shopping list";
      final hits = found(provider, query);
      debugPrint('QUERY "$query" -> $hits');

      expect(hits, contains('/probe/shopping.png'));
      expect(hits, contains('/probe/list.png'));
      expect(hits, hasLength(2),
          reason: 'only the two content words; `s` reached nothing, or the '
              'length assertion below would already have failed');
      expect(hits, isNot(contains('/probe/shelf.png')),
          reason: 'only the bare `s` could reach this one');
      expect(hits, isNot(contains('/probe/sourdough.png')));
    });

    test('a single CJK character is still a query', () async {
      final provider = await seeded();

      // The filter is `t.length > 1 || _cjk.hasMatch(t)`, so a one-character
      // term survives exactly when it is CJK. A single kanji is a word, and the
      // gate above already lets the query through for the same reason.
      //
      // '截' is the LEADING character of the corpus run `截图`, because
      // matching is still prefix-only: `图` would match nothing, and for the
      // same reason `ag` does not find `bagel`.
      final single = found(provider, '截');
      debugPrint('QUERY "截" -> $single');
      expect(single, contains('/probe/cjk.png'),
          reason: 'a one-character CJK term is real content, not noise');
      expect(found(provider, '图'), isEmpty,
          reason: 'unchanged prefix semantics, not a length effect');

      // The whole run still works, so the term is not only matched by accident.
      expect(found(provider, '截图'), contains('/probe/cjk.png'));
    });

    test('a single Latin character is still rejected by the length gate',
        () async {
      final provider = await seeded();

      // `z` is not a stop word, so it passes the filter and reaches the length
      // gate alone. The gate runs on the whole query, which is why it cannot be
      // the thing that catches the `s` in "week's".
      expect(provider.search('z'), isEmpty);
      expect(provider.search('Z'), isEmpty,
          reason: 'the gate lowercases like the rest of the splitter');
      expect(found(provider, 'so'), <String>{'/probe/sourdough.png'},
          reason:
              'a two-character term that is not a stop word still searches, '
              'so the empty results above are the gate and not a dead index');
    });
  });

  group('prefix matching still works on a filtered query', () {
    test('a dropped verb in front does not stop `bag` finding `bagel`',
        () async {
      final provider = await seeded();

      const query = 'please bag';
      final hits = found(provider, query);
      debugPrint('QUERY "$query" -> $hits');

      expect(hits, contains('/probe/bagel.png'),
          reason: '`bag` is a surviving term and must still prefix-match '
              '`bagel`');
      expect(hits, isNot(contains('/probe/receipt.png')));
      expect(hits, isNot(contains('/probe/canteen.png')),
          reason: '`can` is not in this query, so `canteen` must not appear');
      expect(hits, hasLength(1));
    });

    test('a long filtered question still prefix-matches its content word',
        () async {
      final provider = await seeded();

      const query = 'can you please show me my bagel';
      final hits = found(provider, query);
      debugPrint('QUERY "$query" -> $hits');
      expect(hits, <String>{'/probe/bagel.png'});
    });

    test('the term cap still applies, now to content words only', () async {
      final provider = await seeded();

      // Seven content words: none is a stop word, so all seven survive the
      // filter and the cap has to be what drops the seventh.
      const query = 'alpha bravo charlie delta echo foxtrot golf';
      final hits = found(provider, query);
      debugPrint('QUERY "$query" -> $hits');
      expect(hits, hasLength(6));
      expect(hits.contains('/probe/golf.png'), isFalse,
          reason: 'the cap is still 6 and still keeps the first six');
      for (final word in <String>[
        'alpha',
        'bravo',
        'charlie',
        'delta',
        'echo',
        'foxtrot'
      ]) {
        expect(hits, contains('/probe/$word.png'), reason: word);
      }
    });
  });

  group('a search-box query for real content is unchanged', () {
    test('"bagel" finds the bagel record and nothing else', () async {
      final provider = await seeded();

      final hits = found(provider, 'bagel');
      debugPrint('QUERY "bagel" -> $hits');

      expect(hits, <String>{'/probe/bagel.png'});
      expect(hits, isNot(contains('/probe/receipt.png')),
          reason: 'an unrelated record must stay unfound');
      expect(hits, isNot(contains('/probe/menu.png')),
          reason: 'an unrelated record must stay unfound');
    });

    test('a plain multi-word content query is unchanged', () async {
      final provider = await seeded();

      // Neither word is a stop word, so the filter is a no-op and the result is
      // exactly what it was before the fix.
      expect(found(provider, 'bagel receipt'),
          <String>{'/probe/bagel.png', '/probe/receipt.png'});
      expect(found(provider, 'receipt bagel'),
          <String>{'/probe/bagel.png', '/probe/receipt.png'});
      expect(found(provider, 'food menu'),
          <String>{'/probe/food.png', '/probe/menu.png'});
    });
  });
}
