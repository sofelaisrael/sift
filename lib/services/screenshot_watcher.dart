import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/screenshot_provider.dart';
import 'action_service.dart';
import 'file_enumerator.dart';

/// POC screenshot watcher: polls known Android screenshot folders while the
/// app is running, detects new images, analyzes them, and notifies the user.
///
/// NOTE: This only runs while the app is open. A true background/foreground
/// service (running when the app is closed) requires native Android work.
class ScreenshotWatcher {
  final ScreenshotProvider provider;
  final ActionService actionService;
  final bool Function()? isIngesting;

  final FileEnumerator _enumerator;
  Timer? _timer;
  Set<String> _knownPaths = {};
  bool _initialized = false;
  bool _checking = false;

  static const _pollInterval = Duration(seconds: 10);

  ScreenshotWatcher({
    required this.provider,
    required this.actionService,
    this.isIngesting,
    FileEnumerator? enumerator,
  }) : _enumerator = enumerator ?? FileEnumerator();

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

  /// Run one check immediately (used at the end of a bulk ingest pass so
  /// the post-pass delta lands without waiting for the next tick).
  Future<void> scanNow() => _check();

  Future<void> _check() async {
    if (!_initialized || _checking || provider.isDeleting) return;
    if (isIngesting?.call() ?? false) return;

    _checking = true;
    try {
      // Merge provider records each tick so a finished ingest pass is
      // never re-processed.
      final known = <String>{
        ..._knownPaths,
        ...provider.screenshots.map((s) => s.filePath),
      };
      final files = await _enumerator.listMostRecentFirst();
      for (final file in files) {
        if (provider.isDeleting) return;
        if (known.contains(file.path)) continue;
        final processed = await _handleNew(file.path);
        if (processed) {
          _knownPaths.add(file.path);
          await _remember(file.path);
        }
      }
    } finally {
      _checking = false;
    }
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
    if (provider.isDeleting) return false;
    debugPrint('Watcher: new screenshot detected: $path');

    await (ensureNotificationPermission ?? _ensureNotificationPermission)();

    await actionService.notify(
      'New screenshot detected',
      'Sift is analyzing it now...',
    );

    try {
      final success = await provider.processScreenshot(path);
      if (!success) debugPrint('Watcher: analysis failed');
      return success;
    } catch (e) {
      debugPrint('Watcher: analysis failed: $e');
      return false;
    }
  }

  /// Overridable in tests so the notification permission plugin is never
  /// reached. Production behavior is unchanged when unset.
  Future<void> Function()? ensureNotificationPermission;

  Future<void> _ensureNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }
}
