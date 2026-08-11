import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/screenshot.dart';
import '../services/lam_service.dart';
import '../services/action_service.dart';
import '../services/web_lookup.dart';
import '../services/ocr_service.dart';
import '../config.dart';

class ScreenshotProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const int _bulkNotifyInterval = 25;
  static const int _maxQueryTerms = 6;
  static const int _ocrBlobCap = 2000;
  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

  late final OCRService _ocr;

  ScreenshotProvider({OCRService? ocr}) : _ocr = ocr ?? OCRService();

  List<Screenshot> _screenshots = [];
  Map<String, Screenshot> _byPath = {};
  Set<String> _hiddenPaths = {};
  Map<String, String> _searchBlobs = {};
  Map<String, Set<String>> _tagIndex = {};
  bool _isLoading = false;
  String? _error;
  String _processingStatus = '';
  bool _showFavoritesOnly = false;
  bool _localOnly = false;
  Future<void> _queueTail = Future.value();
  Future<void> _writeTail = Future.value();
  int _pendingNotifies = 0;

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

  void loadScreenshots() {
    _isLoading = true;
    notifyListeners();
    _loadSettings();

    try {
      final box = Hive.box('screenshots');
      _screenshots = box.values
          .map((json) => Screenshot.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      _screenshots.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _byPath = {for (final s in _screenshots) s.filePath: s};
      _rebuildIndexes();
      _loadHiddenPaths();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
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
    final prefs = await SharedPreferences.getInstance();
    _localOnly = prefs.getBool('localOnly') ?? false;
  }

  /// Keep the in-memory local-only flag in sync with the Settings toggle.
  void setLocalOnly(bool value) {
    _localOnly = value;
    notifyListeners();
  }

  /// Process a screenshot — local OCR when local-only mode is on, otherwise
  /// the image goes directly to the chosen multimodal AI provider.
  Future<void> _processScreenshotInternal(String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localOnly = prefs.getBool('localOnly') ?? false;
      _localOnly = localOnly;

      if (localOnly) {
        _processingStatus = 'Analyzing locally…';
        _error = null;
        notifyListeners();
        try {
          final ocrText = (await _ocr.extractText(imagePath)).trim();
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
            objects: const [],
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
          _processingStatus = 'Local analysis complete';
          notifyListeners();
          return;
        } catch (e) {
          _error = 'Local analysis failed: ${e.toString()}';
          _processingStatus = '';
          notifyListeners();
          return;
        }
      }

      _processingStatus = 'Analyzing screenshot…';
      _error = null;
      notifyListeners();

      final lamService = LAMService();

      // Load settings
      var providerName =
          prefs.getString('provider') ?? AppConfig.defaultProvider;
      if (!lamService.availableProviders.any((p) => p.name == providerName)) {
        providerName = AppConfig.defaultProvider;
      }
      final savedKey = prefs.getString('key_$providerName') ?? '';
      final apiKey =
          savedKey.isNotEmpty ? savedKey : AppConfig.apiKeyFor(providerName);

      // Fail fast with a clear, actionable message when the selected
      // provider needs a key that isn't configured yet.
      final cfg =
          lamService.availableProviders.where((p) => p.name == providerName);
      final needsKey = cfg.isNotEmpty ? cfg.first.requiresKey : true;
      if (needsKey && (apiKey == null || apiKey.isEmpty)) {
        _error = 'No API key set for $providerName. '
            'Open Settings, choose a provider, and paste its free API key.';
        _processingStatus = '';
        notifyListeners();
        return;
      }

      // Step 1: Send image directly to AI
      final lamResponse = await lamService.analyzeImage(
        imagePath,
        apiKey: apiKey,
        provider: providerName,
      );

      // Step 2: Save to database
      final screenshot = Screenshot(
        id: _uuid.v4(),
        fileName: imagePath.split('/').last,
        filePath: imagePath,
        timestamp: DateTime.now(),
        ocrText: lamResponse.extractedText.isNotEmpty
            ? lamResponse.extractedText
            : lamResponse.summary,
        lamType: lamResponse.type,
        confidence: lamResponse.confidence,
        summary: lamResponse.summary,
        description:
            lamResponse.description.isNotEmpty ? lamResponse.description : null,
        objects: lamResponse.objects,
        recognitions: lamResponse.recognitions,
        actionType: lamResponse.suggestedAction.type,
        actionCompleted: false,
        actionResult: null,
        suggestedAction: lamResponse.suggestedAction.type != 'none'
            ? {
                'type': lamResponse.suggestedAction.type,
                'data': lamResponse.suggestedAction.data,
              }
            : null,
        extractedData: lamResponse.extractedData.isEmpty
            ? null
            : lamResponse.extractedData,
        webResults: const [],
      );

      await _saveScreenshot(screenshot);

      _processingStatus = lamResponse.summary;
      notifyListeners();
    } catch (e) {
      debugPrint('Screenshot processing failed: ${e.toString()}');
      _error =
          "Couldn't analyze this screenshot. Check your API key and try again.";
      _processingStatus = '';
      notifyListeners();
    }
  }

  /// Serializes analysis so concurrent calls (watcher poll + manual pick)
  /// never run two AI/OCR jobs at once.
  Future<void> processScreenshot(String imagePath) {
    final result =
        _queueTail.then((_) => _processScreenshotInternal(imagePath));
    _queueTail = result.catchError((_) {});
    return result;
  }

  Future<void> _saveScreenshot(Screenshot screenshot, {bool notify = true}) async {
    _byPath[screenshot.filePath] = screenshot;
    _insertSorted(screenshot);
    _indexScreenshot(screenshot);
    if (notify) notifyListeners();
    await _writeSerialized(
      () => Hive.box('screenshots').put(screenshot.id, screenshot.toJson()),
    );
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

  String _searchBlobFor(Screenshot s) {
    final ocr = s.ocrText ?? '';
    final ocrCapped = ocr.length > _ocrBlobCap
        ? ocr.substring(0, _ocrBlobCap)
        : ocr;
    return [
      s.fileName,
      s.summary,
      s.description,
      s.lamType,
      ...s.recognitions,
      ...s.objects,
      ...s.tags,
      ...?s.extractedData?.entries.map((e) => '${e.key} ${e.value}'),
      ocrCapped,
    ].whereType<String>().join(' ').toLowerCase();
  }

  void _indexScreenshot(Screenshot s) {
    for (final ids in _tagIndex.values) {
      ids.remove(s.id);
    }
    _searchBlobs[s.id] = _searchBlobFor(s);
    for (final t in s.tags) {
      _tagIndex.putIfAbsent(t.toLowerCase(), () => <String>{}).add(s.id);
    }
  }

  void _rebuildIndexes() {
    _searchBlobs = {};
    _tagIndex = {};
    for (final s in _screenshots) {
      _indexScreenshot(s);
    }
  }

  Future<void> _writeSerialized(Future<void> Function() op) {
    final result = _writeTail.then((_) => op());
    _writeTail = result.catchError((_) {});
    return result;
  }

  /// Add a record from the bulk ingest pass. Real capture time, no
  /// prefs/consent reads, no per-item rebuild (notify throttled).
  Future<String?> addFromBulkIngest({
    required String path,
    required DateTime capturedAt,
    required String ocrText,
  }) async {
    if (_byPath.containsKey(path)) return null;
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
      objects: const [],
      recognitions: const [],
      actionType: null,
      actionCompleted: false,
      actionResult: null,
      suggestedAction: null,
      webResults: const [],
      isFavorite: false,
      tags: const [],
    );
    _byPath[path] = screenshot;
    _insertSorted(screenshot);
    _indexScreenshot(screenshot);
    _pendingNotifies++;
    if (_pendingNotifies >= _bulkNotifyInterval) {
      _pendingNotifies = 0;
      notifyListeners();
    }
    await _writeSerialized(
      () => Hive.box('screenshots').put(screenshot.id, screenshot.toJson()),
    );
    return screenshot.id;
  }

  /// Flush any pending throttled bulk notifications (end of a pass).
  void flushBulkNotify() {
    if (_pendingNotifies > 0) {
      _pendingNotifies = 0;
      notifyListeners();
    }
  }

  Future<void> hideScreenshot(String path) async {
    _hiddenPaths.add(path);
    if (Hive.isBoxOpen('hidden_paths')) {
      await Hive.box('hidden_paths').put(path, DateTime.now().toIso8601String());
    }
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('watcher_seen') ?? <String>[];
    if (!seen.contains(path)) {
      seen.add(path);
      await prefs.setStringList('watcher_seen', seen);
    }
    notifyListeners();
  }

  Future<void> unhideScreenshot(String path) async {
    _hiddenPaths.remove(path);
    if (Hive.isBoxOpen('hidden_paths')) {
      await Hive.box('hidden_paths').delete(path);
    }
    notifyListeners();
  }

  /// Manually run the suggested action stored on a screenshot.
  Future<ActionResult?> runSuggestedAction(Screenshot s) async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('localOnly') ?? false) ||
        !(prefs.getBool('privacy_consent') ?? false)) {
      _error = 'Privacy consent is required before running actions.';
      _processingStatus = '';
      notifyListeners();
      return null;
    }

    final suggested = s.suggestedAction;
    if (suggested == null || suggested.isEmpty) return null;

    try {
      final action = LAMAction(
        type: suggested['type'] as String? ?? 'none',
        data: suggested['data'] is Map
            ? Map<String, dynamic>.from(suggested['data'] as Map)
            : const {},
      );
      if (action.type == 'none') return null;

      _processingStatus = 'Running action…';
      notifyListeners();

      final result = await ActionService().executeAction(action, s.id);
      s.actionCompleted = result.success;
      s.actionResult = result.message;
      final box = Hive.box('screenshots');
      await box.put(s.id, s.toJson());
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

  /// Manually look up matching web links for a screenshot.
  Future<void> findOnline(Screenshot s) async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('localOnly') ?? false) ||
        !(prefs.getBool('privacy_consent') ?? false)) {
      _error = 'Privacy consent is required before searching the web.';
      _processingStatus = '';
      notifyListeners();
      return;
    }

    _processingStatus = 'Searching the web…';
    notifyListeners();
    try {
      final savedYouTubeKey = prefs.getString('key_youtube') ?? '';
      final youTubeKey = savedYouTubeKey.isNotEmpty
          ? savedYouTubeKey
          : AppConfig.youTubeApiKey;
      final results = await WebLookupService().lookup(
        extractedText: s.ocrText ?? '',
        summary: s.summary ?? '',
        recognitions: s.recognitions,
        youTubeApiKey: youTubeKey,
      );
      s.webResults
        ..clear()
        ..addAll(results.map((r) => {'title': r.title, 'url': r.url}));
      final box = Hive.box('screenshots');
      await box.put(s.id, s.toJson());
      notifyListeners();
    } catch (e) {
      debugPrint('Web lookup failed: $e');
      s.webResults.clear();
    } finally {
      _processingStatus = s.summary ?? '';
      notifyListeners();
    }
  }

  /// Wipe everything Sift owns. Image files are never touched — Sift only
  /// references gallery originals and must never delete them.
  Future<void> deleteEverything() async {
    final paths = _screenshots.map((s) => s.filePath).toList();
    await Hive.box('screenshots').clear();
    await Hive.box('actions').clear();
    await Hive.box('chat').clear();
    if (Hive.isBoxOpen('ingest')) await Hive.box('ingest').clear();
    if (Hive.isBoxOpen('hidden_paths')) await Hive.box('hidden_paths').clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (paths.isNotEmpty) {
      await prefs.setStringList('watcher_seen', paths);
    }
    _screenshots = [];
    _byPath = {};
    _hiddenPaths = {};
    _searchBlobs = {};
    _tagIndex = {};
    _error = null;
    _processingStatus = '';
    _localOnly = false;
    notifyListeners();
  }

  /// Local keyword search across summaries, descriptions, text, tags, and
  /// file names. Returns most relevant visible screenshots first.
  List<Screenshot> search(String query, {int limit = 5}) {
    // Min-query gate: 2 chars for non-CJK, 1 char for CJK (single kanji
    // queries are legitimate).
    if (query.trim().length < 2 && !_cjk.hasMatch(query)) return [];

    var terms = query
        .toLowerCase()
        .split(RegExp(r'[^\w\u4e00-\u9fff]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];
    if (terms.length > _maxQueryTerms) {
      terms = terms.sublist(0, _maxQueryTerms);
    }

    final scored = <({Screenshot screenshot, int score})>[];
    for (final s in _visible) {
      final blob = _searchBlobs[s.id];
      if (blob == null) continue;
      var score = 0;
      for (final term in terms) {
        if (blob.contains(term)) score++;
      }
      if (score > 0) scored.add((screenshot: s, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.screenshot).toList();
  }

  Future<void> deleteScreenshot(String id) async {
    final matches = _screenshots.where((s) => s.id == id).toList();
    if (matches.isNotEmpty) {
      _byPath.remove(matches.first.filePath);
      _searchBlobs.remove(id);
      for (final ids in _tagIndex.values) {
        ids.remove(id);
      }
    }
    await _writeSerialized(() => Hive.box('screenshots').delete(id));
    _screenshots.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void setShowFavoritesOnly(bool value) {
    _showFavoritesOnly = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final matches = _screenshots.where((s) => s.id == id);
    if (matches.isEmpty) return;
    final screenshot = matches.first;
    screenshot.isFavorite = !screenshot.isFavorite;
    notifyListeners();
    try {
      final box = Hive.box('screenshots');
      await box.put(id, screenshot.toJson());
    } catch (e) {
      screenshot.isFavorite = !screenshot.isFavorite;
      notifyListeners();
      debugPrint('Failed to persist favorite state: $e');
    }
  }

  Future<bool> addTag(String id, String tag) async {
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
      final box = Hive.box('screenshots');
      await box.put(id, screenshot.toJson());
      return true;
    } catch (e) {
      screenshot.tags = [...screenshot.tags]..remove(trimmed);
      _indexScreenshot(screenshot);
      notifyListeners();
      debugPrint('Failed to persist tag: $e');
      return false;
    }
  }

  Future<bool> removeTag(String id, String tag) async {
    final matches = _screenshots.where((s) => s.id == id);
    if (matches.isEmpty) return false;
    final screenshot = matches.first;
    final i = screenshot.tags.indexOf(tag);
    if (i < 0) return false;
    screenshot.tags = [...screenshot.tags]..removeAt(i);
    _indexScreenshot(screenshot);
    notifyListeners();
    try {
      final box = Hive.box('screenshots');
      await box.put(id, screenshot.toJson());
      return true;
    } catch (e) {
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
