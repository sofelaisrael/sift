import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../providers/screenshot_provider.dart';
import 'file_enumerator.dart';
import 'screenshot_analyzer.dart';

class _AnalysisExhausted implements Exception {
  const _AnalysisExhausted(this.message);
  final String message;
}

class _IngestStopped implements Exception {
  const _IngestStopped();
}

/// Bulk "Index my library" pass: analyzes the existing screenshot folders
/// through the same local analyzer and writes structured records. No network
/// call, no prefs/consent reads, no gallery writes.
///
/// The queue lives in the Hive `ingest` box so it survives restarts:
/// per-path entries hold the status machine and a reserved `__meta` entry
/// tracks running/paused flags. On start, entries stuck in `processing` are
/// re-queued (crash recovery); dedupe is by file path against the
/// provider's path index. The provider owns the analyzer and shared queue.
class IngestService extends ChangeNotifier {
  IngestService({
    required this.provider,
    FileEnumerator? enumerator,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 32),
    ],
    this.onPassComplete,
  }) : _enumerator = enumerator ?? FileEnumerator();

  final ScreenshotProvider provider;
  final FileEnumerator _enumerator;
  final List<Duration> retryDelays;

  /// Called when a pass finishes draining (used to kick the watcher's
  /// post-pass delta scan). Set after construction to break wiring cycles.
  Future<void> Function()? onPassComplete;

  static const _metaKey = '__meta';
  static const _statusPending = 'pending';
  static const _statusProcessing = 'processing';
  static const _statusDone = 'done';
  static const _statusFailed = 'failed';
  static const _statusSkipped = 'skipped';
  static const _statusHidden = 'hidden';
  static const _metaStatusRunning = 'running';
  static const _metaStatusStopped = 'stopped';

  bool _running = false;
  bool _paused = false;
  bool _stopRequested = false;
  int _generation = 0;
  Future<void>? _activeStart;
  Future<void>? _stopOperation;
  Future<void> _metaTail = Future.value();
  Completer<void> _stopSignal = Completer<void>();
  int _processed = 0;
  int _totalTarget = 0;
  DateTime? _passStartedAt;
  final List<String> _pendingQueue = [];
  final StreamController<int> _progress = StreamController<int>.broadcast();

  Box<dynamic> get _box => Hive.box('ingest');

  Future<void> _writeMeta(Map<String, dynamic> value) {
    if (!Hive.isBoxOpen('ingest')) return Future<void>.value();
    if (_stopRequested && value['status'] != _metaStatusStopped) {
      return Future<void>.value();
    }
    final result = _metaTail.then((_) {
      if (!Hive.isBoxOpen('ingest')) return;
      if (_stopRequested && value['status'] != _metaStatusStopped) return;
      return Hive.box('ingest').put(_metaKey, value);
    });
    _metaTail = result.catchError((_) {});
    return result;
  }

  bool get isIngesting => _running;
  bool get paused => _paused;
  bool get isStopped => _stopRequested;
  int get processedCount => _processed;

  /// Paths still waiting to be analyzed. O(1) counter kept in sync with the
  /// queue, so the progress banner never scans the box.
  int get remaining => (_totalTarget - _processed).clamp(0, _totalTarget);

  /// Rough time left based on items completed so far. Null before the first
  /// item finishes or when the rate can't be measured yet.
  Duration? get estimatedRemaining {
    if (!_running || _processed == 0 || _passStartedAt == null) return null;
    final elapsedMs = DateTime.now().difference(_passStartedAt!).inMilliseconds;
    if (elapsedMs <= 0) return null;
    final perItemMs = elapsedMs / _processed;
    return Duration(milliseconds: (remaining * perItemMs).round());
  }

  /// Emits the processed count as the pass advances.
  Stream<int> get progress => _progress.stream;

  String? _entryStatus(String key) {
    final entry = _box.get(key);
    if (entry is Map) return entry['status'] as String?;
    return null;
  }

  Future<void> start() {
    final stopping = _stopOperation;
    if (stopping != null) {
      return stopping.then((_) => _startFresh());
    }
    return _startFresh();
  }

  Future<void> _startFresh() {
    final active = _activeStart;
    if (active != null) return active;
    if (_running) return Future<void>.value();

    final operation = _start();
    _activeStart = operation;
    return operation.whenComplete(() {
      if (identical(_activeStart, operation)) _activeStart = null;
    });
  }

  Map<String, dynamic> _stoppedMeta() => {
        'running': false,
        'paused': false,
        'stopped': true,
        'status': _metaStatusStopped,
        'stoppedAt': DateTime.now().toIso8601String(),
      };

  Future<void> _start() async {
    final generation = ++_generation;
    _stopRequested = false;
    _stopSignal = Completer<void>();
    await _recoverStuckEntries(generation);
    if (_isStopped(generation)) return;

    _paused = false;
    _running = true;
    _processed = 0;
    _totalTarget = 0;
    _passStartedAt = DateTime.now();
    await _writeMeta({
      'running': true,
      'paused': false,
      'stopped': false,
      'status': _metaStatusRunning,
      'startedAt': _passStartedAt!.toIso8601String(),
    });
    if (_isStopped(generation)) {
      await _writeMeta(_stoppedMeta());
      return;
    }

    notifyListeners();
    await _enqueueRemaining(generation);
    if (_isStopped(generation)) return;
    _totalTarget = _pendingQueue.length;
    await _drain(generation);
    if (_isStopped(generation)) return;
    notifyListeners();
  }

  Future<void> stop() {
    final activeStop = _stopOperation;
    if (activeStop != null) return activeStop;
    final operation = _stop();
    _stopOperation = operation;
    return operation.whenComplete(() {
      if (identical(_stopOperation, operation)) _stopOperation = null;
    });
  }

  Future<void> _stop() async {
    _generation++;
    _stopRequested = true;
    _paused = false;
    _running = false;
    _pendingQueue.clear();
    _processed = 0;
    _totalTarget = 0;
    _passStartedAt = null;
    if (!_stopSignal.isCompleted) _stopSignal.complete();

    final active = _activeStart;
    try {
      await _writeMeta(_stoppedMeta());
    } catch (_) {}
    try {
      notifyListeners();
    } catch (_) {}
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
    try {
      await _writeMeta(_stoppedMeta());
    } catch (_) {}
    try {
      notifyListeners();
    } catch (_) {}
  }

  Future<void> pause() async {
    if (!_running || _stopRequested) return;
    _paused = true;
    final meta = _box.get(_metaKey);
    if (meta is Map) {
      await _writeMeta({...meta, 'paused': true});
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_running || !_paused || _stopRequested) return;
    _paused = false;
    final meta = _box.get(_metaKey);
    if (meta is Map) {
      await _writeMeta({...meta, 'paused': false});
    }
    if (_stopRequested) return;
    notifyListeners();
    await _drain(_generation);
  }

  /// Crash recovery: anything stuck in `processing` is re-queued, and box
  /// entries whose file no longer exists are marked skipped.
  Future<void> _recoverStuckEntries(int generation) async {
    final files = await _enumerator.listMostRecentFirst();
    if (_isStopped(generation)) return;
    final livePaths = files.map((f) => f.path).toSet();
    for (final key in _box.keys) {
      if (_isStopped(generation)) return;
      if (key == _metaKey) continue;
      final entry = _box.get(key);
      if (entry is! Map) continue;
      final status = entry['status'];
      if (!livePaths.contains(key)) {
        if (status == _statusPending || status == _statusProcessing) {
          await _box.put(key, {...entry, 'status': _statusSkipped});
        }
        continue;
      }
      if (status == _statusProcessing) {
        await _box.put(key, {...entry, 'status': _statusPending});
      }
    }
  }

  Future<void> _enqueueRemaining(int generation) async {
    final files = await _enumerator.listMostRecentFirst();
    if (_isStopped(generation)) return;
    for (final f in files) {
      if (_isStopped(generation)) return;
      if (provider.containsPath(f.path)) continue;
      final entry = _box.get(f.path);
      if (entry is Map) {
        final status = entry['status'];
        if (status == _statusDone ||
            status == _statusHidden ||
            status == _statusSkipped) {
          continue;
        }
        if (status == _statusPending && !_pendingQueue.contains(f.path)) {
          _pendingQueue.add(f.path);
        }
        continue;
      }
      await _box.put(f.path, {
        'status': _statusPending,
        'attempts': 0,
        'lastError': null,
        'enqueuedAt': DateTime.now().toIso8601String(),
        'processedAt': null,
        'screenshotId': null,
      });
      if (_isStopped(generation)) return;
      _pendingQueue.add(f.path);
    }
  }

  Future<void> _drain(int generation) async {
    while (_running &&
        !_paused &&
        !_stopRequested &&
        generation == _generation) {
      String? next;
      while (_pendingQueue.isNotEmpty) {
        final candidate = _pendingQueue.removeAt(0);
        final status = _entryStatus(candidate);
        if (status == _statusPending) {
          next = candidate;
          break;
        }
      }
      if (next == null) {
        // Files that appeared after the pass started.
        await _enqueueRemaining(generation);
        if (_isStopped(generation)) return;
        _totalTarget = _processed + _pendingQueue.length;
        if (_pendingQueue.isEmpty) break;
        continue;
      }
      await _process(next, generation);
    }

    if (_isStopped(generation)) return;
    if (_running && !_paused) {
      _running = false;
      await _writeMeta({
        'running': false,
        'paused': false,
        'stopped': false,
        'status': 'finished',
        'startedAt': _passStartedAt?.toIso8601String(),
        'finishedAt': DateTime.now().toIso8601String(),
      });
      if (_isStopped(generation)) {
        await _writeMeta(_stoppedMeta());
        return;
      }
      provider.flushBulkNotify();
      if (onPassComplete != null && !_isStopped(generation)) {
        await onPassComplete!();
      }
      notifyListeners();
    }
  }

  Future<void> _process(String path, int generation) async {
    if (_isStopped(generation)) return;
    final now = DateTime.now();
    final entry = _box.get(path);
    await _box.put(path, {
      ...(entry is Map ? entry : const {}),
      'status': _statusProcessing,
    });
    if (_isStopped(generation)) return;

    try {
      final analysis = await _analyzeWithRetry(path, generation);
      if (_isStopped(generation)) return;
      final capturedAt = _capturedAt(path);
      final id = await provider.addFromBulkIngest(
        path: path,
        capturedAt: capturedAt,
        ocrText: analysis.ocrText,
        objects: analysis.objects,
      );
      if (_isStopped(generation) || provider.isDeleting) return;
      await _box.put(path, {
        'status': id == null ? _statusSkipped : _statusDone,
        'attempts': 0,
        'lastError': id == null ? 'duplicate' : null,
        'enqueuedAt': (entry is Map ? entry['enqueuedAt'] : null) ??
            now.toIso8601String(),
        'processedAt': DateTime.now().toIso8601String(),
        'screenshotId': id,
      });
    } on FileSystemException catch (e) {
      if (_isStopped(generation)) return;
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusSkipped,
        'lastError': e.message,
        'processedAt': DateTime.now().toIso8601String(),
      });
    } on _IngestStopped {
      return;
    } on _AnalysisExhausted catch (e) {
      if (_isStopped(generation)) return;
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusFailed,
        'lastError': e.message,
        'processedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (_isStopped(generation)) return;
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusFailed,
        'lastError': e.toString(),
        'processedAt': DateTime.now().toIso8601String(),
      });
    }

    if (_isStopped(generation)) return;
    _processed++;
    _progress.add(_processed);
    notifyListeners();
  }

  Future<ScreenshotAnalysisResult> _analyzeWithRetry(
    String path,
    int generation,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (_isStopped(generation) || provider.isDeleting) {
        throw const _IngestStopped();
      }
      try {
        return await provider.analyzeForBulkIngest(path);
      } catch (e) {
        if (_isStopped(generation) || provider.isDeleting) {
          throw const _IngestStopped();
        }
        lastError = e;
        if (e is FileSystemException) rethrow;
        if (attempt < retryDelays.length) {
          await _waitForRetry(retryDelays[attempt]);
          if (_isStopped(generation) || provider.isDeleting) {
            throw const _IngestStopped();
          }
        }
      }
    }
    throw _AnalysisExhausted('$lastError');
  }

  Future<void> _waitForRetry(Duration delay) {
    if (delay <= Duration.zero) return Future<void>.value();
    return Future.any<void>(<Future<void>>[
      Future<void>.delayed(delay),
      _stopSignal.future,
    ]);
  }

  bool _isStopped(int generation) =>
      _stopRequested || generation != _generation;

  DateTime _capturedAt(String path) {
    try {
      return File(path).statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }
}
