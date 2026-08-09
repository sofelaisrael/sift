import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/screenshot_provider.dart';
import 'action_service.dart';

/// POC screenshot watcher: polls known Android screenshot folders while the
/// app is running, detects new images, analyzes them, and notifies the user.
///
/// NOTE: This only runs while the app is open. A true background/foreground
/// service (running when the app is closed) requires native Android work.
class ScreenshotWatcher {
  final ScreenshotProvider provider;
  final ActionService actionService;

  Timer? _timer;
  Set<String> _knownPaths = {};
  bool _initialized = false;

  static const _pollInterval = Duration(seconds: 10);

  static const List<String> _candidateFolders = [
    '/storage/emulated/0/DCIM/Screenshots',
    '/storage/emulated/0/Pictures/Screenshots',
    '/storage/emulated/0/Pictures/Screenshot',
  ];

  ScreenshotWatcher({required this.provider, required this.actionService});

  Future<void> start() async {
    _knownPaths = provider.screenshots.map((s) => s.filePath).toSet();

    final prefs = await SharedPreferences.getInstance();
    _knownPaths.addAll(prefs.getStringList('watcher_seen') ?? const []);

    _initialized = true;
    _timer = Timer.periodic(_pollInterval, (_) => _check());
    debugPrint('Screenshot watcher started');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('Screenshot watcher stopped');
  }

  Future<void> _check() async {
    if (!_initialized) return;

    final files = await _findScreenshotFiles();
    for (final file in files) {
      if (_knownPaths.contains(file.path)) continue;
      final processed = await _handleNew(file.path);
      if (processed) {
        _knownPaths.add(file.path);
        await _remember(file.path);
      }
    }
  }

  Future<List<File>> _findScreenshotFiles() async {
    final found = <File>[];
    for (final dirPath in _candidateFolders) {
      final dir = Directory(dirPath);
      try {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File && _isImage(entity.path)) {
            found.add(entity);
          }
        }
      } catch (e) {
        debugPrint('Watcher: could not scan $dirPath: $e');
      }
    }
    return found;
  }

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  Future<void> _remember(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('watcher_seen') ?? <String>[];
    if (!seen.contains(path)) {
      seen.add(path);
      await prefs.setStringList('watcher_seen', seen);
    }
  }

  Future<bool> _handleNew(String path) async {
    debugPrint('Watcher: new screenshot detected: $path');

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    final prefs = await SharedPreferences.getInstance();
    final localOnly = prefs.getBool('localOnly') ?? false;
    final consented = prefs.getBool('privacy_consent') ?? false;

    if (!localOnly && !consented) {
      await actionService.notify(
        'Sift needs permission',
        'Open Sift and allow screenshot analysis',
      );
      return false;
    }

    await actionService.notify(
      'New screenshot detected',
      'Sift is analyzing it now...',
    );

    try {
      await provider.processScreenshot(path);
      return true;
    } catch (e) {
      debugPrint('Watcher: analysis failed: $e');
      return false;
    }
  }
}
