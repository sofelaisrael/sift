import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/screenshot.dart';
import '../services/action_model.dart';
import '../services/action_service.dart';
import '../services/image_labeler.dart';
import '../services/ocr_service.dart';
import '../services/screenshot_analyzer.dart';
import '../services/web_lookup.dart';

/// Reads the persisted local-only preference during provider startup.
typedef LocalOnlyPreferenceLoader = Future<bool?> Function();

/// Persists a local-only preference value.
typedef LocalOnlyPreferenceWriter = Future<bool> Function(bool value);

/// Resolves the app documents directory for the private import folder.
typedef DocumentsDirectoryLoader = Future<Directory> Function();

/// Removes the private import folder from disk. Injectable for tests; the
/// default deletes the whole tree recursively.
typedef ImportDirectoryCleaner = Future<void> Function(Directory directory);

/// Drops every stored preference and reports whether the platform accepted the
/// write. Injectable for tests; the default is [SharedPreferences.clear].
typedef PreferencesClearer = Future<bool> Function(SharedPreferences prefs);

/// Raised when "delete everything" cannot guarantee the private import folder
/// is gone. The message is a fixed string: no path, no platform error text.
class DataDeletionException implements Exception {
  const DataDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ProviderOperationRejected implements Exception {
  const _ProviderOperationRejected();
}

/// One record's score for a query, split into the per-field weights that
/// produced it. Returned by [ScreenshotProvider.explainScores].
class SearchScoreExplanation {
  const SearchScoreExplanation({
    required this.id,
    required this.fileName,
    required this.score,
    required this.fieldContributions,
    required this.contributionsSum,
    required this.contributionsMatchScore,
  });

  final String id;
  final String fileName;

  /// The total [ScreenshotProvider.search] ranked this record on. Not
  /// recomputed: it is the score the ranking used.
  final int score;

  /// Field name -> the weight units that field earned for this query. A field
  /// absent from the map earned nothing. A term in both `summary` and `ocrText`
  /// appears in both, because the index really does score both.
  final Map<String, int> fieldContributions;

  /// [fieldContributions] summed, so a reader can check it against [score]
  /// without walking the map.
  final int contributionsSum;

  /// Whether [contributionsSum] equals [score]. False means the breakdown does
  /// not account for the whole score -- a write path indexing a field this
  /// split does not know about, most likely. Report it rather than trusting
  /// the split.
  final bool contributionsMatchScore;
}

/// Everything [ScreenshotProvider.explainScores] knows about one query.
class SearchExplanation {
  const SearchExplanation({required this.query, required this.results});

  final String query;

  /// The same records, in the same rank order, as the list
  /// [ScreenshotProvider.search] returns for [query] at the same limit.
  final List<SearchScoreExplanation> results;

  /// Whether every result's per-field breakdown adds up to its score. A false
  /// here means the attribution is incomplete for this query.
  bool get isConsistent =>
      results.every((SearchScoreExplanation r) => r.contributionsMatchScore);
}

/// One field's contribution to the inverted index: the text that goes in, the
/// weight it carries, and the field's name so a score can be attributed back to
/// it.
///
/// [text] is the raw value, ungated and untrimmed, because
/// `ScreenshotProvider._addTerms` applies `_searchableText` itself.
class _IndexedField {
  const _IndexedField(this.field, this.text, this.weight);

