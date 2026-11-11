import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where provider and YouTube API keys live.
///
/// Keys are encrypted at rest with the platform keystore. An existing key in
/// SharedPreferences is moved on first read, so an upgrade does not ask the
/// user to paste it again.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// Test double. Production always uses [SecureSecretStore].
@visibleForTesting
class InMemorySecretStore implements SecretStore {
  InMemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }
}

class ApiKeyStore {
  ApiKeyStore._();

  /// Swapped by tests; production keeps the keystore-backed default.
  static SecretStore instance = const SecureSecretStore();

  static Future<String?> read(String name) async {
    try {
      final secure = await instance.read(name);
      if (secure != null && secure.trim().isNotEmpty) return secure;
    } on MissingPluginException {
      // No platform implementation (unit tests, unsupported platform). Read
      // the old location rather than pretending the key was never saved.
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(name);
    }

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(name);
    if (legacy == null) return null;

    // One-way migration: the encrypted copy is written before the plaintext
    // one is removed.
    if (legacy.trim().isNotEmpty) {
      await instance.write(name, legacy.trim());
    }
    await prefs.remove(name);
    return legacy.trim();
  }

  static Future<void> write(String name, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await instance.delete(name);
    } else {
      await instance.write(name, trimmed);
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(name)) await prefs.remove(name);
  }

  static Future<void> clear() async {
    try {
      await instance.clear();
    } on MissingPluginException {
      // Nothing to clear when the platform store is absent.
    }
  }
}
