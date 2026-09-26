import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'local_chat_model.dart';
import 'local_model_spec.dart';

/// One open chat over the loaded engine. Closed after every question so no
/// screenshot text survives into the next turn's context.
abstract class LiteRtSession {
  /// Send one user turn and return the whole answer. The runtime applies the
  /// model's own chat template to the turns, so nothing here is hand-built.
  Future<String> ask(String userText);

  /// Close this conversation. The engine and its weights stay loaded.
  Future<void> close();
}

/// The flutter_gemma calls [LiteRtLocalChatModel] makes.
///
/// A seam, not an abstraction for its own sake: [FlutterGemmaLiteRt] is the
/// real implementation, it wraps the runtime's documented model-management and
/// chat APIs one-for-one, and tests substitute a fake so no test needs the
/// native LiteRT library, a real model, an Android SDK, or a network.
abstract class LiteRtGateway {
  /// True when the runtime's model manager already holds [modelFileName] on this
  /// device. A local metadata read.
  ///
  /// This takes the bundle's exact file name, not the bare model id: the
  /// runtime keys its model store on the file name it derives from the download
  /// URL and matches it exactly, so `Qwen3-0.6B` finds nothing and the lookup
  /// silently reports a model that is on disk as absent.
  Future<bool> isInstalled(String modelFileName);

  /// Fetch [url] and register it with the runtime's model manager. Reports
  /// 0-100 through [onProgress] and stops when [cancellation] is cancelled.
  ///
  /// [modelId] is the logical name SIFT calls this model; the real gateway
  /// never hands it to the runtime. The store key is the basename the runtime
  /// derives from [url], so the URL has to end in [LocalModelSpec.fileName] or
  /// every later lookup misses. The parameter stays on the seam so a fake can
  /// assert against the same spec constant the model passes.
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  });

  /// Delete [modelFileName] and its registration from this device. The same key
  /// [isInstalled] uses: with the bare model id the runtime would delete
  /// nothing and the file would survive a removal the user was told succeeded.
  Future<void> uninstall(String modelFileName);

  /// Forget the runtime's saved active-model choice, so the next launch does
  /// not come back pointing at a bundle that has just been deleted. It takes no
  /// name to forget: the runtime keys the active inference identity by
  /// [ModelType], and SIFT clears it after every [uninstall] because a stale
  /// choice is harmless once the file is gone.
  Future<void> clearActiveIdentity();

  /// Create the engine over the active model. This is the expensive step — the
  /// one that reads the weights — so it happens once, lazily, and never at
  /// startup. [contextTokens] is the KV-cache budget shared by the input and
  /// the reply; [backend] picks CPU or GPU.
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  });

  /// Open one conversation over the already-loaded engine.
  /// [maxOutputTokens] caps the generated part of a single answer.
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  });

  /// Release the engine and its weights. Safe when nothing is loaded.
  Future<void> close();
}

/// Why an install or a load did not work, in terms SIFT can turn into copy
/// without echoing a host, a status code, a path, or a plugin exception.
enum LiteRtFailure {
  /// The host refused, or the bundle is not where the spec says.
  hostRefused,

  /// No connection, or the transfer was cut off partway through.
  connection,

  /// The host is rate limiting or unavailable.
  hostBusy,

  /// The engine could not be created on this device.
  loadFailed,

  /// The model could not be deleted from this device.
  removeFailed,

  /// A removal failed earlier and the model is no longer registered, so nothing
  /// here can say whether the file went with the record. The one claim SIFT must
  /// not make is that the space is free.
  removeUnconfirmed,

  /// This device's architecture has no LiteRT-LM native library, so the model
  /// can never be loaded here. Neither the host nor the connection is at
  /// fault: the transfer would succeed and still be unusable. Raised by the
  /// model itself when it finds a bundle on a device it cannot run, so that
  /// case reports this same sentence rather than a second one.
  unsupportedArchitecture,
}

