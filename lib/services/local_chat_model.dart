/// Provider-neutral contract for the optional on-device conversational model.
///
/// Deliberately free of Flutter plugin types: unit tests can supply a plain
/// fake for the chat path, and swapping the LiteRT-LM backend later must not
/// ripple into `ChatEngine`. The only implementation today is
/// `LiteRtLocalChatModel` (Google's Apache-2.0 LiteRT-LM runtime, reached
/// through the MIT-licensed flutter_gemma packages).
library;

/// Readiness of the on-device model. Only [ready] can answer, and only then
/// does a local-only question prefer the model over the plain local reply.
enum LocalChatModelStatus {
  /// No model on this device. Chat falls back to the plain local reply.
  notInstalled,

  /// An explicit setup download is streaming. Started only by the setup
  /// action in More, never at startup and never by a question.
  downloading,

  /// The model is on this device but the inference engine has not been
  /// created yet. Kept distinct from [ready] so the row can say "downloaded,
  /// loads on first question" instead of claiming a model that cannot answer.
  installed,

  /// The engine is being created and the weights read into memory.
  loading,

  /// The engine is loaded and the model can answer.
  ready,

  /// The last attempt failed. [LocalChatModel.statusMessage] explains why in
  /// fixed copy — never a raw plugin, socket, or platform error. A failed load
  /// lands here too, so `ready` is never left standing on a broken engine.
  error,
}

/// One progress tick from the setup download.
///
/// The LiteRT-LM runtime reports whole-percent progress, so that is what this
/// carries: there is no byte count to report and none is invented. [percent] is
/// clamped into 0..100 by the constructors that build one.
class LocalChatDownloadProgress {
  LocalChatDownloadProgress(int percent)
      : percent = percent < 0 ? 0 : (percent > 100 ? 100 : percent);

  final int percent;

  double get fraction => percent / 100;
}

/// Cooperative cancellation for the setup download.
///
/// A cancel that lands before the runtime has produced a real canceller is
/// remembered and applied on [attach], so a cancel racing the transfer still
/// sticks. This is not immediate abort: the transfer stops on the runtime's
/// next checkpoint, and the staged bytes are discarded by the runtime.
class LocalChatCancellation {
  final List<void Function()> _cancellers = [];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    // Copied first: a canceller that unregisters would otherwise mutate the
    // list mid-iteration.
    for (final cancel in List<void Function()>.of(_cancellers)) {
      cancel();
    }
  }

  /// Registers the implementation's real canceller. Called by the backend once
  /// it holds one; SIFT itself never calls this.
  void attach(void Function() cancel) {
    if (_cancelled) {
      cancel();
      return;
    }
    _cancellers.add(cancel);
  }
}

/// What a removal of the model actually achieved.
///
/// Three outcomes, not a bool: a bool cannot tell a deleted file apart from a
/// model that was never there, and that difference is the difference between
/// "removed" and a claim about a file SIFT cannot see.
enum LocalModelRemoval {
  /// A file was deleted from this device. Only this outcome may be reported to
  /// the user as a removal.
  removed,

  /// Nothing was registered, so nothing had to be deleted. The device is free
  /// of the model either way, but no file was removed by this call.
  notRegistered,

  /// The model could not be removed, or its removal could not be confirmed.
  /// The file may still be on this device.
  failed,
}

/// An on-device chat model SIFT can answer with without any network call.
abstract class LocalChatModel {
  LocalChatModelStatus get status;

  /// Fixed, user-facing explanation of the last failure, or null. Never a raw
  /// plugin, socket, or filesystem error: those can carry a path or a URL.
  String? get statusMessage;

  /// True when the model is present and able to answer. Callers that cannot
  /// afford a load attempt should check this first.
  bool get isUsable => status == LocalChatModelStatus.ready;

  /// Whether the model is present on this device. A local read of the
  /// runtime's own model metadata, never a request. This stays true while the
  /// model sits in [LocalChatModelStatus.error] after a failed load, so callers
  /// can tell "never downloaded" from "downloaded but broken".
  Future<bool> isInstalled();

  /// Fetch and register the model. Explicit setup only: nothing calls this
  /// implicitly and nothing calls it at startup. A call made while another is
  /// in flight joins the running one, and a model that is already installed is
  /// never re-fetched. [onProgress] reports exactly what the runtime reported,
  /// never an estimate, so a value on screen is the runtime's own. Every
  /// outcome is reported through [status]: a cancel returns to
  /// [LocalChatModelStatus.notInstalled] rather than raising an error, and a
  /// failure lands in [LocalChatModelStatus.error] with fixed copy in
  /// [statusMessage].
  Future<void> download({
    void Function(LocalChatDownloadProgress value)? onProgress,
    LocalChatCancellation? cancellation,
  });

  /// Materialize the engine if it is not in memory yet. Returns false when the
  /// model is missing or failed to load, and never downloads: a chat question
  /// must never turn into a multi-hundred-megabyte transfer.
  Future<bool> ensureLoaded();

  /// Answer one question. [prompt] carries the grounding rules and the
  /// question, [context] the screenshot block; the implementation joins them
  /// into a single self-contained user turn and lets the runtime apply the
  /// model's own chat template. Throws when the model is unusable — deciding
  /// what to show instead is the caller's job.
  Future<String> generate({
    required String prompt,
    required String context,
    int maxTokens = 256,
  });

  /// Delete the model from this device and release the engine. Reports what it
  /// achieved as a [LocalModelRemoval], so the caller can say a file was removed
  /// only when one actually was. [LocalModelRemoval.failed] covers both a
  /// removal that failed and one that cannot be confirmed: after a failed
  /// removal, a later read that finds nothing registered is not evidence the
  /// file went with it, so it must not be reported as [LocalModelRemoval.removed].
  Future<LocalModelRemoval> remove();

  /// Release the engine and any owned resources. The model file is left on
  /// this device; [remove] is the only thing that deletes it.
  Future<void> dispose();
}
