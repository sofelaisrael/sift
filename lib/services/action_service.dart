import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../services/lam_service.dart';

class ActionService {
  static const _uuid = Uuid();
  final DeviceCalendarPlugin _calendar = DeviceCalendarPlugin();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  ActionService() {
    tz_data.initializeTimeZones();
  }

  Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _notificationsInitialized = true;
  }

  /// Execute the action suggested by LAM
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

  Future<ActionResult> _addCalendarEvent(Map<String, dynamic> data, String screenshotId) async {
    // Check permissions
    final hasPermission = await _calendar.requestPermissions();
    if (hasPermission.isSuccess != true || hasPermission.data != true) {
      return ActionResult(success: false, message: 'Calendar permission denied');
    }

    // Get calendars
    final calendars = await _calendar.retrieveCalendars();
    if (calendars.data == null || calendars.data!.isEmpty) {
      return ActionResult(success: false, message: 'No calendars found');
    }

    final calendarId = calendars.data!.first.id;

    // Create event
    final startDate = _parseDateTime(data['date'], data['time']);
    final event = Event(
      calendarId,
      title: data['title'] ?? 'Screenshot Event',
      description: 'Created from screenshot',
      start: TZDateTime.from(startDate, tz.local),
      end: TZDateTime.from(startDate.add(const Duration(hours: 1)), tz.local),
    );

    final result = await _calendar.createOrUpdateEvent(event);
    
    if (result?.isSuccess == true) {
      // Save action to history
      await _saveAction('calendar', data, screenshotId);
      return ActionResult(
        success: true,
        message: 'Added to calendar: ${data['title']}',
      );
    } else {
      return ActionResult(success: false, message: 'Failed to create event');
    }
  }

  Future<ActionResult> _createReminder(Map<String, dynamic> data, String screenshotId) async {
    await _ensureNotificationsInitialized();
    final title = data['title'] ?? 'Reminder';
    final date = _parseDateTime(data['date'], null);
    
    // Schedule reminder
    await _notifications.zonedSchedule(
      _uuid.v4().hashCode,
      title,
      'Reminder from screenshot',
      TZDateTime.from(date, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
    
    // Save to local storage
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
    
    // Save to local storage
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
