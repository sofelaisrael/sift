import 'dart:io';

/// One screenshot image discovered on disk.
class ScreenshotFile {
  const ScreenshotFile({required this.path, required this.modified});

  final String path;
  final DateTime modified;

  String get fileName => path.split('/').last;
}

/// Shared enumeration of the Android screenshot folders. Both the watcher
/// and the bulk ingest pass use this so the file paths (and therefore the
/// dedupe keys) are identical by construction.
class FileEnumerator {
  FileEnumerator({List<String> folders = _defaultFolders})
      : _folders = folders;

  static const List<String> _defaultFolders = [
    '/storage/emulated/0/DCIM/Screenshots',
    '/storage/emulated/0/Pictures/Screenshots',
    '/storage/emulated/0/Pictures/Screenshot',
  ];

  final List<String> _folders;

  static bool isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  /// All screenshot files under the configured folders, most recent first.
  Future<List<ScreenshotFile>> listMostRecentFirst() async {
    final found = <ScreenshotFile>[];
    for (final dirPath in _folders) {
      final dir = Directory(dirPath);
      try {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File && isImage(entity.path)) {
            found.add(
              ScreenshotFile(
                // Normalize separators so paths (and therefore the dedupe
                // keys) are identical on every platform.
                path: entity.path.replaceAll('\\', '/'),
                modified: entity.statSync().modified,
              ),
            );
          }
        }
      } catch (_) {
        // Unreadable folder — skip it, matching the watcher's tolerance.
      }
    }
    found.sort((a, b) => b.modified.compareTo(a.modified));
    return found;
  }
}
