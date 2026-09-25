/// Outcome of validating a persisted `suggestedAction` map.
///
/// [action] is set only for a well-formed, allowlisted action; [reason] is then
/// null. For a rejected map [reason] is one of the fixed strings in
/// [LAMAction.rejections] — never the untrusted value itself.
class LAMActionValidation {
  const LAMActionValidation.valid(LAMAction validated)
      : action = validated,
        reason = null;

  const LAMActionValidation.rejected(String message)
      : action = null,
        reason = message;

  final LAMAction? action;
  final String? reason;

  bool get isValid => action != null;
}

/// Action data shared by response parsing and local execution.
class LAMAction {
  final String type;
  final Map<String, dynamic> data;

  LAMAction({
    required this.type,
    required this.data,
  });

  factory LAMAction.fromJson(Map<String, dynamic> json) {
    return LAMAction(
      type: json['type'] ?? 'none',
      data: json['data'] ?? {},
    );
  }

  /// The only action types Sift will ever execute. A persisted type outside
  /// this set is legacy or model-invented and is never run.
  static const Set<String> supportedTypes = {
    'add_calendar',
    'create_reminder',
    'create_shopping_list',
    'create_task',
    'none',
  };

  /// Fixed, sanitized failure messages. No rejected value is ever interpolated
  /// into one of these, so nothing untrusted can reach the UI through them.
  static const Map<String, String> rejections = {
    'unreadable-type':
        'This suggested action has an unreadable type and was not run.',
    'unsupported-type':
        'This suggested action type is no longer supported and was not run.',
    'unreadable-data':
        'This suggested action has unreadable details and was not run.',
    'unreadable-title':
        'This suggested action has an unreadable title and was not run.',
    'malformed-date':
        'This suggested action has an unreadable date and was not run.',
    'malformed-time':
        'This suggested action has an unreadable time and was not run.',
    'malformed-items':
        'This suggested action has an unreadable item list and was not run.',
  };

  static const int maxTextLength = 200;
  static const int maxItems = 200;
  static final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
  static final RegExp _timePattern =
      RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$');

  /// Validate a `suggestedAction` map that was persisted earlier, possibly by
  /// the old cloud analyzer and so possibly model-generated and arbitrary.
  ///
  /// Checks the type against [supportedTypes], then checks each field the type
  /// actually needs: required keys must be present with the right type, dates
  /// and times must parse, and item lists must hold only non-empty strings.
  /// The returned action carries only allowlisted keys with normalized values,
  /// so nothing arbitrary reaches a calendar, notification, or list write.
  static LAMActionValidation validate(Map<dynamic, dynamic>? suggested) {
    if (suggested == null || suggested.isEmpty) {
      return LAMActionValidation.rejected(rejections['unreadable-type']!);
    }
    final map = <String, dynamic>{};
    for (final entry in suggested.entries) {
      if (entry.key is! String) {
        return LAMActionValidation.rejected(rejections['unreadable-type']!);
      }
      map[entry.key as String] = entry.value;
    }

    final rawType = map['type'];
    if (rawType is! String) {
      return LAMActionValidation.rejected(rejections['unreadable-type']!);
    }
    final type = rawType.trim();
    if (type == 'none') {
      return LAMActionValidation.valid(LAMAction(type: 'none', data: const {}));
    }
    if (!supportedTypes.contains(type)) {
      return LAMActionValidation.rejected(rejections['unsupported-type']!);
    }

    final rawData = map['data'];
    if (rawData != null && rawData is! Map) {
      return LAMActionValidation.rejected(rejections['unreadable-data']!);
    }
    final data = <String, dynamic>{};
    if (rawData is Map) {
      for (final entry in rawData.entries) {
        if (entry.key is! String) {
          return LAMActionValidation.rejected(rejections['unreadable-data']!);
        }
        data[entry.key as String] = entry.value;
      }
    }

    final title = _cleanText(data['title']);
    if (data.containsKey('title') && title == null) {
      return LAMActionValidation.rejected(rejections['unreadable-title']!);
    }

    switch (type) {
      case 'add_calendar':
      case 'create_reminder':
        // A calendar event and a reminder are meaningless without a date, so
        // a missing one is rejected instead of silently becoming "today".
        if (!data.containsKey('date')) {
          return LAMActionValidation.rejected(rejections['malformed-date']!);
        }
        final date = _normalizeDate(data['date']);
        if (date == null) {
          return LAMActionValidation.rejected(rejections['malformed-date']!);
        }
        final allowed = <String, dynamic>{'date': date};
        if (title != null) allowed['title'] = title;
        if (type == 'add_calendar') {
          if (data.containsKey('time')) {
            final time = _normalizeTime(data['time']);
            if (time == null) {
              return LAMActionValidation.rejected(
                rejections['malformed-time']!,
              );
            }
            allowed['time'] = time;
          }
        }
        return LAMActionValidation.valid(LAMAction(type: type, data: allowed));

      case 'create_shopping_list':
        if (!data.containsKey('items') || data['items'] is! List) {
          return LAMActionValidation.rejected(rejections['malformed-items']!);
        }
        final rawItems = data['items'] as List;
        if (rawItems.length > maxItems) {
          return LAMActionValidation.rejected(rejections['malformed-items']!);
        }
        final items = <String>[];
        for (final raw in rawItems) {
          final item = _cleanText(raw);
          if (item == null) {
            return LAMActionValidation.rejected(rejections['malformed-items']!);
          }
          items.add(item);
        }
        final allowed = <String, dynamic>{'items': items};
        if (data.containsKey('list_name')) {
          final listName = _cleanText(data['list_name']);
          if (listName == null) {
            return LAMActionValidation.rejected(
              rejections['unreadable-title']!,
            );
          }
          allowed['list_name'] = listName;
        }
        return LAMActionValidation.valid(LAMAction(type: type, data: allowed));

      case 'create_task':
        final allowed = <String, dynamic>{};
        if (title != null) allowed['title'] = title;
        if (data.containsKey('date')) {
          final date = _normalizeDate(data['date']);
          if (date == null) {
            return LAMActionValidation.rejected(rejections['malformed-date']!);
          }
          allowed['date'] = date;
        }
        return LAMActionValidation.valid(LAMAction(type: type, data: allowed));

      default:
        return LAMActionValidation.rejected(rejections['unsupported-type']!);
    }
  }

  /// A trimmed, control-character-free, length-capped string, or null when the
  /// value is not a usable string. Never returns an empty string.
  static String? _cleanText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxTextLength) return null;
    for (final unit in trimmed.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) return null;
    }
    return trimmed;
  }

  /// Canonical `YYYY-MM-DD`, or null when the value is not a real calendar
  /// date. Impossible dates (e.g. 2026-02-30) are rejected rather than rolled
  /// over, so downstream date math cannot throw or silently shift the day.
  static String? _normalizeDate(Object? value) {
    if (value is! String) return null;
    final match = _datePattern.firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// Canonical `HH:mm`, or null when the value is not a 24-hour time.
  static String? _normalizeTime(Object? value) {
    if (value is! String) return null;
    final match = _timePattern.firstMatch(value.trim());
    if (match == null) return null;
    return '${match.group(1)}:${match.group(2)}';
  }

  String get displayName {
    switch (type) {
      case 'add_calendar':
        return 'Add to Calendar';
      case 'create_reminder':
        return 'Create Reminder';
      case 'create_shopping_list':
        return 'Create Shopping List';
      case 'create_task':
        return 'Create Task';
      case 'none':
        return 'No Action';
      default:
        return 'Unknown';
    }
  }
}
