import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../providers/screenshot_provider.dart';
import 'file_enumerator.dart';
import 'ocr_service.dart';
import 'image_labeler.dart';

class _OcrExhausted implements Exception {
  const _OcrExhausted(this.message);
  final String message;
}

/// Bulk "Index my library" pass: OCRs the existing screenshot folders
/// through the same local OCR path and writes structured records. No
/// network call, no prefs/consent reads, no gallery writes.
///
/// The queue lives in the Hive `ingest` box so it survives restarts:
/// per-path entries hold the status machine and a reserved `__meta` entry
/// tracks running/paused flags. On start, entries stuck in `processing` are
/// re-queued (crash recovery); dedupe is by file path against the
/// provider's path index.
class IngestService extends ChangeNotifier {
  IngestService({
    required this.provider,
    required this.ocr,
    this.labeler,
    FileEnumerator? enumerator,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 32),
    ],
    this.onPassComplete,
  }) : _enumerator = enumerator ?? FileEnumerator();

  final ScreenshotProvider provider;
  final OCRService ocr;
  final ImageLabeler? labeler;
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

  bool _running = false;
  bool _paused = false;
  int _processed = 0;
  int _totalTarget = 0;
  DateTime? _passStartedAt;
  final List<String> _pendingQueue = [];
  final StreamController<int> _progress = StreamController<int>.broadcast();

  Box<dynamic> get _box => Hive.box('ingest');

  bool get isIngesting => _running;
  bool get paused => _paused;
  int get processedCount => _processed;

  /// Paths still waiting to be OCR'd. O(1) counter kept in sync with the
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

  Future<void> start() async {
    if (_running) return;
    await _recoverStuckEntries();
    _paused = false;
    _running = true;
    _processed = 0;
    _passStartedAt = DateTime.now();
    await _box.put(_metaKey, {
      'running': true,
      'paused': false,
      'startedAt': _passStartedAt!.toIso8601String(),
    });
    notifyListeners();
    await _enqueueRemaining();
    _totalTarget = _pendingQueue.length;
    await _drain();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_running) return;
    _paused = true;
    final meta = _box.get(_metaKey);
    if (meta is Map) {
      await _box.put(_metaKey, {...meta, 'paused': true});
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_running || !_paused) return;
    _paused = false;
    final meta = _box.get(_metaKey);
    if (meta is Map) {
      await _box.put(_metaKey, {...meta, 'paused': false});
    }
    notifyListeners();
    await _drain();
  }

  /// Crash recovery: anything stuck in `processing` is re-queued, and box
  /// entries whose file no longer exists are marked skipped.
  Future<void> _recoverStuckEntries() async {
    final files = await _enumerator.listMostRecentFirst();
    final livePaths = files.map((f) => f.path).toSet();
    for (final key in _box.keys) {
      if (key == _metaKey) continue;
      final entry = _box.get(key);
      if (entry is! Map) continue;
      final status = entry['status'];
      if (status == _statusProcessing) {
        await _box.put(key, {...entry, 'status': _statusPending});
      } else if ((status == _statusPending || status == _statusProcessing) &&
          !livePaths.contains(key)) {
        await _box.put(key, {...entry, 'status': _statusSkipped});
      }
    }
  }

  Future<void> _enqueueRemaining() async {
    final files = await _enumerator.listMostRecentFirst();
    for (final f in files) {
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
      _pendingQueue.add(f.path);
    }
  }

  Future<void> _drain() async {
    while (_running && !_paused) {
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
        await _enqueueRemaining();
        _totalTarget = _processed + _pendingQueue.length;
        if (_pendingQueue.isEmpty) break;
        continue;
      }
      await _process(next);
    }

    if (_running && !_paused) {
      _running = false;
      await _box.put(_metaKey, {
        'running': false,
        'paused': false,
        'startedAt': _passStartedAt?.toIso8601String(),
        'finishedAt': DateTime.now().toIso8601String(),
      });
      provider.flushBulkNotify();
      if (onPassComplete != null) {
        await onPassComplete!();
      }
      notifyListeners();
    }
  }

  Future<void> _process(String path) async {
    final now = DateTime.now();
    final entry = _box.get(path);
    await _box.put(path, {
      ...(entry is Map ? entry : const {}),
      'status': _statusProcessing,
    });

    try {
      final ocrText = await _ocrWithRetry(path);
      // Skip visual labeling when OCR already produced rich text — the text
      // is the search surface there; labels mainly help text-less images.
      final labels = ScreenshotProvider.shouldLabel(ocrText)
          ? await _labelsFor(path)
          : const <String>[];
      final capturedAt = _capturedAt(path);
      final id = await provider.addFromBulkIngest(
        path: path,
        capturedAt: capturedAt,
        ocrText: ocrText,
        objects: labels,
      );
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
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusSkipped,
        'lastError': e.message,
        'processedAt': DateTime.now().toIso8601String(),
      });
    } on _OcrExhausted catch (e) {
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusFailed,
        'lastError': e.message,
        'processedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await _box.put(path, {
        ...(entry is Map ? entry : const {}),
        'status': _statusFailed,
        'lastError': e.toString(),
        'processedAt': DateTime.now().toIso8601String(),
      });
    }

    _processed++;
    _progress.add(_processed);
    notifyListeners();
  }

  Future<List<String>> _labelsFor(String path) async {
    try {
      return await labeler?.labelsFor(path) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<String> _ocrWithRetry(String path) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      try {
        return await ocr.extractText(path);
      } catch (e) {
        lastError = e;
        if (e is FileSystemException) rethrow;
        if (attempt < retryDelays.length) {
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
    }
    throw _OcrExhausted('$lastError');
  }

  DateTime _capturedAt(String path) {
    try {
      return File(path).statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }
}
