import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/screenshot.dart';
import '../services/lam_service.dart';
import '../services/action_service.dart';
import '../services/web_lookup.dart';
import '../config.dart';

class ScreenshotProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  
  List<Screenshot> _screenshots = [];
  bool _isLoading = false;
  String? _error;
  String _processingStatus = '';
  bool _showFavoritesOnly = false;

  List<Screenshot> get screenshots => _screenshots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get processingStatus => _processingStatus;
  bool get showFavoritesOnly => _showFavoritesOnly;
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

  /// Process a screenshot — sends image directly to multimodal AI
  Future<void> processScreenshot(String imagePath) async {
    try {
      _processingStatus = 'AI analyzing screenshot...';
      _error = null;
      notifyListeners();

      // Load settings
      final prefs = await SharedPreferences.getInstance();
      final providerName = prefs.getString('provider') ?? AppConfig.defaultProvider;
      final savedKey = prefs.getString('key_$providerName') ?? '';
      final apiKey = savedKey.isNotEmpty ? savedKey : AppConfig.apiKeyFor(providerName);

      final lamService = LAMService();

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

      _processingStatus = 'Executing action...';
      notifyListeners();

      // Step 2: Execute Action
      final actionService = ActionService();
      ActionResult? actionResult;
      
      if (lamResponse.suggestedAction.type != 'none') {
        actionResult = await actionService.executeAction(
          lamResponse.suggestedAction,
          _uuid.v4(),
        );
      }

      // Step 2.5: Go online — find real links to what SIFT recognized
      List<Map<String, String>> webResults = const [];
      if (lamResponse.confidence > 0.0 &&
          !lamResponse.summary.startsWith('Could not analyze')) {
        _processingStatus = 'Searching the web…';
        notifyListeners();
        try {
          final savedYouTubeKey = prefs.getString('key_youtube') ?? '';
          final youTubeApiKey = savedYouTubeKey.isNotEmpty
              ? savedYouTubeKey
              : AppConfig.youTubeApiKey;
          final lookupResults = await WebLookupService().lookup(
            response: lamResponse,
            youTubeApiKey: youTubeApiKey,
          );
          webResults = lookupResults
              .map((r) => {'title': r.title, 'url': r.url})
              .toList();
        } catch (_) {
          webResults = const [];
        } finally {
          _processingStatus = actionResult?.message ?? lamResponse.summary;
          notifyListeners();
        }
      }

      // Step 3: Save to database
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
        actionCompleted: actionResult?.success ?? false,
        actionResult: actionResult?.message,
        webResults: webResults,
      );

      await _saveScreenshot(screenshot);

      _processingStatus = actionResult?.message ?? lamResponse.summary;
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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearStatus() {
    _processingStatus = '';
    notifyListeners();
  }
}
