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
  final OCRService _ocr = OCRService();

  List<Screenshot> _screenshots = [];
  bool _isLoading = false;
  String? _error;
  String _processingStatus = '';
  bool _showFavoritesOnly = false;
  bool _localOnly = false;

  List<Screenshot> get screenshots => _screenshots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get processingStatus => _processingStatus;
  bool get showFavoritesOnly => _showFavoritesOnly;
  bool get localOnly => _localOnly;
  List<Screenshot> get favorites =>
      _screenshots.where((s) => s.isFavorite).toList();
  List<Screenshot> get visibleScreenshots =>
      _showFavoritesOnly ? favorites : _screenshots;

  List<Screenshot> get recentScreenshots => _screenshots.take(10).toList();
  
  Map<String, List<Screenshot>> get byType {
    final map = <String, List<Screenshot>>{};
    for (final s in _screenshots) {
      final type = s.lamType ?? 'other';
      map.putIfAbsent(type, () => []).add(s);
    }
    return map;
  }

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
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
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
  Future<void> processScreenshot(String imagePath) async {
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

      _processingStatus = 'AI analyzing screenshot...';
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
      final cfg = lamService.availableProviders.where((p) => p.name == providerName);
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
        description: lamResponse.description.isNotEmpty
            ? lamResponse.description
            : null,
        objects: lamResponse.objects,
        recognitions: lamResponse.recognitions,
        actionType: lamResponse.suggestedAction.type,
        actionCompleted: false,
        actionResult: null,
        suggestedAction: lamResponse.suggestedAction.type != 'none'
            ? {
                'type': lamResponse.suggestedAction.type,
                'data': lamResponse.suggestedAction.data ?? const {},
              }
            : null,
        webResults: const [],
      );

      await _saveScreenshot(screenshot);

      _processingStatus = lamResponse.summary;
      notifyListeners();
    } catch (e) {
      _error = 'Processing failed: ${e.toString()}';
      _processingStatus = '';
      notifyListeners();
    }
  }

  Future<void> _saveScreenshot(Screenshot screenshot) async {
    final box = Hive.box('screenshots');
    await box.put(screenshot.id, screenshot.toJson());
    _screenshots.insert(0, screenshot);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (paths.isNotEmpty) {
      await prefs.setStringList('watcher_seen', paths);
    }
    _screenshots = [];
    _error = null;
    _processingStatus = '';
    _localOnly = false;
    notifyListeners();
  }

  /// Local keyword search across summaries, descriptions, text, and tags.
  /// Returns most relevant screenshots first.
  List<Screenshot> search(String query, {int limit = 5}) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^\w\u4e00-\u9fff]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return [];

    final scored = <({Screenshot screenshot, int score})>[];
    for (final s in _screenshots) {
      final haystack = [
        s.summary,
        s.description,
        s.ocrText,
        s.lamType,
        ...s.recognitions,
        ...s.objects,
        ...s.tags,
      ]
          .whereType<String>()
          .join(' ')
          .toLowerCase();

      var score = 0;
      for (final term in terms) {
        if (haystack.contains(term)) score++;
      }
      if (score > 0) scored.add((screenshot: s, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.screenshot).toList();
  }

  Future<void> deleteScreenshot(String id) async {
    final box = Hive.box('screenshots');
    await box.delete(id);
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
    notifyListeners();
    try {
      final box = Hive.box('screenshots');
      await box.put(id, screenshot.toJson());
      return true;
    } catch (e) {
      screenshot.tags = [...screenshot.tags]..remove(trimmed);
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
    notifyListeners();
    try {
      final box = Hive.box('screenshots');
      await box.put(id, screenshot.toJson());
      return true;
    } catch (e) {
      screenshot.tags = [...screenshot.tags]..insert(i, tag);
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