/// The user asked to stop. Not a failure: nothing is installed and the row
/// offers the download again.
class LiteRtInstallCancelled implements Exception {
  const LiteRtInstallCancelled();
}

/// An install or removal that failed, reduced to a fixed reason SIFT is willing
/// to show. [reason] is never anything the transport, the plugin, or the
/// filesystem said.
class LiteRtOperationFailed implements Exception {
  const LiteRtOperationFailed(this.reason);

  final LiteRtFailure reason;
}

/// The LiteRT-LM backend for [LocalChatModel].
///
/// Owns the one optional on-device model end to end: the runtime's model
/// manager downloads and registers the `.litertlm` bundle, the LiteRT-LM engine
/// answers on this device, and nothing here reaches a hosted provider.
///
/// Nothing runs at construction. [register] must be called once at startup and
/// only registers the engine — it downloads nothing and reads no weights. The
/// bundle is fetched only through [download] (the explicit setup action) and
/// the engine is created only by [ensureLoaded] or the first [generate].
class LiteRtLocalChatModel implements LocalChatModel {
  LiteRtLocalChatModel({
    LiteRtGateway? gateway,
    PreferredBackend backend = PreferredBackend.cpu,
    this.contextTokens = defaultContextTokens,
    bool? isSupportedDevice,
  })  : _gateway = gateway ?? FlutterGemmaLiteRt(),
        _backend = backend,
        _isSupportedDevice =
            isSupportedDevice ?? LiteRtLocalChatModel.isSupportedDevice;

  /// KV-cache budget. A 0.6B bundle on a phone answers acceptably here, and a
  /// large window is the fastest way to run a device out of memory. The
  /// runtime raises anything below 1024 to its own floor.
  static const int defaultContextTokens = 2048;

  /// Floor and ceiling for one answer. The floor keeps a stray tiny request
  /// from being cut off mid-word; the ceiling stops a 0.6B model on a phone
  /// from spending seconds per token on text that adds nothing here.
  static const int minMaxTokens = 64;
  static const int maxTokensCap = 512;

  /// Characters of context kept, sized to leave room for the grounding rules
  /// and the question inside [contextTokens] tokens.
  static const int _contextChars = 6000;

  /// The one sentence SIFT shows for a device that cannot run the model at all.
  /// Fixed copy like every other reason here: the runtime's own error names an
  /// ABI string and a package, neither of which means anything to a user.
  static const String unsupportedDeviceNote =
      'On-device chat needs an arm64-v8a device, which this is not. SIFT keeps '
      'using the plain local reply.';

  /// Whether this device's architecture can run the runtime at all.
  ///
  /// Google publishes the LiteRT-LM native library for arm64-v8a only, so on
  /// x86_64 or 32-bit Android the transfer can be fetched and then never
  /// loaded. SIFT therefore asks before offering it, not after.
  ///
  /// Fails open on purpose: a detection that throws reports true, because
  /// refusing a real arm64 device over a read that failed is a worse failure
  /// than a download that ends in an honest "could not be loaded".
  static bool get isSupportedDevice {
    try {
      if (!Platform.isAndroid) return true;
      return Abi.current() == Abi.androidArm64;
    } catch (_) {
      return true;
    }
  }

  /// The grounding contract handed to the runtime as the model's system
  /// instruction, so the LiteRT-LM chat template places it where the model's
  /// own template expects a system turn instead of SIFT inventing one.
  static const String systemInstruction =
      'You are SIFT, answering a question about the user\'s saved screenshots.\n'
      'Answer ONLY from the CONTEXT you are given. Never invent a screenshot, '
      'a detail, or a fact that is not in it.\n'
      'If the CONTEXT does not contain the answer, say so plainly and stop. '
      'Do not guess and do not use outside knowledge.\n'
      'Be concise and plain text: no markdown, no headings, no bullet lists, no '
      'preamble.\n'
      'Do not mention screenshots, CONTEXT, or that you are an AI. Just answer.';

  final LiteRtGateway _gateway;
  final PreferredBackend _backend;

