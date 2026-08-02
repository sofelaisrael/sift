import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../services/lam_service.dart';

class ActionService {
  static const _uuid = Uuid();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  ActionService() {
    tz_data.initializeTimeZones();
  }

  Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _notificationsInitialized = true;
  }

  Future<ActionResult> executeAction(LAMAction action, String screenshotId) async {
    try {
      switch (action.type) {
        case 'add_calendar':
          return await _addCalendarEvent(action.data, screenshotId);
        case 'create_reminder':
          return await _createReminder(action.data, screenshotId);
        case 'create_shopping_list':
          return await _createShoppingList(action.data, screenshotId);
        case 'create_task':
          return await _createTask(action.data, screenshotId);
        default:
          return ActionResult(success: false, message: 'Unknown action');
      }
    } catch (e) {
      return ActionResult(success: false, message: 'Action failed: $e');
    }
  }

  /// Show an immediate local notification (used by the screenshot watcher)
  Future<void> notify(String title, String body) async {
    try {
      await _ensureNotificationsInitialized();
      await _notifications.show(
        id: _uuid.v4().hashCode,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'sift',
            'Sift',
            channelDescription: 'Screenshot analysis alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  Future<ActionResult> _addCalendarEvent(Map<String, dynamic> data, String screenshotId) async {
    final startDate = _parseDateTime(data['date'], data['time']);
    final event = cal.Event(
      title: data['title'] ?? 'Screenshot Event',
      description: 'Created from screenshot',
      startDate: startDate,
      endDate: startDate.add(const Duration(hours: 1)),
    );

    cal.Add2Calendar.addEvent2Cal(event);
    await _saveAction('calendar', data, screenshotId);
    return ActionResult(
      success: true,
      message: 'Added to calendar: ${data['title']}',
    );
  }

  Future<ActionResult> _createReminder(Map<String, dynamic> data, String screenshotId) async {
    await _ensureNotificationsInitialized();
    final title = data['title'] ?? 'Reminder';
    final date = _parseDateTime(data['date'], null);

    await _notifications.zonedSchedule(
      id: _uuid.v4().hashCode,
      title: title,
      body: 'Reminder from screenshot',
      scheduledDate: tz.TZDateTime.from(date, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    await _saveAction('reminder', data, screenshotId);
    return ActionResult(
      success: true,
      message: 'Reminder set: $title',
    );
  }

  Future<ActionResult> _createShoppingList(Map<String, dynamic> data, String screenshotId) async {
    final items = List<String>.from(data['items'] ?? []);
    final listName = data['list_name'] ?? 'Shopping List';

    final box = Hive.box('actions');
    await box.put(_uuid.v4(), {
      'type': 'shopping_list',
      'name': listName,
      'items': items,
      'created_at': DateTime.now().toIso8601String(),
      'screenshot_id': screenshotId,
    });

    return ActionResult(
      success: true,
      message: 'Shopping list created: $listName (${items.length} items)',
    );
  }

  Future<ActionResult> _createTask(Map<String, dynamic> data, String screenshotId) async {
    final title = data['title'] ?? 'Task';

    final box = Hive.box('actions');
    await box.put(_uuid.v4(), {
      'type': 'task',
      'title': title,
      'due_date': data['date'],
      'created_at': DateTime.now().toIso8601String(),
      'screenshot_id': screenshotId,
    });

    return ActionResult(
      success: true,
      message: 'Task created: $title',
    );
  }

  DateTime _parseDateTime(String? date, String? time) {
    final now = DateTime.now();
    final dateStr = date ?? now.toIso8601String().split('T')[0];
    final timeStr = time ?? '12:00';

    return DateTime.parse('${dateStr}T$timeStr:00');
  }

  Future<void> _saveAction(String type, Map<String, dynamic> data, String screenshotId) async {
    final box = Hive.box('actions');
    await box.put(_uuid.v4(), {
      'type': type,
      'data': data,
      'screenshot_id': screenshotId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class ActionResult {
  final bool success;
  final String message;

  ActionResult({
    required this.success,
    required this.message,
  });
}
