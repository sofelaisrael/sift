/// Non-secret app metadata for builds.
///
/// Sift ships no provider or YouTube API key, in any build. Cloud chat and
/// source lookup run only against a key the user saved in Settings; without
/// one, no hosted request is made. `lib/config.dart` is gitignored — copy this
/// file there for a local build, or have CI copy it (see `codemagic.yaml` and
/// `.github/workflows/release.yml`).
///
/// Do not add credential fields or CI-injected secrets here: anything in this
/// file ends up inside the release binary.
class AppConfig {
  /// Provider selected for hosted text chat until the user picks one.
  /// Non-secret: it is a name, resolved against a key the user saved.
  static const String defaultProvider = 'Google Gemini';

  /// Display name for the app. Non-secret.
  static const String appName = 'Sift';
}