  /// The architecture answer, injectable so a test can present a device the
  /// runtime cannot run on. Production always asks [isSupportedDevice], the only
  /// thing that knows which architectures the native library ships for.
  final bool _isSupportedDevice;

  /// Context budget for the engine. Injectable so a test can shrink it.
  final int contextTokens;

  LocalChatModelStatus _status = LocalChatModelStatus.notInstalled;
  String? _statusMessage;
  bool _engineLoaded = false;
  bool _loadFailed = false;

  /// Set when a removal could not be confirmed, cleared only by a removal that
  /// actually deleted something. While it stands, a read that finds no model
  /// registered proves only that the record is gone — the runtime keeps that
  /// index in the same SharedPreferences store a "Delete everything" wipe
  /// clears, so a wipe after a failed removal leaves the file with nothing
  /// pointing at it. The flag is what stops that from being reported as a
  /// removal.
  bool _removalUnconfirmed = false;
  bool _disposed = false;
  Future<void>? _activeDownload;
  Future<bool>? _activeLoad;

  @override
  LocalChatModelStatus get status => _status;

  @override
  String? get statusMessage => _statusMessage;

  @override
  bool get isUsable => _status == LocalChatModelStatus.ready;

  /// Registers the LiteRT-LM engine. Call once at startup, before anything asks
  /// the model a question.
  ///
  /// Registration only: no download, no weights read, no model on disk
  /// required. Plugin logging is silenced here rather than left at its default
  /// because the verbose level writes prompts and conversation history, and
  /// those are screenshot text.
  static Future<void> register() async {
    FlutterGemma.logLevel = GemmaLogLevel.none;
    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
  }

  void _setStatus(LocalChatModelStatus next, [String? message]) {
    if (_status == next && _statusMessage == message) return;
    _status = next;
    _statusMessage = message;
  }

  @override
  Future<bool> isInstalled() async {
    if (_disposed) return false;
    try {
      return await _gateway.isInstalled(LocalModelSpec.fileName);
    } catch (_) {
      // A plugin or filesystem failure here means "cannot confirm", which for a
      // privacy-first app is the same as absent: chat falls back.
      return false;
    }
  }

