import 'package:flutter_test/flutter_test.dart';
import 'package:screensort_lam/models/screenshot.dart';

void main() {
  test('Screenshot toJson/fromJson round-trips every field', () {
    final original = Screenshot(
      id: 'shot-1',
      fileName: 'receipt.png',
      filePath: '/gallery/receipt.png',
      timestamp: DateTime(2026, 1, 12, 9, 30),
      ocrText: 'Total: \$540.00',
      lamType: 'product',
      confidence: 0.92,
      summary: 'A receipt for groceries',
      description: 'Itemized grocery receipt',
      actionType: 'create_shopping_list',
      actionCompleted: true,
      actionResult: 'Created list',
      objects: ['receipt', 'groceries'],
      recognitions: ['Whole Foods'],
      webResults: const [
        {'title': 'Store', 'url': 'https://a.com/x'},
      ],
      isFavorite: true,
      tags: ['shopping', 'urgent'],
      suggestedAction: {
        'type': 'add_calendar',
        'data': {'date': '2026-01-12'},
      },
      extractedData: {'price': 540, 'tags': ['x']},
    );

    final roundTripped = Screenshot.fromJson(original.toJson());

    expect(roundTripped.id, original.id);
    expect(roundTripped.fileName, original.fileName);
    expect(roundTripped.filePath, original.filePath);
    expect(roundTripped.timestamp, original.timestamp);
    expect(roundTripped.ocrText, original.ocrText);
    expect(roundTripped.lamType, original.lamType);
    expect(roundTripped.confidence, original.confidence);
    expect(roundTripped.summary, original.summary);
    expect(roundTripped.description, original.description);
    expect(roundTripped.actionType, original.actionType);
    expect(roundTripped.actionCompleted, original.actionCompleted);
    expect(roundTripped.actionResult, original.actionResult);
    expect(roundTripped.objects, original.objects);
    expect(roundTripped.recognitions, original.recognitions);
    expect(roundTripped.webResults, original.webResults);
    expect(roundTripped.isFavorite, original.isFavorite);
    expect(roundTripped.tags, original.tags);
    expect(roundTripped.suggestedAction, original.suggestedAction);
    expect(roundTripped.extractedData, original.extractedData);

    expect(roundTripped.toJson(), equals(original.toJson()));
  });
}
