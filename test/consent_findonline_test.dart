import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('findOnline is blocked without consent and leaves results empty', () async {
    final provider = ScreenshotProvider();
    final s = Screenshot(
      id: 's1',
      fileName: 'web.png',
      filePath: '/gallery/web.png',
      timestamp: DateTime(2026, 1, 1),
      webResults: const [],
    );

    await provider.findOnline(s);

    expect(provider.error, contains('consent'));
    expect(s.webResults, equals(const <Map<String, String>>[]));
  });
}
