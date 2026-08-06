import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/screenshot_provider.dart';
import '../services/action_service.dart';
import '../services/screenshot_watcher.dart';

/// Owns the [ScreenshotWatcher] lifecycle above MaterialApp so theme
/// rebuilds never double-start the watcher. Starts in the constructor when
/// auto-detect is enabled (prefs read once), and never disposes.
class WatcherService extends ChangeNotifier {
  final ScreenshotProvider provider;
  final ActionService actionService;

  ScreenshotWatcher? _watcher;

  WatcherService({
    required this.provider,
    required this.actionService,
  }) {
    _startIfEnabled();
  }

  Future<void> _startIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('autoDetect') ?? true;
    if (!enabled) return;

    _watcher = ScreenshotWatcher(
      provider: provider,
      actionService: actionService,
    );
    await _watcher!.start();
    debugPrint('WatcherService: watcher started');
  }
}
