import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'localOnly': true,
      'privacy_consent': false,
    });
  });

  test('local action path is not blocked by cloud consent settings', () async {
    final provider = ScreenshotProvider();
    // `none` reaches the local path without invoking a platform action.
    final s = Screenshot(
      id: 's1',
      fileName: 'reminder.png',
      filePath: '/gallery/reminder.png',
      timestamp: DateTime(2026, 1, 1),
      suggestedAction: {'type': 'none', 'data': <String, dynamic>{}},
    );

    final result = await provider.runSuggestedAction(s);

    expect(result, isNull);
    expect(provider.error, isNull);
  });
}
