import 'package:flutter/foundation.dart';

import 'device_memory.dart';
import 'litert_local_chat_model.dart';
import 'local_chat_model.dart';

/// App-lifetime owner of the optional on-device model.
///
/// It exists so the model has exactly one place that decides *when* work
/// happens, and the UI has one place to read. Nothing here runs at startup: the
/// LiteRT-LM bundle is fetched only through [startDownload] (the explicit setup
/// action in More) and the engine is created only by a local-only question
/// that actually needs an answer.
class LocalModelService extends ChangeNotifier {
  /// [isSupportedDevice] exists so a test can drive a device the runtime cannot
  /// run on; production always asks the runtime, the only thing that knows
  /// which architectures it ships a native library for. [isLowRamDevice] is the
  /// same escape hatch for the memory question, which no test can present
  /// without a phone.
  LocalModelService({
    required this.model,
    bool? isSupportedDevice,
    bool? isLowRamDevice,
  })  : _isSupportedDevice =
            isSupportedDevice ?? LiteRtLocalChatModel.isSupportedDevice,
        _isLowRamDevice = isLowRamDevice ?? DeviceMemory.isLowRam;

  /// The owned model. The chat path takes this so it depends on
  /// [LocalChatModel] alone, not on this notifier.
  final LocalChatModel model;

  /// Whether this device's architecture can run the model. The runtime ships a
  /// native library for arm64-v8a on Android only, so on x86_64 or 32-bit the
  /// 614 MB could be fetched and still never load. The UI reads this to keep
  /// the setup action off the row entirely.
  bool get isSupportedDevice => _isSupportedDevice;

  /// Whether the OS classes this device as short on memory. A 614 MB bundle read
  /// whole into a phone with little to spare fails while the weights load, so
  /// the setup action asks before it offers anything.
  ///
  /// This is the warmed cache, not a read: a widget `build` cannot await a
  /// platform message. [startDownload] asks the platform itself, so a cold cache
  /// costs the transfer nothing — it just means the row's own copy stays quiet
  /// until the answer has been read once.
  bool get isLowRamDevice => _isLowRamDevice;

  /// Why the setup action is unavailable here, in the same fixed copy the model
  /// itself would show. Names the architecture requirement and nothing else: no
  /// host, no connection, no path.
  String get unsupportedDeviceNote =>
      LiteRtLocalChatModel.unsupportedDeviceNote;

  /// [unsupportedDeviceNote]'s counterpart for a phone the OS classes as low on
  /// memory. Shared with the model so the two cannot drift.
  String get lowRamDeviceNote => LiteRtLocalChatModel.lowRamDeviceNote;

  final bool _isSupportedDevice;
  final bool _isLowRamDevice;

  /// Set when a setup action was refused here rather than by the model, which
  /// was never asked. It is why [status] can be [LocalChatModelStatus.error]
  /// with no failed transfer behind it.
  String? _refusal;

  LocalChatModelStatus get status =>
      _refusal == null ? model.status : LocalChatModelStatus.error;
  String? get statusMessage => _refusal ?? model.statusMessage;
  bool get isUsable => model.isUsable;
  bool get isDownloading => status == LocalChatModelStatus.downloading;

  /// Whether the model is on this device, as last observed. Kept apart from
  /// [status] because a downloaded model is usable while still unloaded, and a
  /// model that failed to load is still on the device.
  bool get installed => _installed;

  /// Progress of the running download, or null outside one.
  LocalChatDownloadProgress? get progress => _progress;
  double? get downloadFraction => _progress?.fraction;

  /// Percent of the running download, or null when there is none.
  int? get downloadPercent => _progress?.percent;

  bool _installed = false;
  LocalChatDownloadProgress? _progress;
  LocalChatCancellation? _cancellation;
  Future<void>? _activeDownload;

