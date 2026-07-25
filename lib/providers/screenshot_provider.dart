import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/screenshot.dart';
import '../services/ocr_service.dart';
import '../services/lam_service.dart';
import '../services/action_service.dart';

class ScreenshotProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  
  List<Screenshot> _screenshots = [];
  bool _isLoading = false;
  String? _error;
  String _processingStatus = '';

  List<Screenshot> get screenshots => _screenshots;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get processingStatus => _processingStatus;

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

  /// Process a screenshot through the full LAM pipeline
  Future<void> processScreenshot(String imagePath) async {
    try {
      _processingStatus = 'Extracting text...';
      notifyListeners();

      // Step 1: OCR
      final ocrService = OCRService();
      final ocrText = await ocrService.extractText(imagePath);
      ocrService.dispose();

      if (ocrText.isEmpty) {
        _error = 'No text found in screenshot';
        notifyListeners();
        return;
      }

      _processingStatus = 'AI analyzing...';
      notifyListeners();

      // Step 2: LAM Analysis
      final lamService = LAMService();
      final lamResponse = await lamService.processScreenshot(ocrText);

      _processingStatus = 'Executing action...';
      notifyListeners();

      // Step 3: Execute Action
      final actionService = ActionService();
      ActionResult? actionResult;
      
      if (lamResponse.suggestedAction.type != 'none') {
        actionResult = await actionService.executeAction(
          lamResponse.suggestedAction,
          _uuid.v4(),
        );
      }

      // Step 4: Save to database
      final screenshot = Screenshot(
        id: _uuid.v4(),
        fileName: imagePath.split('/').last,
        filePath: imagePath,
        timestamp: DateTime.now(),
        ocrText: ocrText,
        lamType: lamResponse.type,
        confidence: lamResponse.confidence,
        summary: lamResponse.summary,
        actionType: lamResponse.suggestedAction.type,
        actionCompleted: actionResult?.success ?? false,
        actionResult: actionResult?.message,
      );

      await _saveScreenshot(screenshot);

      _processingStatus = actionResult?.message ?? 'Processed!';
      notifyListeners();
    } catch (e) {
      _error = 'Processing failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveScreenshot(Screenshot screenshot) async {
    final box = Hive.box('screenshots');
    await box.put(screenshot.id, screenshot.toJson());
    _screenshots.insert(0, screenshot);
    notifyListeners();
  }

  Future<void> deleteScreenshot(String id) async {
    final box = Hive.box('screenshots');
    await box.delete(id);
    _screenshots.removeWhere((s) => s.id == id);
    notifyListeners();
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
