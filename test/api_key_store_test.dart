import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/services/api_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecretStore secure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = InMemorySecretStore();
    ApiKeyStore.instance = secure;
  });

  test('writes the key to the secret store and drops the plaintext copy',
      () async {
    SharedPreferences.setMockInitialValues({'key_youtube': 'legacy-key'});

    await ApiKeyStore.write('key_youtube', '  new-key  ');

    expect(await secure.read('key_youtube'), 'new-key');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_youtube'), isNull);
  });

  test('migrates an existing plaintext key on first read', () async {
    SharedPreferences.setMockInitialValues({'key_youtube': 'old-key'});

    expect(await ApiKeyStore.read('key_youtube'), 'old-key');
    expect(await secure.read('key_youtube'), 'old-key');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_youtube'), isNull);
  });

  test('an empty write deletes the saved key', () async {
    await ApiKeyStore.write('key_youtube', 'saved');
    await ApiKeyStore.write('key_youtube', '   ');

    expect(await secure.read('key_youtube'), isNull);
    expect(await ApiKeyStore.read('key_youtube'), isNull);
  });

  test('clear removes every saved key', () async {
    await ApiKeyStore.write('key_youtube', 'youtube');
    await ApiKeyStore.write('key_Google Gemini', 'gemini');

    await ApiKeyStore.clear();

    expect(await ApiKeyStore.read('key_youtube'), isNull);
    expect(await ApiKeyStore.read('key_Google Gemini'), isNull);
  });
}