  @override
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) {
    final active = _activeDownload;
    if (active != null) return active;
    final operation =
        _download(onProgress: onProgress, cancellation: cancellation);
    _activeDownload = operation;
    return operation.whenComplete(() {
      if (identical(_activeDownload, operation)) _activeDownload = null;
    });
  }

  Future<void> _download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  }) async {
    // A retry always starts from a clean slate: the previous failure message
    // must not survive into a fresh attempt.
    _loadFailed = false;
    _statusMessage = null;

    // Idempotent: a model that is already on this device is never re-fetched,
    // so a second tap on Download is free and makes no request.
    if (await isInstalled()) {
      _setStatus(
        _engineLoaded
            ? LocalChatModelStatus.ready
            : LocalChatModelStatus.installed,
      );
      return;
    }
    if (cancellation?.isCancelled ?? false) {
      _setStatus(LocalChatModelStatus.notInstalled);
      return;
    }

    _setStatus(LocalChatModelStatus.downloading);
    try {
      await _gateway.install(
        modelId: LocalModelSpec.modelId,
        url: LocalModelSpec.downloadUrl,
        onProgress: (percent) {
          // A cancel that lands after the transfer finished must not rewind a
          // completed install.
          if (cancellation?.isCancelled ?? false) return;
          onProgress?.call(LocalChatDownloadProgress(percent));
        },
        // A fresh token per attempt: cancelling the previous download must not
        // cancel this one.
        cancellation: cancellation ?? LocalChatCancellation(),
      );
    } on LiteRtInstallCancelled {
      // Not an error. Nothing is installed, so the row offers the download.
      _setStatus(LocalChatModelStatus.notInstalled);
      return;
    } on LiteRtOperationFailed catch (error) {
      if (_userCancelled(cancellation)) return;
      debugPrint('On-device model download failed');
      _setStatus(LocalChatModelStatus.error, _failureCopy(error.reason));
      return;
    } catch (_) {
      if (_userCancelled(cancellation)) return;
      // A plugin, socket, or filesystem error can echo the URL, a CDN host, a
      // status code, or an absolute path. None of it is logged or shown.
      debugPrint('On-device model download failed');
      _setStatus(
        LocalChatModelStatus.error,
        _failureCopy(LiteRtFailure.connection),
      );
      return;
    }

    // Trust the manager, not the exception: an install that returned is
    // installed. Anything else would report `installed` over a missing file.
    if (!await isInstalled()) {
      _setStatus(
        LocalChatModelStatus.error,
        'The model was not saved on this device. Try the download again.',
      );
      return;
    }
    _setStatus(LocalChatModelStatus.installed);
  }

  /// Whether the failure now being handled is really a cancel the user asked
  /// for, and so must not become an error state.
  ///
  /// The runtime has two cancel paths and SIFT can only see the result of
  /// either: a `DownloadCancelledException`, or a `DownloadException` carrying
  /// `DownloadError.canceled()`, which [FlutterGemmaLiteRt] cannot tell apart
  /// from a network cut because the sealed type is all it matches on. The token
  /// is the one thing both paths share, so it is asked before any failure is
  /// mapped to copy. Nothing is installed after a cancel, so the state is
  /// [LocalChatModelStatus.notInstalled] and the row offers the download again
  /// — while `LiteRtFailure.connection` would send the user to fix a connection
  /// they never lost.
  bool _userCancelled(LocalChatCancellation? cancellation) {
    if (!(cancellation?.isCancelled ?? false)) return false;
    _setStatus(LocalChatModelStatus.notInstalled);
    return true;
  }

  /// Fixed copy per failure reason. Nothing from the transport, the plugin, or
  /// the filesystem is interpolated into any of these.
  static String _failureCopy(LiteRtFailure reason) {
    switch (reason) {
      case LiteRtFailure.hostRefused:
        return 'The model host refused the download. Try again later.';
      case LiteRtFailure.connection:
        return 'The model could not be downloaded. Check your connection and '
            'try again.';
      case LiteRtFailure.hostBusy:
        return 'The model host is busy or limiting requests. Wait a few '
            'minutes and try again.';
      case LiteRtFailure.loadFailed:
        return 'The model could not be loaded on this device. SIFT will keep '
            'using the plain local reply.';
      case LiteRtFailure.removeFailed:
        return 'The model could not be removed from this device.';
      case LiteRtFailure.removeUnconfirmed:
        return 'The model file could not be deleted, and SIFT can no longer '
            'track it. Removing the app frees the space.';
      case LiteRtFailure.unsupportedArchitecture:
        return unsupportedDeviceNote;
    }
  }

  @override
  Future<bool> ensureLoaded() {
    if (_engineLoaded && _status == LocalChatModelStatus.ready) {
      return Future<bool>.value(true);
    }
    final active = _activeLoad;
    if (active != null) return active;
    final operation = _load();
    _activeLoad = operation;
    return operation.whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
  }

  Future<bool> _load() async {
    if (_disposed) return false;
    // A load that already failed is not retried per question: recreating the
    // engine to watch it fail again would stall every local chat. The flag is
    // cleared by download() and remove().
    if (_loadFailed) return false;
    if (!await isInstalled()) {
      _setStatus(LocalChatModelStatus.notInstalled);
      return false;
    }
    // A model can be on this device without SIFT having put it there — a
    // sideloaded bundle, a restored backup — and the setup action's architecture
    // check only guards SIFT's own transfer. There is no native library here to
    // read the weights with, so the load is not attempted and the true cause is
    // reported instead of a vague "could not be loaded". Not flagged as a failed
    // load to retry around: the architecture does not change while the app runs.
    if (!_isSupportedDevice) {
      _loadFailed = true;
      _setStatus(
        LocalChatModelStatus.error,
        _failureCopy(LiteRtFailure.unsupportedArchitecture),
      );
      return false;
    }
    _setStatus(LocalChatModelStatus.loading);
    try {
      await _gateway.load(contextTokens: contextTokens, backend: _backend);
      _engineLoaded = true;
      _setStatus(LocalChatModelStatus.ready);
      return true;
    } catch (_) {
      // Plugin exceptions can echo the model path and native internals.
      _engineLoaded = false;
      _loadFailed = true;
      _setStatus(
        LocalChatModelStatus.error,
        _failureCopy(LiteRtFailure.loadFailed),
      );
      return false;
    }
  }

  @override
  Future<String> generate({
    required String prompt,
    required String context,
    int maxTokens = 256,
  }) async {
    if (!await ensureLoaded()) {
      throw StateError('The on-device model is not ready.');
    }
    final capped = maxTokens < minMaxTokens
        ? minMaxTokens
        : (maxTokens > maxTokensCap ? maxTokensCap : maxTokens);

    // One session per question, opened and closed around it: the weights are
    // loaded once and shared, but no screenshot text survives into the next
    // turn's context.
    final session = await _gateway.openChat(
      maxOutputTokens: capped,
      systemInstruction: systemInstruction,
    );
    try {
      return (await session.ask(_composePrompt(prompt, context))).trim();
    } finally {
      await session.close();
    }
  }

  /// One self-contained user turn. The caller's rules and question come first
  /// so a long context is what gets trimmed, never the instructions. Where the
  /// turns land in the model's own chat template is the runtime's decision.
  String _composePrompt(String prompt, String context) {
    final budget = _contextChars - prompt.length;
    final body = budget <= 0
        ? ''
        : context.length > budget
            ? '${context.substring(0, budget)}…'
            : context;
    if (body.isEmpty) return prompt;
    return '$prompt\n\nCONTEXT:\n$body';
  }

  @override
  Future<LocalModelRemoval> remove() async {
    await _releaseEngine();
    // A retry after a failed removal must not be blocked by the old flag.
    _loadFailed = false;
    if (!await isInstalled()) {
      if (_removalUnconfirmed) {
        // Nothing is registered, but a previous removal never deleted the file
        // and only the wipe removed the record of it. There is no read left that
        // could tell the two apart, so the removal is reported as unconfirmed
        // rather than as done: this is the one claim that must not be made about
        // a file nobody can reach any more.
        debugPrint('On-device model removal could not be confirmed');
        _setStatus(
          LocalChatModelStatus.error,
          _failureCopy(LiteRtFailure.removeUnconfirmed),
        );
        return LocalModelRemoval.failed;
      }
      _setStatus(LocalChatModelStatus.notInstalled);
      return LocalModelRemoval.notRegistered;
    }
    try {
      await _gateway.uninstall(LocalModelSpec.fileName);
      await _gateway.clearActiveIdentity();
    } catch (_) {
      // The path and the plugin's message are in the failure text, so neither
      // is echoed anywhere.
      debugPrint('On-device model removal failed');
      // The runtime deletes the file before the record, so a throw here can
      // leave the file behind with the record still pointing at it. Either way
      // the file may survive, so the removal is no longer something this model
      // can vouch for.
      _removalUnconfirmed = true;
      _setStatus(
        LocalChatModelStatus.error,
        _failureCopy(LiteRtFailure.removeFailed),
      );
      return LocalModelRemoval.failed;
    }
    _removalUnconfirmed = false;
    _setStatus(LocalChatModelStatus.notInstalled);
    return LocalModelRemoval.removed;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _releaseEngine();
  }

  Future<void> _releaseEngine() async {
    if (!_engineLoaded) return;
    _engineLoaded = false;
    try {
      await _gateway.close();
    } catch (_) {
      // Either nothing was loaded natively or the engine is already gone; the
      // weights are released either way.
    }
    // The file stays until remove(). A model that is only unloaded is not an
    // error, so a previous failure message is left alone here.
    if (_status == LocalChatModelStatus.error) return;
    _setStatus(
      _status == LocalChatModelStatus.notInstalled
          ? LocalChatModelStatus.notInstalled
          : LocalChatModelStatus.installed,
    );
  }
}

