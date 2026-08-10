import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('runSuggestedAction is blocked without consent', () async {
    final provider = ScreenshotProvider();
    final s = Screenshot(
      id: 's1',
      fileName: 'reminder.png',
      filePath: '/gallery/reminder.png',
      timestamp: DateTime(2026, 1, 1),
      suggestedAction: {'type': 'create_reminder', 'data': <String, dynamic>{}},
    );

    final result = await provider.runSuggestedAction(s);

    expect(result, isNull);
    expect(provider.error, contains('consent'));
  });
}
