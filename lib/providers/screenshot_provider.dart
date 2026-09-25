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
  }) : _analyzer = analyzer ??
            MLKitScreenshotAnalyzer(ocr: ocr, labeler: labeler),
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
  // Field weights: summary=5, description=4, tags=3, objects/recognitions/lamType=2, ocrText/fileName/extractedData=1.
  static const int _wSummary = 5;
  static const int _wDescription = 4;
  static const int _wTags = 3;
  static const int _wObjects = 2;
  static const int _wRecognitions = 2;
  static const int _wLamType = 2;
  static const int _wOcr = 1;
  static const int _wFileName = 1;
  static const int _wExtractedData = 1;
  static const int _wSearchKeywords = 4;
  static const int _maxWordLength = 64;
  static final RegExp _wordSplitter = RegExp(r'[^\w\u4e00-\u9fff]+');
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
    final persisted = _localOnlyPreferenceWriter != null
        ? await _localOnlyPreferenceWriter!(value)
        : (await SharedPreferences.getInstance()).setBool('localOnly', value);
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
      final firstLine = ocrText.split('\n').firstWhere(
            (line) => line.trim().isNotEmpty,
            orElse: () => '',
          );
      final screenshot = Screenshot(
        id: _uuid.v4(),
        fileName: imagePath.split('/').last,
        filePath: imagePath,
        timestamp: DateTime.now(),
        ocrText: ocrText.isEmpty ? null : ocrText,
        lamType: 'document',
        summary: ocrText.isEmpty
            ? 'No text found'
            : (firstLine.isNotEmpty
                ? (firstLine.length > 80
                    ? firstLine.substring(0, 80)
                    : firstLine)
                : (ocrText.length > 80
                    ? ocrText.substring(0, 80)
                    : ocrText)),
        description: null,
        objects: _mergeObjects(analysis.objects),
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

  Future<void> _saveScreenshot(Screenshot screenshot, {bool notify = true}) async {
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

  /// Add [id] with [weight] for every word in [text] to the inverted index.
  void _addTerms(String? text, String id, int weight, {Map<String, Map<String, int>>? index}) {
    if (text == null || text.isEmpty) return;
    final idx = index ?? _invertedIndex;
    for (final word in _tokenize(text)) {
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

  /// Build the inverted index for a single screenshot.
  void _indexScreenshot(Screenshot s) {
    // Remove old tags from tag index
    for (final ids in _tagIndex.values) {
      ids.remove(s.id);
    }
    // Remove old inverted index entries
    _removeId(s.id);

    // Build fresh inverted index with field weights
    _addTerms(s.summary, s.id, _wSummary);
    _addTerms(s.description, s.id, _wDescription);
    _addTerms(s.fileName, s.id, _wFileName);
    _addTerms(s.lamType, s.id, _wLamType);
    for (final tag in s.tags) {
      _addTerms(tag, s.id, _wTags);
    }
    for (final obj in s.objects) {
      _addTerms(obj, s.id, _wObjects);
    }
    for (final rec in s.recognitions) {
      _addTerms(rec, s.id, _wRecognitions);
    }
    for (final kw in s.searchKeywords) {
      _addTerms(kw, s.id, _wSearchKeywords);
    }
    if (s.extractedData != null) {
      for (final e in s.extractedData!.entries) {
        _addTerms('${e.key} ${e.value}', s.id, _wExtractedData);
      }
    }
    // OCR text gets weight 1 but is capped to avoid bloating the index
    final ocr = s.ocrText ?? '';
    if (ocr.isNotEmpty) {
      _addTerms(ocr.length > _ocrBlobCap ? ocr.substring(0, _ocrBlobCap) : ocr, s.id, _wOcr);
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
    final firstLine = ocr.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
    final screenshot = Screenshot(
      id: _uuid.v4(),
      fileName: path.split('/').last,
      filePath: path,
      timestamp: capturedAt,
      ocrText: ocr.isEmpty ? null : ocr,
      lamType: 'document',
      summary: ocr.isEmpty
          ? 'No text found'
          : (firstLine.isNotEmpty
              ? (firstLine.length > 80
                  ? firstLine.substring(0, 80)
                  : firstLine)
              : (ocr.length > 80 ? ocr.substring(0, 80) : ocr)),
      description: null,
      objects: _mergeObjects(objects),
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
        if (!writerSaved) throw StateError('local-only preference write failed');
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
        if (!seenSaved) throw StateError('watcher seen preference write failed');
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

  /// Local keyword search using inverted index with field weighting.
  /// Returns most relevant visible screenshots first. O(t × avg_postings)
  /// instead of O(n × t) for the old linear scan.
  List<Screenshot> search(String query, {int limit = 5}) {
    // Min-query gate: 2 chars for non-CJK, 1 char for CJK (single kanji
    // queries are legitimate).
    if (query.trim().length < 2 && !_cjk.hasMatch(query)) return [];

    var terms = query
        .toLowerCase()
        .split(_wordSplitter)
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];
    if (terms.length > _maxQueryTerms) {
      terms = terms.sublist(0, _maxQueryTerms);
    }

    // Collect candidate screenshot IDs and sum their weighted scores.
    final scores = <String, int>{};
    for (final term in terms) {
      final postings = _invertedIndex[term];
      if (postings == null) continue;
      for (final entry in postings.entries) {
        // Only count hidden-path-free screenshots (checked later).
        scores[entry.key] = (scores[entry.key] ?? 0) + entry.value;
      }
    }

    if (scores.isEmpty) return [];

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
    return scored.take(limit).map((e) => e.screenshot).toList();
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
