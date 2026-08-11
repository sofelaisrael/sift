import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR over screenshot images.
///
/// Recognizers are created lazily and shared, and [extractOverride] lets
/// tests inject a fake extractor — ML Kit cannot run inside `flutter test`,
/// so the override means unit tests never touch native ML Kit.
class OCRService {
  OCRService({this.extractOverride});

  final Future<String> Function(String imagePath)? extractOverride;

  TextRecognizer? _latinRecognizer;
  TextRecognizer? _chineseRecognizer;

  TextRecognizer get _latin =>
      _latinRecognizer ??=
          TextRecognizer(script: TextRecognitionScript.latin);
  TextRecognizer get _chinese =>
      _chineseRecognizer ??=
          TextRecognizer(script: TextRecognitionScript.chinese);

  Future<String> extractText(String imagePath) async {
    if (extractOverride != null) return extractOverride!(imagePath);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      // Try Latin first
      var result = await _latin.processImage(inputImage);

      // If empty, try Chinese
      if (result.text.isEmpty) {
        result = await _chinese.processImage(inputImage);
      }

      return result.text;
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  void dispose() {
    _latinRecognizer?.close();
    _chineseRecognizer?.close();
  }
}
