import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// True when `.gitignore` covers [path]. Such a file is a developer's local
/// working copy — `lib/config.dart` can hold their own keys — and a failing
/// `expect` prints the file's source, so the scan must skip it rather than echo
/// those secrets into test output.
bool _isGitIgnored(String path) {
  final normalized = path.replaceAll('\\', '/');
  for (final line in File('.gitignore').readAsLinesSync()) {
    final pattern = line.trim().replaceAll('\\', '/');
    if (pattern.isEmpty ||
        pattern.startsWith('#') ||
        pattern.startsWith('!')) {
      continue;
    }
    if (pattern.replaceFirst(RegExp('^/'), '') == normalized) return true;
  }
  return false;
}

/// Guards the "no release secrets" rule: Sift must never ship a provider or
/// YouTube key, and CI must never bake one into the build.
void main() {
  const secretEnvVars = [
    'GROQ_API_KEY',
    'GEMINI_API_KEY',
    'CEREBRAS_API_KEY',
    'OPENROUTER_API_KEY',
    'YOUTUBE_API_KEY',
  ];

  test('codemagic never interpolates a secret into the build config', () async {
    final source = await File('codemagic.yaml').readAsString();

    for (final secret in secretEnvVars) {
      expect(source, isNot(contains(secret)), reason: secret);
    }
    // The old build injected keys through a shell heredoc; that whole shape
    // is gone, along with every key-shaped field it declared.
    expect(source, isNot(contains('ENDCONFIG')));
    expect(source, isNot(contains('cat > lib/config.dart')));
    expect(source, isNot(contains('ApiKey')));
    expect(
      source,
      contains('cp lib/config.example.dart lib/config.dart'),
    );
  });

  test('the generated release workflow also stays key-free', () async {
    final source = await File('.github/workflows/release.yml').readAsString();

    for (final secret in secretEnvVars) {
      expect(source, isNot(contains(secret)), reason: secret);
    }
  });

  test('the config template carries non-secret metadata only', () async {
    final source = await File('lib/config.example.dart').readAsString();

    for (final secret in secretEnvVars) {
      expect(source, isNot(contains(secret)), reason: secret);
    }
    expect(source, isNot(contains('ApiKey')));
    expect(source, isNot(contains('apiKey')));
    expect(source, isNot(contains('apiKeyFor')));
    expect(source, contains('static const String defaultProvider'));
    expect(source, contains('static const String appName'));
  });

  test('production code has no bundled key fallback', () async {
    final entities = await Directory('lib').list(recursive: true).toList();
    var scanned = 0;
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('config.example.dart')) continue;
      if (_isGitIgnored(entity.path)) continue;
      final source = await entity.readAsString();
      scanned++;
      expect(
        source,
        isNot(contains('AppConfig.apiKeyFor')),
        reason: entity.path,
      );
      expect(
        source,
        isNot(contains('AppConfig.youTubeApiKey')),
        reason: entity.path,
      );
      for (final secret in secretEnvVars) {
        expect(
          source,
          isNot(contains(secret)),
          reason: '${entity.path}: $secret',
        );
      }
    }
    expect(scanned, greaterThan(0));
  });

  test('the local generated config stays out of the secret scan', () async {
    // A developer's `lib/config.dart` is a local copy that may still hold their
    // own keys, and the scan asserts against raw file source.
    expect(_isGitIgnored('lib/config.dart'), isTrue);
    expect(_isGitIgnored('lib/config.example.dart'), isFalse);
  });

  test('the README does not promise a CI-injected key', () async {
    final readme = await File('README.md').readAsString();

    for (final secret in secretEnvVars) {
      expect(readme, isNot(contains(secret)), reason: secret);
    }
    expect(
      readme,
      isNot(contains('Codemagic environment')),
    );
    expect(
      readme,
      contains('never baked into a build'),
    );
  });
}