  /// Re-read the on-device state. A local metadata read only: safe whenever
  /// More opens, and it never reaches the network.
  Future<void> refresh() async {
    final installed = await model.isInstalled();
    if (_installed == installed) return;
    _installed = installed;
    notifyListeners();
  }

  /// The explicit setup action. No implicit caller exists, so nothing can
  /// start a transfer the user did not ask for. A second tap while a download
  /// is running joins the first.
  ///
  /// On a device that cannot run the model it refuses without asking the
  /// runtime: no request is made, no byte moves, and the reason is in
  /// [statusMessage] instead of a 614 MB file that can never load. That covers
  /// both gates — see [deviceRefusal], which is the one place that decides.
  Future<void> startDownload() async {
    final refused = await deviceRefusal();
    if (refused != null) {
      _refusal = refused;
      _progress = null;
      notifyListeners();
      return;
    }
    // A refusal from an earlier attempt must not survive into one that is
    // proceeding. Cleared here rather than before the check so the row keeps
    // showing its old reason while the device is still being asked.
    _refusal = null;
    final active = _activeDownload;
    if (active != null) return active;
    final operation = _download();
    _activeDownload = operation;
    return operation.whenComplete(() {
      if (identical(_activeDownload, operation)) _activeDownload = null;
    });
  }

  /// The fixed sentence that refuses a transfer on this device, or null when
  /// none applies.
  ///
  /// Both device gates pass through here so there is one refusal and one copy
  /// per reason, and no path that starts a transfer the others would refuse.
  ///
  /// The memory check is awaited rather than read from [isLowRamDevice] because
  /// this is the one call where the difference between "answered no" and "never
  /// asked" decides whether 614 MB moves. A cache hit short-circuits, so the
  /// platform message is only sent when the answer is genuinely missing.
  Future<String?> deviceRefusal() async {
    if (!isSupportedDevice) return unsupportedDeviceNote;
    if (isLowRamDevice) return lowRamDeviceNote;
    return await DeviceMemory.check() ? lowRamDeviceNote : null;
  }

  Future<void> _download() async {
    _cancellation = LocalChatCancellation();
    // Seeded at 0 so the row shows a percentage from the first frame even
    // before the runtime reports a tick. Every later value is the runtime's
    // own, so nothing here is an estimate of its progress.
    _progress = LocalChatDownloadProgress(0);
    _installed = false;
    notifyListeners();
    try {
      await model.download(
        onProgress: (value) {
          _progress = value;
          notifyListeners();
        },
        cancellation: _cancellation,
      );
    } catch (_) {
      // The download reports its own failures through its status, but the
      // setup action is fired and forgotten by the UI, so an escaping error
      // would become an unhandled async error rather than a visible state.
    } finally {
      _cancellation = null;
      _progress = null;
      _installed = await model.isInstalled();
      notifyListeners();
    }
  }

  /// Ask the running download to stop. Nothing is installed afterwards, so the
  /// next attempt starts from scratch.
  void cancelDownload() => _cancellation?.cancel();

  /// Delete the model from this device through the manager that owns it.
  /// Reports what the removal actually achieved, so a caller can claim a
  /// deleted file only when one was deleted. [LocalModelRemoval.failed] also
  /// covers a removal that could not be confirmed, which is the outcome to
  /// treat as "the file may still be here".
  Future<LocalModelRemoval> removeModel() async {
    _cancellation?.cancel();
    _progress = null;
    // Whatever the model then reports is the truth about the model.
    _refusal = null;
    final outcome = await model.remove();
    // A removal that did not delete a file leaves the answer to a fresh read:
    // `removed` says there is nothing left, and the other two have to ask
    // rather than assume.
    _installed = outcome == LocalModelRemoval.removed
        ? false
        : await model.isInstalled();
    notifyListeners();
    return outcome;
  }

  @override
  void dispose() {
    // The engine goes back to the OS; the model stays until removeModel().
    model.dispose();
    super.dispose();
  }
}
