import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  late final TextRecognizer _latinRecognizer;
  late final TextRecognizer _chineseRecognizer;

  OCRService() {
    _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _chineseRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  }

  Future<String> extractText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      
      // Try Latin first
      var result = await _latinRecognizer.processImage(inputImage);
      
      // If empty, try Chinese
      if (result.text.isEmpty) {
        result = await _chineseRecognizer.processImage(inputImage);
      }
      
      return result.text;
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  void dispose() {
    _latinRecognizer.close();
    _chineseRecognizer.close();
  }
}