  /// Field name, matching the key the weight table uses.
  final String field;
  final String? text;
  final int weight;
}

class ScreenshotProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const int _bulkNotifyInterval = 25;
  static const int _maxQueryTerms = 6;
  static const int _ocrBlobCap = 2000;
  static const int _maxImportBytes = 25 * 1024 * 1024;
  static const Set<String> _importExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.heic',
    '.heif',
  };
  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

  final ScreenshotAnalyzer _analyzer;
  final LocalOnlyPreferenceLoader? _localOnlyPreferenceLoader;
  final LocalOnlyPreferenceWriter? _localOnlyPreferenceWriter;
  final DocumentsDirectoryLoader? _documentsDirectoryLoader;
  final ImportDirectoryCleaner _importDirectoryCleaner;
  final PreferencesClearer _preferencesClearer;
  Directory? _importDirectoryOverride;
  Future<void> Function()? _ingestStopHook;

  ScreenshotProvider({
    ScreenshotAnalyzer? analyzer,
    OCRService? ocr,
    ImageLabeler? labeler,
    LocalOnlyPreferenceLoader? localOnlyPreferenceLoader,
    LocalOnlyPreferenceWriter? localOnlyPreferenceWriter,
    DocumentsDirectoryLoader? documentsDirectoryLoader,
    ImportDirectoryCleaner? importDirectoryCleaner,
    PreferencesClearer? preferencesClearer,
  })  : _analyzer =
            analyzer ?? MLKitScreenshotAnalyzer(ocr: ocr, labeler: labeler),
        _localOnlyPreferenceLoader = localOnlyPreferenceLoader,
        _localOnlyPreferenceWriter = localOnlyPreferenceWriter,
        _documentsDirectoryLoader = documentsDirectoryLoader,
        _importDirectoryCleaner = importDirectoryCleaner ??
            ((directory) => directory.delete(recursive: true)),
        _preferencesClearer = preferencesClearer ?? ((prefs) => prefs.clear());

  ScreenshotAnalyzer get analyzer => _analyzer;
  bool get isDeleting => _deletionInProgress;
  int get deletionRevision => _deletionRevision;

  void setIngestStopHook(Future<void> Function()? stop) {
    _ingestStopHook = stop;
  }

  List<Screenshot> _screenshots = [];
  Map<String, Screenshot> _byPath = {};
  Set<String> _hiddenPaths = {};
  Map<String, Set<String>> _tagIndex = {};
  bool _isLoading = false;
  String? _error;
  String _processingStatus = '';
  bool _showFavoritesOnly = false;
  bool _localOnly = true;
  int _localOnlyRevision = 0;
  bool _deletionInProgress = false;
  int _deletionRevision = 0;
  Future<void>? _deletionFuture;
  Future<void> _queueTail = Future.value();
  Future<void> _writeTail = Future.value();
  int _pendingNotifies = 0;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_deletionInProgress) {
      return Future<T>.error(const _ProviderOperationRejected());
    }
    final result = _queueTail.then<T>((_) {
      if (_deletionInProgress) {
        throw const _ProviderOperationRejected();
      }
      return operation();
    });
    // Return errors to the caller without leaving the queue blocked.
    _queueTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  // Inverted index: word → {screenshotId: fieldWeightScore}
  // Built at load time and updated incrementally on add/delete.
  // Every indexed field, with its weight: summary 5, searchKeywords 4, tags 3,
  // objects 2, recognitions 2, ocrText 1, fileName 1, extractedData 1.
  //
  // A weight is a per-field score, not a per-occurrence multiplier: a term
  // contributes its field's weight once however many times the term recurs
  // inside that field. The same term in two fields still adds both — `summary`
  // is a slice of `ocrText`, so an overlap legitimately scores 5 + 1.
  //
  // Queries match a term when the *indexed* term starts with it, so 'bag'
  // finds 'bagel'. That is query-side only: nothing extra is written to the
  // index, and a mid-word substring still does not match. See [search].
  //
  // Unpopulated by the local analyzer: searchKeywords, recognitions and
  // extractedData are written as []/null on every record, so their 7 weight
  // units never fire. tags is empty until the user adds one. ocrText is null
  // when the image has no readable text. summary is the first 80 characters of
  // ocrText, so its 5 units re-weight the same tokens.
  //
  // description is record-and-prompt-only: stored on the record, rendered into
  // the model prompt, and indexed nowhere. It is built from `objects` plus
  // framing words that are themselves unreachable, so it carries nothing
  // `objects` does not already carry, and indexing it would count the same
  // label tokens twice. See [_deriveDescription].
  //
  // lamType is deliberately NOT indexed: the local paths store the constant
  // 'document' on every record, so it can never discriminate between results.
  // The field itself is untouched — cards and the type filter still read it.
  //
  // The weight values are not tuned. They are unmeasured, and recalibrating
  // them is a separate, measurement-driven task; only remove the dead entries.
  static const int _wSummary = 5;
  static const int _wTags = 3;
  static const int _wObjects = 2;
  static const int _wRecognitions = 2;
  static const int _wOcr = 1;
  static const int _wFileName = 1;
  static const int _wExtractedData = 1;
  static const int _wSearchKeywords = 4;
  static const int _maxWordLength = 64;
  // Separators are everything outside `A-Za-z0-9` and the CJK range, so `_`
  // splits. The keep-set is spelled out letter-by-letter rather than written as
  // `\w` because Dart's `\w` is `[A-Za-z0-9_]`: a negated class can only ever
  // *add* to the set it excludes from, so `[^\w…]` can never make the
  // underscore a separator. It stayed glued to its neighbours instead, which
  // made `Screenshot_20260927_143012` one token and the fileName field
  // unsearchable by any part of the name. Hyphens already split and
  // underscores joining them was an oversight, not a decision, so both now
  // separate. Nothing else moves: `\w` is ASCII-only in Dart, so accented
  // Latin and other non-CJK scripts were already separators and still are. The
  // CJK range is untouched for the same reason as before — CJK has no spaces
  // between characters, so `\u4e00-\u9fff` is the only reason
  // '咖啡店的菜单' tokenizes at all.
  static final RegExp _wordSplitter = RegExp(r'[^A-Za-z0-9\u4e00-\u9fff]+');
  Map<String, Map<String, int>> _invertedIndex = {};

  List<Screenshot> get screenshots => _screenshots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get processingStatus => _processingStatus;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get localOnly => _localOnly;
  List<Screenshot> get favorites =>
      _screenshots.where((s) => s.isFavorite).toList();
  List<Screenshot> get visibleScreenshots => _showFavoritesOnly
      ? _screenshots
          .where((s) => s.isFavorite && !_hiddenPaths.contains(s.filePath))
          .toList()
      : _visible;

  List<Screenshot> get _visible =>
      _screenshots.where((s) => !_hiddenPaths.contains(s.filePath)).toList();

  List<Screenshot> get recentScreenshots => _visible.take(10).toList();

  Map<String, List<Screenshot>> get byType {
    final map = <String, List<Screenshot>>{};
    for (final s in _visible) {
      final type = s.lamType ?? 'other';
      map.putIfAbsent(type, () => []).add(s);
    }
    return map;
  }

  bool containsPath(String path) => _byPath.containsKey(path);

  bool isHidden(String path) => _hiddenPaths.contains(path);

  /// Screenshots carrying [tag] (case-insensitive), hidden excluded.
  List<Screenshot> byTag(String tag) {
    final ids = _tagIndex[tag.toLowerCase()] ?? const <String>{};
    return _screenshots
        .where((s) => ids.contains(s.id) && !_hiddenPaths.contains(s.filePath))
        .toList();
  }

  /// Every distinct user tag (original casing), for filter chips.
  Set<String> get tags => _screenshots
      .expand((s) => s.tags)
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet();

  Future<void> loadScreenshots() async {
    if (_deletionInProgress) return;
    final deletionRevision = _deletionRevision;
    _isLoading = true;
    notifyListeners();
    await _loadSettings();
    if (_deletionInProgress || deletionRevision != _deletionRevision) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final box = Hive.box('screenshots');
      final loaded = box.values
          .map((json) => Screenshot.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      if (_deletionInProgress || deletionRevision != _deletionRevision) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      _screenshots = loaded;
      _screenshots.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _byPath = {for (final s in _screenshots) s.filePath: s};
      _rebuildIndexes();
      _loadHiddenPaths();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_deletionInProgress || deletionRevision != _deletionRevision) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void _loadHiddenPaths() {
    if (!Hive.isBoxOpen('hidden_paths')) return;
    final box = Hive.box('hidden_paths');
    _hiddenPaths = box.keys.cast<String>().toSet();
  }

  Future<void> _loadSettings() async {
    final revision = _localOnlyRevision;
    try {
      final value = _localOnlyPreferenceLoader != null
          ? await _localOnlyPreferenceLoader!()
          : (await SharedPreferences.getInstance()).getBool('localOnly');
      if (revision == _localOnlyRevision) {
        _localOnly = value != false;
      }
    } catch (_) {
      if (revision == _localOnlyRevision) {
        _localOnly = true;
      }
    }
  }

  Future<bool> _persistLocalOnlyPreference(bool value) async {
    // Both branches are awaited so the ternary stays `bool`; awaiting only one
    // side of `?:` leaves the other an untyped expression and the whole
    // expression an Object.
    final bool persisted = _localOnlyPreferenceWriter != null
        ? await _localOnlyPreferenceWriter!(value)
        : await (await SharedPreferences.getInstance()).setBool(
            'localOnly',
            value,
          );
    if (!persisted) throw Exception('local-only preference write failed');
    return persisted;
  }

  /// Persist the local-only choice before publishing the in-memory change.
  Future<void> setLocalOnly(bool value) async {
    if (_deletionInProgress && !value) {
      throw Exception('Local-only mode cannot be disabled during deletion.');
    }
    if (_deletionInProgress) value = true;
    final localOnlyRevision = _localOnlyRevision;
    final deletionRevision = _deletionRevision;
    try {
      await _persistLocalOnlyPreference(value);
    } catch (_) {
      throw Exception('Could not save local-only preference.');
    }

    if (_deletionInProgress || localOnlyRevision != _localOnlyRevision) {
      if (deletionRevision != _deletionRevision && _localOnly) {
        try {
          await _persistLocalOnlyPreference(true);
        } catch (_) {}
        _localOnly = true;
      }
      return;
    }
    _localOnlyRevision++;
    _localOnly = value;
    notifyListeners();
  }

  /// Kept for callers that used the old provider-level label rule.
  static bool shouldLabel(String? ocrText) =>
      MLKitScreenshotAnalyzer.shouldLabel(ocrText);

  /// Process a screenshot through the shared local analyzer.
  Future<bool> _processScreenshotInternal(String imagePath) async {
    if (_deletionInProgress) return false;
    try {
      await _loadSettings();
      if (_deletionInProgress) return false;
      _processingStatus = 'Analyzing locally…';
      _error = null;
      notifyListeners();

      final analysis = await _analyzer.analyze(imagePath);
      if (_deletionInProgress) return false;
      final ocrText = analysis.ocrText.trim();
      // Both derived values are computed here and handed to the record, rather
      // than derived inside the constructor, so the description can be given the
      // exact summary it must not repeat. One call site each: the derivations
      // themselves are shared, see [_deriveSummary] and [_deriveDescription].
      final labels = _mergeObjects(analysis.objects);
      final screenshot = Screenshot(
        id: _uuid.v4(),
        fileName: imagePath.split('/').last,
        filePath: imagePath,
        timestamp: DateTime.now(),
        ocrText: ocrText.isEmpty ? null : ocrText,
        lamType: 'document',
        summary: _deriveSummary(ocrText),
        description: _deriveDescription(objects: labels),
        objects: labels,
        recognitions: const [],
        actionType: null,
        actionCompleted: false,
        actionResult: null,
        suggestedAction: null,
        webResults: const [],
        isFavorite: false,
        tags: const [],
      );
      await _saveScreenshot(screenshot);
      if (_deletionInProgress) return false;
      _processingStatus = 'Local analysis complete';
      notifyListeners();
      return true;
    } catch (e) {
      if (_deletionInProgress) return false;
      _error = 'Local analysis failed: ${e.toString()}';
      _processingStatus = '';
      notifyListeners();
      return false;
    }
  }

  /// Serializes analysis so concurrent calls (watcher poll + manual pick)
  /// never run two local analysis jobs at once. Returns true only after the
  /// screenshot is persisted.
  Future<bool> processScreenshot(String imagePath) async {
    try {
      return await _enqueue<bool>(
        () => _processScreenshotInternal(imagePath),
      );
    } on _ProviderOperationRejected {
      return false;
    }
  }

  /// Analyze one bulk-ingest image through the provider's shared queue.
  /// The native analyzer is not cancellable, so the deletion check is repeated
  /// after it returns and the caller must still use [addFromBulkIngest].
  Future<ScreenshotAnalysisResult> analyzeForBulkIngest(String imagePath) {
    return _enqueue<ScreenshotAnalysisResult>(() async {
      final analysis = await _analyzer.analyze(imagePath);
      if (_deletionInProgress) {
        throw const _ProviderOperationRejected();
      }
      return analysis;
    });
  }

  Future<void> _saveScreenshot(Screenshot screenshot,
      {bool notify = true}) async {
    if (_deletionInProgress) throw const _ProviderOperationRejected();
    await _writeSerialized(
      () => Hive.box('screenshots').put(screenshot.id, screenshot.toJson()),
    );
    if (_deletionInProgress) throw const _ProviderOperationRejected();
    _byPath[screenshot.filePath] = screenshot;
    _insertSorted(screenshot);
    _indexScreenshot(screenshot);
    if (notify) notifyListeners();
  }

  void _insertSorted(Screenshot screenshot) {
    var lo = 0;
    var hi = _screenshots.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_screenshots[mid].timestamp.isAfter(screenshot.timestamp)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _screenshots.insert(lo, screenshot);
  }

  /// Tokenize a text into lowercase words, capped at [_maxWordLength] chars.
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(_wordSplitter)
        .where((w) => w.isNotEmpty && w.length <= _maxWordLength)
        .toList();
  }

  /// The summary a text-free screenshot is stored and displayed with. It is a
  /// display string, never content — see [_displayOnlyValues].
  static const String _noTextSummary = 'No text found';

  /// Values that stand in for absent content: stored, shown to the user, and
  /// indexed nowhere. Held lowercased because [_searchableText] compares a
  /// lowercased value. [_noTextSummary] is the only one written today; add
  /// future sentinels here, never as a check at an indexing call site.
  static final Set<String> _displayOnlyValues = {
    _noTextSummary.toLowerCase(),
  };

  /// [value] trimmed when it carries real searchable content, null when there
  /// is nothing to index: null, blank, or a display-only placeholder.
  ///
  /// This is the single gate every field passes through on its way into the
  /// index, so a placeholder cannot be indexed merely by being stored. It
  /// matters most at the top weight: the text-free summary would otherwise
  /// donate `no`, `text` and `found` at [_wSummary] on every such screenshot,
  /// so a query for "text" outscored genuine matches across the whole library.
  static String? _searchableText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (_displayOnlyValues.contains(trimmed.toLowerCase())) return null;
    return trimmed;
  }

  /// Add [id] with [weight] once for every distinct word in [text] to the
  /// inverted index. Text with nothing to say — blank, or a display-only
  /// placeholder — indexes nothing. See [_searchableText].
  ///
  /// The word set is what makes a weight mean what the weight table says. The
  /// splitter emits a repeated word once per occurrence, and adding the field
  /// weight each time made 'summary = 5' a floor rather than a score: a word
  /// repeated three times in 80 characters scored 15, and beat a screenshot
  /// that mentions the same word once because it happened to say it louder.
  /// Counting each term once per field removes that inflation. It is
  /// deliberately *not* a per-document dedupe: the same term in two different
  /// fields still adds both weights, so a term in `summary` and in `ocrText`
  /// scores 5 + 1.
  void _addTerms(String? text, String id, int weight,
      {Map<String, Map<String, int>>? index}) {
    final searchable = _searchableText(text);
    if (searchable == null) return;
    final idx = index ?? _invertedIndex;
    for (final word in _tokenize(searchable).toSet()) {
      idx.putIfAbsent(word, () => <String, int>{});
      idx[word]![id] = (idx[word]![id] ?? 0) + weight;
    }
  }

  /// Remove [id] from every posting in the inverted index.
  void _removeId(String id) {
    final toDelete = <String>[];
    for (final entry in _invertedIndex.entries) {
      entry.value.remove(id);
      if (entry.value.isEmpty) toDelete.add(entry.key);
    }
    for (final key in toDelete) {
      _invertedIndex.remove(key);
    }
  }

  /// Every field of [s] that reaches the inverted index, in the order and with
  /// the text [_indexScreenshot] feeds it. `lamType` is absent on purpose: see
  /// the weight-table comment above.
  ///
  /// This is the single description of what a record contributes.
  /// [_indexScreenshot] builds the index from it and `explainScores` attributes
  /// a score back through it, so the attribution cannot credit a field the
  /// index never received, nor miss one it did.
  Iterable<_IndexedField> _indexedFields(Screenshot s) sync* {
    yield _IndexedField('summary', s.summary, _wSummary);
    yield _IndexedField('fileName', s.fileName, _wFileName);
    for (final tag in s.tags) {
      yield _IndexedField('tags', tag, _wTags);
    }
    for (final obj in s.objects) {
      yield _IndexedField('objects', obj, _wObjects);
    }
    for (final rec in s.recognitions) {
      yield _IndexedField('recognitions', rec, _wRecognitions);
    }
    for (final kw in s.searchKeywords) {
      yield _IndexedField('searchKeywords', kw, _wSearchKeywords);
    }
    final extracted = s.extractedData;
    if (extracted != null) {
      for (final e in extracted.entries) {
        yield _IndexedField(
            'extractedData', '${e.key} ${e.value}', _wExtractedData);
      }
    }
    // OCR text gets weight 1 but is capped to avoid bloating the index
    final ocr = s.ocrText ?? '';
    if (ocr.isNotEmpty) {
      yield _IndexedField(
          'ocrText',
          ocr.length > _ocrBlobCap ? ocr.substring(0, _ocrBlobCap) : ocr,
          _wOcr);
    }
  }

  /// Build the inverted index for a single screenshot.
  void _indexScreenshot(Screenshot s) {
    // Remove old tags from tag index
    for (final ids in _tagIndex.values) {
      ids.remove(s.id);
    }
    // Remove old inverted index entries
    _removeId(s.id);

    // Build fresh inverted index with field weights
    for (final _IndexedField field in _indexedFields(s)) {
      _addTerms(field.text, s.id, field.weight);
    }

    // Rebuild tag index
    for (final t in s.tags) {
      _tagIndex.putIfAbsent(t.toLowerCase(), () => <String>{}).add(s.id);
    }
  }

  void _rebuildIndexes() {
    _invertedIndex = {};
    _tagIndex = {};
    for (final s in _screenshots) {
      _indexScreenshot(s);
    }
  }

  Future<void> _writeSerialized(Future<void> Function() op) {
    if (_deletionInProgress) {
      return Future<void>.error(const _ProviderOperationRejected());
    }
    final result = _writeTail.then((_) {
      if (_deletionInProgress) {
        throw const _ProviderOperationRejected();
      }
      return op();
    });
    _writeTail = result.catchError((_) {});
    return result;
  }

  /// Add a record from the bulk ingest pass. Real capture time, no
  /// prefs/consent reads, no per-item rebuild (notify throttled).
  /// [objects] carries on-device visual labels for text-less images.
  Future<String?> addFromBulkIngest({
    required String path,
    required DateTime capturedAt,
    required String ocrText,
    List<String>? objects,
  }) async {
    try {
      return await _enqueue<String?>(
        () => _addFromBulkIngestInternal(
          path: path,
          capturedAt: capturedAt,
          ocrText: ocrText,
          objects: objects,
        ),
      );
    } on _ProviderOperationRejected {
      return null;
    }
  }

  Future<String?> _addFromBulkIngestInternal({
    required String path,
    required DateTime capturedAt,
    required String ocrText,
    List<String>? objects,
  }) async {
    if (_deletionInProgress || _byPath.containsKey(path)) return null;
    final ocr = ocrText.trim();
    // The same two derivations the single-image path uses, from the same two
    // helpers. A record ingested in bulk and a record analyzed one at a time
    // must not be describable in two different ways.
    final labels = _mergeObjects(objects);
    final screenshot = Screenshot(
      id: _uuid.v4(),
      fileName: path.split('/').last,
      filePath: path,
      timestamp: capturedAt,
      ocrText: ocr.isEmpty ? null : ocr,
      lamType: 'document',
      summary: _deriveSummary(ocr),
      description: _deriveDescription(objects: labels),
      objects: labels,
      recognitions: const [],
      actionType: null,
      actionCompleted: false,
      actionResult: null,
      suggestedAction: null,
      webResults: const [],
      isFavorite: false,
      tags: const [],
    );
    await _writeSerialized(
      () => Hive.box('screenshots').put(screenshot.id, screenshot.toJson()),
    );
    if (_deletionInProgress) return null;
    _byPath[path] = screenshot;
    _insertSorted(screenshot);
    _indexScreenshot(screenshot);
    _pendingNotifies++;
    if (_pendingNotifies >= _bulkNotifyInterval) {
      _pendingNotifies = 0;
      notifyListeners();
    }
    return screenshot.id;
  }

  /// Flush any pending throttled bulk notifications (end of a pass).
  void flushBulkNotify() {
    if (_pendingNotifies > 0) {
      _pendingNotifies = 0;
      notifyListeners();
    }
  }

  /// Dedupe + cap the visual labels stored on the frozen `objects` field.
  List<String> _mergeObjects(List<String>? incoming) {
    if (incoming == null || incoming.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final o in incoming) {
      final t = o.trim();
      if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
      out.add(t);
      if (out.length >= 12) break;
    }
    return out;
  }

  /// The display summary for a locally written record: the first non-empty OCR
  /// line, capped at [_summaryChars] characters, or [_noTextSummary] when the
  /// image has no readable text at all.
  ///
  /// Extracted, with the logic untouched, so both local write paths derive it in
  /// one place. Duplicating it in a second call site is what let the two write
  /// paths drift on everything else too, and this is the value a record is
  /// displayed by everywhere from here on.
  static String _deriveSummary(String ocrText) {
    if (ocrText.isEmpty) return _noTextSummary;
    final firstLine = ocrText.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
    final source = firstLine.isNotEmpty ? firstLine : ocrText;
    return source.length > _summaryChars
        ? source.substring(0, _summaryChars)
        : source;
  }

  static const int _summaryChars = 80;

  /// How many visual labels a description names.
  ///
  /// Three is where a description stops being a description and becomes a dump.
  /// Nothing is lost by the cap: the full label list is indexed field by field at
  /// [_wObjects] and is already rendered in its own line of the model prompt, so
  /// a description that listed all twelve would add reading, not meaning.
  static const int _maxDescriptionLabels = 3;

  /// The one-sentence description both local write paths store.
  ///
  /// Derived, never generated: no model, no network, no inference. Everything it
  /// says was already computed at index time, so the same record yields the same
  /// string on every device and no fact reaches the prompt that the index does
  /// not already hold.
  ///
  /// Why the field was worth filling: `ChatEngine.buildContextText` renders it
  /// into the prompt the on-device model receives — and on every record it was
  /// null. So the prompt handed the model `Summary:` (the first 80 characters of
  /// the OCR) immediately followed by `Text:` beginning with those same 80
  /// characters. Duplicated tokens, zero semantics.
  ///
  /// **What it deliberately does not do: quote the OCR.** An earlier draft
  /// appended the text past `summary`, and it read well — and it was wrong, for
  /// a reason the recall harness had already measured about `summary`: a field
  /// that restates words another field already holds takes weight units in
  /// proportion to how much it repeats. Quoting the tail turned a second-line
  /// term into 4 + 1 = 5 points where it had earned 1, and the three tests that
  /// pin "this term is only in `ocrText`" all failed at once. That is the
  /// duplicate-OCR defect being fixed, rebuilt one field over.
  ///
  /// So it says only what the OCR cannot: what the picture *is*, from the ML Kit
  /// labels. Those are indexed already, at [_wObjects]. The field itself is
  /// indexed nowhere: a caption naming three of a record's twelve labels carries
  /// nothing `objects` does not, so weighting it would count those label tokens a
  /// second time — the same duplicate-field inflation `summary` was cleared of,
  /// one field over. It earns its place by being in the prompt, not in the index.
  ///
  /// Returns null when there are no labels. That is a clean empty rather than a
  /// filler sentence: a record with no labels is one whose only content is text,
  /// and `summary` at 5 plus `ocrText` at 1 already cover every token in it. A
  /// description here could only restate them.
  static String? _deriveDescription({required List<String> objects}) {
    final labels = _labelPhrase(objects);
    if (labels == null) return null;
    return 'Looks like $labels.';
  }

  /// "a receipt and food" from the visual labels.
  ///
  /// ML Kit returns single lowercase labels such as `receipt` or
  /// `bicycle helmet`, so they read as a noun phrase once an article is in
  /// front. Lowercased here because the sentence puts them mid-clause, and
  /// de-duplicated by the caller's `_mergeObjects` rather than again here.
  ///
  /// The article is also index noise, and deliberately so little of it: `a` is
  /// unreachable by any query (the minimum-query gate rejects a one-character
  /// term, and prefix matching only ever widens a term, never a posting), so
  /// the indefinite article costs the index nothing.
  static String? _labelPhrase(List<String> objects) {
    final words = <String>[
      for (final o in objects)
        if (o.trim().isNotEmpty) o.trim().toLowerCase(),
    ].take(_maxDescriptionLabels).toList();
    if (words.isEmpty) return null;
    final joined = words.length == 1
        ? words.single
        : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
    return '${_indefiniteArticle(words.first)} $joined';
  }

  /// "a" or "an", from the first letter.
  ///
  /// Approximate on purpose. It is only ever read inside one sentence built from
  /// ML Kit's own labels, and an article chosen wrong there is not worth a
  /// pronunciation table or an exception list.
  static String _indefiniteArticle(String word) =>
      'aeiou'.contains(word[0].toLowerCase()) ? 'an' : 'a';

  Future<Directory> _defaultImportDirectory() async {
    final documents = _documentsDirectoryLoader != null
        ? await _documentsDirectoryLoader!()
        : await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'sift_imports'));
  }

  /// Add user-picked images to the library: each file is copied into Sift's
  /// private folder, analyzed on-device, then indexed. Dedupes by (file name
  /// + size) against existing entries. [importDir] is injectable for tests
  /// (defaults to the app documents dir). Per-file work is routed through
  /// [_queueTail] so analysis never runs concurrently with the watcher tick,
  /// the ingest pass, or manual processing.
  Future<int> importImages(
    List<String> pickedPaths, {
    Directory? importDir,
  }) async {
    if (_deletionInProgress) return 0;
    var added = 0;
    if (importDir != null) _importDirectoryOverride = importDir;
    final dir = importDir ?? await _defaultImportDirectory();
    if (_deletionInProgress) return 0;
    try {
      await dir.create(recursive: true);
    } catch (_) {}
    if (_deletionInProgress) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
      return 0;
    }
    for (final src in pickedPaths) {
      if (_deletionInProgress) break;
      final result = _enqueue<String?>(() => _importOne(src, dir));
      String? id;
      try {
        id = await result;
      } on _ProviderOperationRejected {
        break;
      }
      if (id != null) added++;
    }
    flushBulkNotify();
    notifyListeners();
    return added;
  }

  Future<void> _deleteImportedFile(String path, Directory dir) async {
    final root = p.normalize(p.absolute(dir.path));
    final candidate = p.normalize(p.absolute(path));
    if (candidate == root || !p.isWithin(root, candidate)) return;
    final file = File(candidate);
    if (await file.exists()) await file.delete();
  }

  /// Copy, analyze, and index one picked file. Returns the new screenshot id,
  /// or null when the file is skipped (missing, oversized, disallowed
  /// name/extension, or already imported). Never throws; per-file failures
  /// are logged and skipped so one bad file can't sink the batch.
  Future<String?> _importOne(String src, Directory dir) async {
    String? destPath;
    try {
      if (_deletionInProgress) return null;
      final srcFile = File(src);
      if (!await srcFile.exists()) return null;
      final size = await srcFile.length();
      if (size > _maxImportBytes) return null;
      final name = p.basename(src);
      if (!_acceptableImportName(name)) return null;
      final alreadyImported = _screenshots.any((s) {
        // Imported copies live as "{uuid}_<original name>"; match on the
        // suffix plus an exact byte size so re-picking the same photo
        // never creates a duplicate.
        if (!s.fileName.endsWith(name)) return false;
        final f = File(s.filePath);
        try {
          return f.existsSync() && f.lengthSync() == size;
        } catch (_) {
          return false;
        }
      });
      if (alreadyImported) return null;
      if (_deletionInProgress) return null;
      final copiedPath = '${dir.path}/${_uuid.v4()}_$name';
      destPath = copiedPath;
      await srcFile.copy(copiedPath);
      if (_deletionInProgress) {
        await _deleteImportedFile(copiedPath, dir);
        return null;
      }
      final analysis = await _analyzer.analyze(copiedPath);
      if (_deletionInProgress) {
        await _deleteImportedFile(copiedPath, dir);
        return null;
      }
      // This import already occupies the provider queue slot.
      final id = await _addFromBulkIngestInternal(
        path: copiedPath,
        capturedAt: _capturedAtFor(srcFile),
        ocrText: analysis.ocrText,
        objects: analysis.objects,
      );
      if (id == null && _deletionInProgress) {
        await _deleteImportedFile(copiedPath, dir);
      }
      return id;
    } catch (e) {
      if (destPath != null) await _deleteImportedFile(destPath, dir);
      debugPrint('Import failed for $src: $e');
      return null;
    }
  }

  bool _acceptableImportName(String name) {
    if (name.isEmpty) return false;
    if (name.contains('..')) return false;
    if (name.contains('/') || name.contains('\\')) return false;
    for (final code in name.codeUnits) {
      if (code < 0x20 || code == 0x7f) return false;
    }
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false;
    return _importExtensions.contains(name.substring(dot).toLowerCase());
  }

  DateTime _capturedAtFor(File f) {
    try {
      return f.statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<void> hideScreenshot(String path) async {
    if (_deletionInProgress) return;
    _hiddenPaths.add(path);
    if (Hive.isBoxOpen('hidden_paths')) {
      if (_deletionInProgress) return;
      try {
        await _writeSerialized(
          () => Hive.box('hidden_paths').put(
            path,
            DateTime.now().toIso8601String(),
          ),
        );
      } on _ProviderOperationRejected {
        return;
      }
    }
    if (_deletionInProgress) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('watcher_seen') ?? <String>[];
    if (!seen.contains(path)) {
      seen.add(path);
      await prefs.setStringList('watcher_seen', seen);
    }
    if (_deletionInProgress) return;
    notifyListeners();
  }

  Future<void> unhideScreenshot(String path) async {
    if (_deletionInProgress) return;
    _hiddenPaths.remove(path);
    if (Hive.isBoxOpen('hidden_paths')) {
      try {
        await _writeSerialized(() => Hive.box('hidden_paths').delete(path));
      } on _ProviderOperationRejected {
        return;
      }
    }
    if (_deletionInProgress) return;
    notifyListeners();
  }

  /// Manually run the suggested action stored on a screenshot.
  Future<ActionResult?> runSuggestedAction(Screenshot s) async {
    try {
      return await _enqueue<ActionResult?>(
        () => _runSuggestedActionInternal(s),
      );
    } on _ProviderOperationRejected {
      return null;
    }
  }

  Future<ActionResult?> _runSuggestedActionInternal(Screenshot s) async {
    if (_deletionInProgress) return null;
    final suggested = s.suggestedAction;
    if (suggested == null || suggested.isEmpty) return null;

    // Records persisted by the old cloud analyzer can hold model-generated
    // maps, so the type and every field it needs are validated before any
    // calendar/reminder/list write. Rejection is a sanitized, fixed message:
    // no untrusted value is ever echoed into the UI.
    final validation = LAMAction.validate(suggested);
    if (!validation.isValid) {
      return _rejectSuggestedAction(s, validation.reason!);
    }
    final action = validation.action!;
    if (action.type == 'none') return null;

    try {
      _processingStatus = 'Running action…';
      notifyListeners();

      final result = await ActionService().executeAction(action, s.id);
      if (_deletionInProgress) return null;
      s.actionCompleted = result.success;
      s.actionResult = result.message;
      await _writeSerialized(
        () => Hive.box('screenshots').put(s.id, s.toJson()),
      );
      if (_deletionInProgress) return null;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('Action failed: $e');
      return null;
    } finally {
      _processingStatus = s.summary ?? '';
      notifyListeners();
    }
  }

  /// Record a rejected suggested action: fixed copy only, no platform call.
  Future<ActionResult?> _rejectSuggestedAction(
    Screenshot s,
    String reason,
  ) async {
    debugPrint('Rejected suggested action on ${s.id}: $reason');
    s.actionCompleted = false;
    s.actionResult = reason;
    _error = reason;
    try {
      await _writeSerialized(
        () => Hive.box('screenshots').put(s.id, s.toJson()),
      );
    } on _ProviderOperationRejected {
      return null;
    }
    if (_deletionInProgress) return null;
    notifyListeners();
    return null;
  }

  /// Manually look up matching web links for a screenshot.
  Future<void> findOnline(Screenshot s) async {
    if (_deletionInProgress) return;
    final prefs = await SharedPreferences.getInstance();
    if (_deletionInProgress) return;
    if (_localOnly || !(prefs.getBool('privacy_consent') ?? false)) {
      _error = 'Privacy consent is required before searching the web.';
      _processingStatus = '';
      notifyListeners();
      return;
    }

    _processingStatus = 'Searching the web…';
    notifyListeners();
    try {
      final savedYouTubeKey = (prefs.getString('key_youtube') ?? '').trim();
      // Only a key the user saved counts: no bundled or CI-injected fallback,
      // so an unsaved key means the lookup runs keyless.
      final youTubeKey = savedYouTubeKey.isEmpty ? null : savedYouTubeKey;
      final results = await WebLookupService().lookup(
        extractedText: s.ocrText ?? '',
        summary: s.summary ?? '',
        recognitions: s.recognitions,
        objects: s.objects,
        youTubeApiKey: youTubeKey,
      );
      if (_deletionInProgress) return;
      s.webResults
        ..clear()
        ..addAll(results.map((r) => {'title': r.title, 'url': r.url}));
      try {
        await _writeSerialized(
          () => Hive.box('screenshots').put(s.id, s.toJson()),
        );
      } on _ProviderOperationRejected {
        return;
      }
      if (_deletionInProgress) return;
      notifyListeners();
    } catch (e) {
      debugPrint('Web lookup failed: $e');
      s.webResults.clear();
    } finally {
      _processingStatus = s.summary ?? '';
      notifyListeners();
    }
  }

  /// Wipe everything Sift owns. Gallery originals are never touched. Only
  /// files in the app-private `sift_imports` directory are removed from disk.
  /// [importDir] is an injectable test seam for that private directory.
  ///
  /// The private folder is resolved and removed *before* any box or preference
  /// is cleared. A folder that cannot be deleted throws a sanitized
  /// [DataDeletionException] with nothing destroyed. Past that point the wipe is
  /// under way, so a failed box or preference write throws a sanitized
  /// [StateError] instead of reporting success — the caller must surface that
  /// even though some data may already be gone.
  Future<void> deleteEverything({Directory? importDir}) {
    final active = _deletionFuture;
    if (active != null) return active;
    final operation = _deleteEverything(importDir: importDir);
    _deletionFuture = operation;
    return operation.whenComplete(() {
      if (identical(_deletionFuture, operation)) _deletionFuture = null;
    });
  }

  Future<void> _deleteEverything({Directory? importDir}) async {
    _deletionInProgress = true;
    _deletionRevision++;
    _localOnlyRevision++;
    _localOnly = true;

    try {
      notifyListeners();
      final stopHook = _ingestStopHook;
      if (stopHook != null) {
        try {
          await stopHook();
        } catch (e) {
          debugPrint('Ingest stop during deletion failed: $e');
        }
      }

      final paths = <String>{for (final s in _screenshots) s.filePath};
      await _queueTail;
      await _writeTail;
      if (Hive.isBoxOpen('screenshots')) {
        for (final value in Hive.box('screenshots').values) {
          if (value is Map && value['filePath'] is String) {
            paths.add(value['filePath'] as String);
          }
        }
      }

      // Resolve and remove the private folder first: if it cannot be deleted,
      // nothing else is touched, so the caller can report an honest failure.
      await _deleteImportedDirectory(importDir);
      await _clearBoxIfOpen('screenshots');
      await _clearBoxIfOpen('actions');
      await _clearBoxIfOpen('chat');
      await _clearBoxIfOpen('ingest');
      await _clearBoxIfOpen('hidden_paths');

      final prefs = await SharedPreferences.getInstance();
      // A false here means provider/API keys or consent flags may still be on
      // disk, so the wipe cannot be reported as complete.
      if (!await _preferencesClearer(prefs)) {
        throw StateError('preference clear failed');
      }
      if (_localOnlyPreferenceWriter != null) {
        final writerSaved = await _localOnlyPreferenceWriter!(true);
        if (!writerSaved) {
          throw StateError('local-only preference write failed');
        }
      }
      if (!await prefs.setBool('localOnly', true)) {
        throw StateError('local-only preference write failed');
      }
      if (!await prefs.setBool('library_indexed', true)) {
        throw StateError('library index preference write failed');
      }
      if (paths.isNotEmpty) {
        final seenSaved = await prefs.setStringList(
          'watcher_seen',
          paths.toList(),
        );
        if (!seenSaved) {
          throw StateError('watcher seen preference write failed');
        }
      }

      _screenshots = [];
      _byPath = {};
      _hiddenPaths = {};
      _invertedIndex = {};
      _tagIndex = {};
      _error = null;
      _processingStatus = '';
      _pendingNotifies = 0;
      _localOnlyRevision++;
      _localOnly = true;
    } finally {
      _deletionInProgress = false;
      _queueTail = Future.value();
      _writeTail = Future.value();
      notifyListeners();
    }
  }

  Future<void> _clearBoxIfOpen(String name) async {
    if (Hive.isBoxOpen(name)) await Hive.box(name).clear();
  }

  /// Resolve the app-private import folder and remove it. Throws a sanitized
  /// [DataDeletionException] when the folder cannot be located or deleted —
  /// the caller must not treat that as a completed wipe. Nothing is logged with
  /// the raw platform error, which can contain paths.
  Future<void> _deleteImportedDirectory(Directory? importDir) async {
    final Directory directory;
    try {
      final resolved = importDir ??
          _importDirectoryOverride ??
          await _defaultImportDirectory();
      directory = resolved;
    } catch (e) {
      debugPrint('Could not resolve the import directory for deletion: $e');
      throw const DataDeletionException(
        "Could not delete everything: Sift could not locate its private "
        "import folder, so nothing was deleted.",
      );
    }

    try {
      if (await directory.exists()) {
        await _importDirectoryCleaner(directory);
      }
    } catch (e) {
      debugPrint('Could not delete the import directory: $e');
      throw const DataDeletionException(
        "Could not delete everything: Sift could not remove its private "
        "import folder, so nothing was deleted.",
      );
    }
  }

  /// English words dropped from a query before it is scored on.
  ///
  /// This is a short list of *function* words, not a language model's stop-word
  /// list. Every entry is here because it breaks retrieval in this index, in a
  /// way that can be named; anything that could plausibly be the content a user
  /// typed is left out on purpose.
  ///
  /// Two separate things break, and both are visible in one plain question —
  /// "can you please show me my food screenshots from last week":
  ///
  ///  * **The term cap.** [_maxQueryTerms] keeps the *first* six words, so an
  ///    eleven-word question was scored on `can you please show me my` and
  ///    `food` and `screenshots` were discarded before the index was ever read.
  ///    Filtering first is what lets the content words reach it.
  ///  * **Prefix matching.** A term matches every indexed word that *starts*
  ///    with it (see [search]), so a function word reaches records that never
  ///    contained anything the user asked for. `me` -> `menu` is the measured
  ///    one; `in` -> `invoice`, `an` -> `android`, `at` -> `atm` and
  ///    `be` -> `berlin` are the same accident. Those hits carry a real weight,
  ///    so they can outrank the screenshot the user actually meant.
  ///
  /// Grouped by what each group breaks:
  ///
  ///  * **Articles.** `a` reaches every word starting with a, `an` reaches
  ///    `android`/`answer`, `the` reaches `theme`/`their`. No discriminative
  ///    power at all, only dilution.
  ///  * **Pronouns, possessives, demonstratives, question words.** They name
  ///    the asker, not the thing: `i`, `me`, `my`, `you`, `it`, `this`, `what`,
  ///    `which`. `me` -> `menu` is the false positive this list exists for.
  ///  * **Prepositions, including the time words questions lean on.** "from
  ///    last week" is grammar around the content; the content is `week`. `on` ->
  ///    `onion`, `in` -> `invoice` and `to` -> `total` are `me` -> `menu`
  ///    again. `last`/`next`/`past` go because they are prepositions in "last
  ///    week" but would otherwise reach `laptop` and `lunch`.
  ///  * **Conjunctions.** `or` -> `orange`/`order` and `so` -> `social`/`software`
  ///    are real hits on the wrong screenshot; `and`, `but`, `if`, `than`,
  ///    `because` name no content either.
  ///  * **Auxiliaries, copula and modals.** `is`, `was`, `do`, `have`, `can`,
  ///    `could`, `would` carry the question, never its subject: `can` ->
  ///    `cancelled`/`candy`, `is` -> `istanbul`.
  ///  * **Asking-verbs and fillers.** `please`, `show`, `find`, `give`, `tell`,
  ///    `help`, `hey`, `thanks`. The instruction to the app, not the query —
  ///    and because every question opens with them, they are also the words
  ///    most likely to be what the term cap keeps.
  ///  * **Sift's own nouns, singular.** `screenshot`, `image`, `picture`,
  ///    `photo`, `pic`, `shot`, `phone`, `gallery`. Naming the medium is not
  ///    naming the content, and the singular `screenshot` is the worst term in
  ///    the set: `addFromBulkIngest` derives `fileName` as
  ///    `Screenshot_<timestamp>.png`, so that one word is in the index on
  ///    *every* record, at [_wFileName]. It cannot separate two screenshots
  ///    from each other while still costing a cap slot.
  ///
  ///    Only the singular is dropped, and that is the whole justification: no
  ///    production file name is ever `Screenshots_…`, so the plurals are not
  ///    the non-discriminative term. Keeping `screenshots` also keeps the word
  ///    of the worked example alive — "food screenshots" is a person naming a
  ///    subject and a medium, and `food` is the half that carries the content.
  ///
  /// Matched case-insensitively by being compared against the already-lowercased
  /// term: OCR and typed input disagree about case and the index is lowercase,
  /// so a case-sensitive set would miss the very words it lists. Consulted only
  /// for a non-CJK query — see [_queryTerms].
  static const Set<String> _queryStopWords = <String>{
    // Articles.
    'a', 'an', 'the',
    // Pronouns, possessives, demonstratives, question words.
    'i', 'me', 'my', 'we', 'us', 'our', 'you', 'your',
    'he', 'him', 'his', 'she', 'her', 'it', 'its',
    'they', 'them', 'their', 'this', 'that', 'these', 'those',
    'there', 'who', 'which', 'what',
    // Prepositions, including the time words questions lean on.
    'of', 'in', 'on', 'at', 'to', 'for', 'with', 'from', 'by', 'about',
    'into', 'up', 'out', 'over', 'under', 'after', 'before', 'between',
    'during', 'near', 'through', 'against', 'last', 'next', 'past',
    // Conjunctions.
    'and', 'or', 'but', 'if', 'then', 'than', 'so', 'because', 'as',
    // Auxiliaries, copula, modals.
    'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'do', 'does', 'did', 'have', 'has', 'had',
    'can', 'could', 'will', 'would', 'shall', 'should', 'may', 'might',
    'must',
    // Asking-verbs and fillers.
    'please', 'show', 'find', 'give', 'tell', 'help', 'see', 'want', 'need',
    'let', 'thanks', 'thank', 'hey', 'hi', 'hello',
    // Sift's own nouns, singular only: see the doc comment for why the
    // plurals stay searchable.
    'screenshot', 'image', 'picture', 'photo', 'pic', 'shot', 'phone',
    'gallery',
  };

  /// The terms [search] scores on, or null when the query cannot be searched at
  /// all. Shared with [explainScores] so both take the same minimum-query gate,
  /// the same splitter, the same stop-word filter and the same term cap.
  List<String>? _queryTerms(String query) {
    // Min-query gate: 2 chars for non-CJK, 1 char for CJK (single kanji
    // queries are legitimate). Unchanged: it runs before anything else and the
    // filter below never sees a query it rejected.
    if (query.trim().length < 2 && !_cjk.hasMatch(query)) return null;

    final raw = query
        .toLowerCase()
        .split(_wordSplitter)
        .where((t) => t.isNotEmpty)
        .toList();
    if (raw.isEmpty) return null;

    // Drop one-character terms before anything else scores them. The splitter
    // breaks on the apostrophe, so "week's" tokenises to ['week', 's']; `s` is
    // not a stop word, and prefix matching turns it into a query for every
    // indexed word that begins with `s`. In "what's in my shopping list" that is
    // three of six terms spent on one letter.
    //
    // One character is kept when it is CJK, because a single kanji is a word:
    // the gate above already admits a one-character CJK query for the same
    // reason, so rejecting the term here would leave such a query admitted and
    // then unsearchable.
    final terms = raw.where((t) => t.length > 1 || _cjk.hasMatch(t)).toList();

    // Drop the function words BEFORE the cap, not after. Capping first throws
    // away the content of any question longer than [_maxQueryTerms] words: the
    // cap takes the first six, so "can you please show me my food screenshots"
    // was scored on `can you please show me my` and never reached `food`. See
    // [_queryStopWords] for what each dropped group breaks.
    //
    // CJK takes the original list untouched. There are no whitespace-delimited
    // words to recognise — the splitter hands back whole runs, so '咖啡店的菜单'
    // is one term, not four — and a set of English function words could only
    // remove real content there. The guard makes that path byte-identical
    // instead of relying on the set happening to contain no CJK.
    final filtered = _cjk.hasMatch(query)
        ? terms
        : terms.where((t) => !_queryStopWords.contains(t)).toList();

    // A query made of nothing but stop words — "screenshot", "show me" — would
    // filter down to an empty list and therefore match nothing at all, which a
    // user cannot tell from "you have no such screenshot". Fall back to the
    // unfiltered terms so those keep searching exactly as they did before.
    // Falling back to [raw] rather than to [terms] also restores the one-character
    // terms for a query that is nothing but one-character terms, so that query
    // still searches rather than going quiet.
    final kept = filtered.isEmpty ? raw : filtered;

    // The cap is unchanged, and it is applied to the filtered list, so it only
    // bites on a query with more than six *content* words.
    if (kept.length > _maxQueryTerms) {
      return kept.sublist(0, _maxQueryTerms);
    }
    return kept;
  }

  /// Score every record the terms reach and order them the way [search] ranks
  /// them: highest score first, hidden screenshots dropped, ties left to the
  /// sort. Both [search] and [explainScores] read this, so an explanation
  /// cannot describe a different set of results, or a different order, from the
  /// ranking it is explaining.
  ///
  /// A term can match several indexed words at once ('bag' over 'bag' and
  /// 'bagel'), and a document holding both is scored for both — the exact word
  /// carries its own weight on top of the extension, which is what keeps a
  /// literal hit ahead of a merely-prefixed one.
  List<({Screenshot screenshot, int score})> _ranked(List<String> terms) {
    // Collect candidate screenshot IDs and sum their weighted scores.
    final scores = <String, int>{};
    for (final term in terms) {
      for (final posting in _invertedIndex.entries) {
        if (!posting.key.startsWith(term)) continue;
        for (final entry in posting.value.entries) {
          // Only count hidden-path-free screenshots (checked later).
          scores[entry.key] = (scores[entry.key] ?? 0) + entry.value;
        }
      }
    }

    if (scores.isEmpty) return const [];

    // Build scored list, filtering hidden screenshots.
    final scored = <({Screenshot screenshot, int score})>[];
    for (final entry in scores.entries) {
      final s = _byPath.values.cast<Screenshot?>().firstWhere(
            (ss) => ss!.id == entry.key,
            orElse: () => null,
          );
      if (s == null || _hiddenPaths.contains(s.filePath)) continue;
      scored.add((screenshot: s, score: entry.value));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Local keyword search using inverted index with field weighting.
  /// Returns most relevant visible screenshots first. O(t × avg_postings)
  /// instead of O(n × t) for the old linear scan.
  ///
  /// A query term matches every indexed term that *starts with* it, so a
  /// partial word finds its completion. The search box is as-you-type with a
  /// debounce, so a user is mid-word most of the time and 'bag' returning
  /// nothing for a screenshot that plainly says "Bagel…" reads as broken
  /// search. This is query-side only: the index is untouched, so no prefix
  /// entries are stored and no existing query's score moves. Stemming and
  /// fuzzy matching are still out — a term in the *middle* of an indexed word
  /// does not match, and a query for 'ag' does not find 'bagel'.
  List<Screenshot> search(String query, {int limit = 5}) {
    final terms = _queryTerms(query);
    if (terms == null) return [];
    return _ranked(terms).take(limit).map((e) => e.screenshot).toList();
  }

  /// The same records [search] returns for [query], in the same rank order, each
  /// carrying the score it was ranked on and a breakdown of which field earned
  /// each part of that score. Additive and read-only.
  ///
  /// The totals here are not a re-computation: they come out of the same
  /// [_ranked] call [search] ranks on, so `score` here is literally the score
  /// that produced the rank. Calling this changes nothing — the index is not
  /// touched, no field is reindexed, and [search] returns exactly what it
  /// returned before.
  ///
  /// The per-field weights are derived back through [_indexedFields] — the same
  /// description of the index that [_indexScreenshot] builds from — using the
  /// same weights, the same tokenizer and the same [_searchableText] gate. That
  /// makes the breakdown a *decomposition* of the score rather than a second
  /// scorer, and it is checked rather than trusted:
  /// [SearchScoreExplanation.contributionsMatchScore] is false whenever the
  /// parts do not add up to the total, which is what a future write path that
  /// indexes a field this split does not know about would look like. Read the
  /// flag instead of assuming the split is complete.
  SearchExplanation explainScores(String query, {int limit = 5}) {
    final terms = _queryTerms(query);
    if (terms == null) {
      return SearchExplanation(query: query, results: const []);
    }
    return SearchExplanation(
      query: query,
      results: [
        for (final ({Screenshot screenshot, int score}) e
            in _ranked(terms).take(limit))
          _explain(e.screenshot, terms, e.score),
      ],
    );
  }

  /// Split one record's score into the per-field weights that produced it.
  ///
  /// A term matches a field's word when the *word* starts with the term, which
  /// is the same rule [_ranked] applies to the index key — and a word reached by
  /// two terms is credited twice, because [_ranked] visits its posting once per
  /// term. The result therefore reproduces the indexed score for [terms] field
  /// by field rather than approximating it.
  SearchScoreExplanation _explain(Screenshot s, List<String> terms, int score) {
    final byField = <String, int>{};
    for (final _IndexedField field in _indexedFields(s)) {
      final searchable = _searchableText(field.text);
      if (searchable == null) continue;
      final words = _tokenize(searchable).toSet();
      var earned = 0;
      for (final term in terms) {
        for (final word in words) {
          if (word.startsWith(term)) {
            earned += field.weight;
          }
        }
      }
      if (earned > 0) {
        byField[field.field] = (byField[field.field] ?? 0) + earned;
      }
    }
    final total = byField.values.fold(0, (a, b) => a + b);
    return SearchScoreExplanation(
      id: s.id,
      fileName: s.fileName,
      score: score,
      fieldContributions: byField,
      contributionsSum: total,
      contributionsMatchScore: total == score,
    );
  }

  Future<void> deleteScreenshot(String id) async {
    if (_deletionInProgress) return;
    final matches = _screenshots.where((s) => s.id == id).toList();
    if (matches.isNotEmpty) {
      _byPath.remove(matches.first.filePath);
      _removeId(id);
      for (final ids in _tagIndex.values) {
        ids.remove(id);
      }
    }
    try {
      await _writeSerialized(() => Hive.box('screenshots').delete(id));
    } on _ProviderOperationRejected {
      return;
    }
    if (_deletionInProgress) return;
    _screenshots.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void setShowFavoritesOnly(bool value) {
    _showFavoritesOnly = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    if (_deletionInProgress) return;
    final matches = _screenshots.where((s) => s.id == id);
    if (matches.isEmpty) return;
    final screenshot = matches.first;
    screenshot.isFavorite = !screenshot.isFavorite;
    notifyListeners();
    try {
      await _writeSerialized(
        () => Hive.box('screenshots').put(id, screenshot.toJson()),
      );
    } catch (e) {
      screenshot.isFavorite = !screenshot.isFavorite;
      notifyListeners();
      debugPrint('Failed to persist favorite state: $e');
    }
  }

  Future<bool> addTag(String id, String tag) async {
    if (_deletionInProgress) return false;
    var trimmed = tag.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > 50) trimmed = trimmed.substring(0, 50);
    final matches = _screenshots.where((s) => s.id == id);
    if (matches.isEmpty) return false;
    final screenshot = matches.first;
    if (screenshot.tags.length >= 25) return false;
    final alreadyPresent = screenshot.tags.any(
      (t) => t.toLowerCase() == trimmed.toLowerCase(),
    );
    if (alreadyPresent) return false;
    screenshot.tags = [...screenshot.tags, trimmed];
    _indexScreenshot(screenshot);
    notifyListeners();
    try {
      await _writeSerialized(
        () => Hive.box('screenshots').put(id, screenshot.toJson()),
      );
      if (_deletionInProgress) return false;
      return true;
    } catch (e) {
      if (_deletionInProgress) return false;
      screenshot.tags = [...screenshot.tags]..remove(trimmed);
      _indexScreenshot(screenshot);
      notifyListeners();
      debugPrint('Failed to persist tag: $e');
      return false;
    }
  }

  Future<bool> removeTag(String id, String tag) async {
    if (_deletionInProgress) return false;
    final matches = _screenshots.where((s) => s.id == id);
    if (matches.isEmpty) return false;
    final screenshot = matches.first;
    final i = screenshot.tags.indexOf(tag);
    if (i < 0) return false;
    screenshot.tags = [...screenshot.tags]..removeAt(i);
    _indexScreenshot(screenshot);
    notifyListeners();
    try {
      await _writeSerialized(
        () => Hive.box('screenshots').put(id, screenshot.toJson()),
      );
      if (_deletionInProgress) return false;
      return true;
    } catch (e) {
      if (_deletionInProgress) return false;
      screenshot.tags = [...screenshot.tags]..insert(i, tag);
      _indexScreenshot(screenshot);
      notifyListeners();
      debugPrint('Failed to persist tag removal: $e');
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearStatus() {
    _processingStatus = '';
    notifyListeners();
  }
}
