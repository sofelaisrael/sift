import 'image_labeler.dart';
import 'ocr_service.dart';

/// Immutable result of a local screenshot analysis.
class ScreenshotAnalysisResult {
  ScreenshotAnalysisResult({
    required this.ocrText,
    List<String>? objects,
    List<String>? labels,
  }) : objects = List.unmodifiable(objects ?? labels ?? const <String>[]);

  final String ocrText;
  final List<String> objects;

  List<String> get labels => objects;
  String get text => ocrText;
}

typedef ScreenshotAnalysis = ScreenshotAnalysisResult;

abstract class ScreenshotAnalyzer {
  Future<ScreenshotAnalysisResult> analyze(String imagePath);
}

/// Combines ML Kit OCR with optional on-device visual labels. The caller owns
/// the supplied OCR service; no hosted provider is involved.
class MLKitScreenshotAnalyzer implements ScreenshotAnalyzer {
  MLKitScreenshotAnalyzer({OCRService? ocr, ImageLabeler? labeler})
      : _ocr = ocr ?? OCRService(),
        _labeler = labeler;

  static const int maxLabelOcrLength = 200;

  final OCRService _ocr;
  final ImageLabeler? _labeler;

  static bool shouldLabel(String? ocrText) =>
      (ocrText ?? '').trim().length <= maxLabelOcrLength;

  @override
  Future<ScreenshotAnalysisResult> analyze(String imagePath) async {
    final ocrText = (await _ocr.extractText(imagePath)).trim();
    var objects = const <String>[];
    if (shouldLabel(ocrText) && _labeler != null) {
      try {
        objects = await _labeler!.labelsFor(imagePath);
      } catch (_) {
        objects = const <String>[];
      }
    }
    return ScreenshotAnalysisResult(ocrText: ocrText, objects: objects);
  }
}
