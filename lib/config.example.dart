class AppConfig {
  // API keys - set these locally or inject via CI env vars (see codemagic.yaml)
  static const String groqApiKey = '';
  static const String geminiApiKey = '';
  static const String cerebrasApiKey = '';
  static const String openRouterApiKey = '';

  // Default provider - Gemini for images
  static const String defaultProvider = 'Google Gemini';

  // App info
  static const String appName = 'Sift';

  /// Resolve a configured API key for a provider, or null if none is set.
  /// Used as a fallback when the user has not entered a key in Settings.
  static String? apiKeyFor(String provider) {
    switch (provider) {
      case 'Google Gemini':
        return geminiApiKey.isEmpty ? null : geminiApiKey;
      case 'Groq':
        return groqApiKey.isEmpty ? null : groqApiKey;
      case 'Cerebras':
        return cerebrasApiKey.isEmpty ? null : cerebrasApiKey;
      case 'OpenRouter':
        return openRouterApiKey.isEmpty ? null : openRouterApiKey;
      default:
        return null;
    }
  }
}
