import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screensort_lam/models/screenshot.dart';
import 'package:screensort_lam/providers/screenshot_provider.dart';
import 'package:screensort_lam/services/action_model.dart';
import 'package:screensort_lam/services/action_service.dart';

/// Records persisted before the on-device migration can hold `suggestedAction`
/// maps the old cloud analyzer generated. They are untrusted input: every one
/// must be validated before any calendar, reminder, shopping-list, or task
/// write happens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('legacy_action_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('screenshots');
    await Hive.openBox('actions');
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Screenshot recordWith(Map<String, dynamic> suggestedAction) {
    return Screenshot(
      id: 'legacy',
      fileName: 'legacy.png',
      filePath: '/gallery/legacy.png',
      timestamp: DateTime(2026, 1, 1),
      summary: 'Legacy record',
      suggestedAction: suggestedAction,
    );
  }

  /// Runs the local action path with no cloud consent in effect and returns
  /// what happened. The `actions` box is the only place the list/task actions
  /// write, so an empty box proves no platform action ran.
  Future<({ActionResult? result, Screenshot screenshot, int writes})>
      runLegacy(Map<String, dynamic> suggestedAction) async {
    final provider = ScreenshotProvider();
    final screenshot = recordWith(suggestedAction);
    final result = await provider.runSuggestedAction(screenshot);
    final writes = Hive.box('actions').length;
    return (result: result, screenshot: screenshot, writes: writes);
  }

  test('an unsupported legacy action type runs nothing and fails safely',
      () async {
    final outcome = await runLegacy({
      'type': 'run_shell_command',
      'data': {'cmd': 'rm -rf /'},
    });

    expect(outcome.result, isNull);
    expect(outcome.writes, 0);
    expect(outcome.screenshot.actionCompleted, isFalse);
    expect(
      outcome.screenshot.actionResult,
      'This suggested action type is no longer supported and was not run.',
    );
    // The untrusted payload is never echoed into anything the UI can show.
    expect(outcome.screenshot.actionResult, isNot(contains('rm -rf')));
    expect(
      outcome.screenshot.actionResult,
      isNot(contains('run_shell_command')),
    );
  });

  test('a malformed legacy date runs nothing and fails safely', () async {
    final outcome = await runLegacy({
      'type': 'create_task',
      'data': {'title': 'Pay rent', 'date': 'next tuesday-ish'},
    });

    expect(outcome.result, isNull);
    expect(outcome.writes, 0);
    expect(outcome.screenshot.actionCompleted, isFalse);
    expect(
      outcome.screenshot.actionResult,
      'This suggested action has an unreadable date and was not run.',
    );
    expect(outcome.screenshot.actionResult, isNot(contains('tuesday')));
  });

  test('a legacy item list with non-string entries runs nothing', () async {
    final outcome = await runLegacy({
      'type': 'create_shopping_list',
      'data': {
        'list_name': 'Groceries',
        'items': ['milk', {'nested': 'map'}, 7],
      },
    });

    expect(outcome.result, isNull);
    expect(outcome.writes, 0);
    expect(
      outcome.screenshot.actionResult,
      'This suggested action has an unreadable item list and was not run.',
    );
  });

  test('a non-map type payload runs nothing and fails safely', () async {
    final outcome = await runLegacy({
      'type': 42,
      'data': <String, dynamic>{},
    });

    expect(outcome.result, isNull);
    expect(outcome.writes, 0);
    expect(
      outcome.screenshot.actionResult,
      'This suggested action has an unreadable type and was not run.',
    );
  });

  test('a well-formed legacy action survives validation with clean data', () {
    final validation = LAMAction.validate({
      'type': 'add_calendar',
      'data': {
        'title': '  Flight to Lisbon  ',
        'date': '2026-3-5',
        'time': '15:04',
        'injected': 'dropped',
      },
    });

    expect(validation.isValid, isTrue);
    expect(validation.reason, isNull);
    expect(validation.action!.type, 'add_calendar');
    expect(validation.action!.data, {
      'date': '2026-03-05',
      'title': 'Flight to Lisbon',
      'time': '15:04',
    });
  });

  test('validate rejects the malformed shapes it claims to', () {
    const cases = <String, Map<String, dynamic>>{
      'unsupported-type': {'type': 'email_everyone'},
      'unreadable-type': {'type': null},
      'unreadable-data': {'type': 'create_task', 'data': 'not-a-map'},
      'malformed-date': {
        'type': 'create_reminder',
        'data': {'date': '2026-02-30T10:00:00Z'},
      },
      'malformed-time': {
        'type': 'add_calendar',
        'data': {'date': '2026-02-28', 'time': '25:99'},
      },
      'unreadable-title': {
        'type': 'create_task',
        'data': {'title': 'two\nlines'},
      },
      'malformed-items': {
        'type': 'create_shopping_list',
        'data': {'items': 'milk'},
      },
    };

    for (final entry in cases.entries) {
      final validation = LAMAction.validate(entry.value);
      expect(validation.isValid, isFalse, reason: entry.key);
      expect(validation.reason, LAMAction.rejections[entry.key]);
    }
  });

  test('validate treats a none action as no action at all', () {
    final validation = LAMAction.validate({
      'type': 'none',
      'data': <String, dynamic>{'date': 'garbage'},
    });

    expect(validation.isValid, isTrue);
    expect(validation.action!.type, 'none');
    expect(validation.action!.data, isEmpty);
  });

  test('the local action path still needs no cloud consent', () async {
    // No privacy_consent, and local-only is the default: a valid local action
    // must not be blocked by the cloud consent gate.
    final provider = ScreenshotProvider();
    final screenshot = recordWith({
      'type': 'create_shopping_list',
      'data': {'list_name': 'Groceries', 'items': ['milk', 'eggs']},
    });

    final result = await provider.runSuggestedAction(screenshot);

    // The list write is the platform action; it happens, proving no consent
    // gate blocked the local path.
    expect(Hive.box('actions').length, 1);
    expect(screenshot.actionCompleted, isTrue);
    expect(result, isNotNull);
    expect(provider.error, isNull);
  });

  test(
    'the action service never echoes a raw error into the UI message',
    () async {
      const path = 'lib/services/action_service.dart';
      final source = await File(path).readAsString();

      expect(source, isNot(contains("message: 'Action failed: \$e'")));
      expect(source, contains('debugPrint(\'Action failed: \$e\')'));
    },
  );
}
