class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final List<String> sourceIds;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.sourceIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'sourceIds': sourceIds,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        role: json['role'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        sourceIds: _stringList(json['sourceIds']),
      );

  bool get isUser => role == 'user';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}
