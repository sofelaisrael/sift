/// Everything SIFT knows about the one optional on-device model, in one place.
///
/// The `.litertlm` bundle is never bundled in the app: it is fetched once over
/// a fixed HTTPS URL by the LiteRT-LM runtime's own model manager and then runs
/// entirely on this device. Keeping the URL, the expected file name, the size
/// ceiling, and the license note together means a reader can audit the whole
/// download story from a single file.
abstract final class LocalModelSpec {
  /// The logical model id: the base of [fileName] and the name SIFT uses for
  /// the model in copy and in tests. It is not a key the runtime knows — the
  /// runtime's own model store is keyed on the exact file name it derives from
  /// [downloadUrl], so every lookup and removal has to go through [fileName].
  static const String modelId = 'Qwen3-0.6B';

  /// The LiteRT-LM bundle format. The runtime applies the model's own chat
  /// template to this format, so SIFT never hand-builds one.
  static const String fileExtension = '.litertlm';

  /// File name SIFT identifies the installed model by.
  static const String fileName = '$modelId$fileExtension';

  /// Fixed source: the official LiteRT community repository. No query string,
  /// no mirror, no fallback host — one place to audit. Public model, so no
  /// Hugging Face token and no account is involved.
  static const String downloadUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
      'Qwen3-0.6B.litertlm';

  /// What the host serves for [downloadUrl] today: 614236160 bytes. Pinned so
  /// a change in the published bundle is a visible diff rather than a surprise
  /// on a user's phone.
  static const int expectedBytes = 614236160;

  /// Declared size ceiling, in bytes. It leaves roughly 20% headroom above
  /// [expectedBytes] and refuses to describe anything that would fill a
  /// device.
  ///
  /// This is a stated bound, not an enforced guard: the transfer belongs to the
  /// LiteRT-LM runtime's model manager, which reports whole-percent progress
  /// and exposes no byte count mid-transfer. SIFT therefore never shows it and
  /// never claims to have blocked an oversized transfer — it exists so the test
  /// that pins it above the real file has something to pin. The size the user
  /// is shown is [approxSizeLabel], which describes the bundle that is actually
  /// fetched rather than a bound nothing enforces.
  static const int maxBytes = 700 * 1024 * 1024;

  /// Approximate download size shown before the user agrees to the transfer.
  /// Honest wording about what is being fetched, not a promise about a
  /// Content-Length.
  static const String approxSizeLabel = 'about 614 MB';

  /// Short attribution for the settings row and the about dialog.
  static const String licenseNote =
      'Qwen3 0.6B (LiteRT-LM bundle) from the official LiteRT community repo on '
      'Hugging Face, Apache-2.0. Downloaded once, then run on this device with '
      'Google’s LiteRT-LM runtime (Apache-2.0).';

  /// The local runtime, named in copy so the settings row says what actually
  /// runs the model.
  static const String runtimeName = 'LiteRT-LM';
}
