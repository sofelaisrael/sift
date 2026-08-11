import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    as mlkit;

/// On-device visual labels for screenshots (ML Kit Image Labeling).
/// Gives text-less screenshots searchable terms ("dog", "food", "menu", ...)
/// with no network and no AI provider. Never fatal: any failure returns no
/// labels so the ingest pass and watcher keep working.
class ImageLabeler {
  ImageLabeler({this.labelOverride});

  /// Test seam mirroring OCRService.extractOverride.
  final Future<List<String>> Function(String imagePath)? labelOverride;

  static const int _maxLabels = 4;
  static const double _minConfidence = 0.5;

  Future<List<String>> labelsFor(String imagePath) async {
    if (labelOverride != null) return labelOverride!(imagePath);
    try {
      final labeler = mlkit.ImageLabeler(
        options: mlkit.ImageLabelerOptions(
          confidenceThreshold: _minConfidence,
        ),
      );
      try {
        final input = mlkit.InputImage.fromFilePath(imagePath);
        final labels = await labeler.processImage(input);
        final seen = <String>{};
        final top = <String>[];
        for (final l in labels) {
          final label = l.label.trim().toLowerCase();
          if (label.isEmpty || !seen.add(label)) continue;
          top.add(label);
          if (top.length >= _maxLabels) break;
        }
        return top;
      } finally {
        labeler.close();
      }
    } catch (_) {
      return const [];
    }
  }
}
