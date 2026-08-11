import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/models/chat_message.dart';

void main() {
  test('ChatMessage round-trips through toJson/fromJson with links preserved',
      () {
    final message = ChatMessage(
      id: 'm1',
      role: 'assistant',
      content: 'Here are some related links.',
      timestamp: DateTime(2026, 1, 1, 12, 30, 15),
      sourceIds: const ['s1', 's2'],
      relatedLinks: const [
        {'title': 'Example one', 'url': 'https://example.com/1'},
        {'title': 'Example two', 'url': 'https://example.com/2'},
      ],
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.id, message.id);
    expect(restored.role, message.role);
    expect(restored.content, message.content);
    expect(restored.timestamp, message.timestamp);
    expect(restored.sourceIds, message.sourceIds);
    expect(restored.relatedLinks, message.relatedLinks);
  });
}
