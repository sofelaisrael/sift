class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final List<String> sourceIds;
  final List<Map<String, String>> relatedLinks;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.sourceIds = const [],
    this.relatedLinks = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'sourceIds': sourceIds,
        'relatedLinks': relatedLinks
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        role: json['role'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        sourceIds: _stringList(json['sourceIds']),
        relatedLinks: _stringMapList(json['relatedLinks']),
      );

  bool get isUser => role == 'user';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  static List<Map<String, String>> _stringMapList(dynamic value) {
    if (value is List) {
      return value.map((e) {
        if (e is Map) {
          return e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        }
        return const <String, String>{};
      }).toList();
    }
    return const [];
  }
}