/// The real [LiteRtGateway]: one call per flutter_gemma API, no logic of its
/// own beyond translating the runtime's typed errors into SIFT's fixed reasons.
class FlutterGemmaLiteRt implements LiteRtGateway {
  InferenceModel? _model;

  @override
  Future<bool> isInstalled(String modelFileName) =>
      FlutterGemma.isModelInstalled(modelFileName);

  @override
  Future<void> install({
    required String modelId,
    required String url,
    required void Function(int percent) onProgress,
    required LocalChatCancellation cancellation,
  }) async {
    // modelId is unused on purpose: the runtime keys its store on the file name
    // it derives from url, and SIFT's own id is not a key it can ask about.
    final token = CancelToken();
    // Attached before the transfer starts, so a cancel that already landed
    // still reaches the runtime.
    cancellation.attach(token.cancel);
    try {
      await FlutterGemma.installModel(
        modelType: ModelType.qwen3,
        // fileType is what selects the LiteRT-LM engine: canHandle keys on
        // litertlm, and the default (.task) would route the bundle to a runtime
        // that cannot read it. modelType does not choose an engine — it tells the
        // runtime which model family this is, for the function-call format and
        // the thinking filter.
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(url)
          .withProgress(onProgress)
          .withCancelToken(token)
          .install();
    } on DownloadCancelledException {
      throw const LiteRtInstallCancelled();
    } on DownloadException catch (error) {
      throw LiteRtOperationFailed(_reasonFor(error.error));
    }
  }

  /// The runtime's own `toUserMessage()` embeds HTTP status codes and, for a
  /// network failure, the raw transport message, so SIFT matches the sealed
  /// error type and picks its own copy.
  static LiteRtFailure _reasonFor(DownloadError error) {
    switch (error) {
      case NotFoundError():
      case UnauthorizedError():
      case ForbiddenError():
        return LiteRtFailure.hostRefused;
      case RateLimitedError():
      case ServerError():
        return LiteRtFailure.hostBusy;
      case NetworkError():
      case CanceledError():
      case UnknownError():
        return LiteRtFailure.connection;
    }
  }

  @override
  Future<void> uninstall(String modelFileName) =>
      FlutterGemma.uninstallModel(modelFileName);

  @override
  Future<void> clearActiveIdentity() =>
      FlutterGemma.clearActiveInferenceIdentity();

  @override
  Future<void> load({
    required int contextTokens,
    required PreferredBackend backend,
  }) async {
    _model = await FlutterGemma.getActiveModel(
      // The context window, shared by input and output — not a reply length.
      maxTokens: contextTokens,
      preferredBackend: backend,
    );
  }

  @override
  Future<LiteRtSession> openChat({
    required int maxOutputTokens,
    required String systemInstruction,
  }) async {
    final model = _model;
    if (model == null) {
      throw StateError('The LiteRT-LM engine is not loaded.');
    }
    final chat = await model.openChat(
      systemInstruction: systemInstruction,
      maxOutputTokens: maxOutputTokens,
      modelType: ModelType.qwen3,
    );
    return _FlutterGemmaSession(chat);
  }

  @override
  Future<void> close() async {
    final model = _model;
    _model = null;
    await model?.close();
  }
}

/// One open conversation over the loaded engine.
class _FlutterGemmaSession implements LiteRtSession {
  _FlutterGemmaSession(this._chat);

  final InferenceChat _chat;

  @override
  Future<String> ask(String userText) async {
    await _chat.addQueryChunk(Message.text(text: userText, isUser: true));
    final response = await _chat.generateChatResponse();
    if (response is TextResponse) return response.token;
    // No function tools are ever registered, so anything other than text means
    // the runtime returned something SIFT cannot show.
    throw StateError('The on-device model returned an unexpected response.');
  }

  @override
  Future<void> close() => _chat.close();
}
