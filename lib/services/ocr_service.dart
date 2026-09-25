import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
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
    try {
      if (extractOverride != null) {
        return await extractOverride!(imagePath);
      }
      if (await _isMissingFile(imagePath)) {
        throw FileSystemException('Unable to access file', imagePath);
      }
      final inputImage = InputImage.fromFilePath(imagePath);

      // Try Latin first
      var result = await _latin.processImage(inputImage);

      // If empty, try Chinese
      if (result.text.isEmpty) {
        result = await _chinese.processImage(inputImage);
      }

      return result.text;
    } on PlatformException catch (e) {
      if (await _isMissingFile(imagePath)) {
        throw FileSystemException('Unable to access file', imagePath);
      }
      throw Exception('OCR failed: ${e.message ?? 'native OCR error'}');
    } on FileSystemException catch (e) {
      if (await _isMissingFile(imagePath)) {
        throw FileSystemException('Unable to access file', imagePath);
      }
      throw Exception('OCR failed: ${e.message}');
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  Future<bool> _isMissingFile(String imagePath) async {
    try {
      return !await File(imagePath).exists();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _latinRecognizer?.close();
    _chineseRecognizer?.close();
  }
}
