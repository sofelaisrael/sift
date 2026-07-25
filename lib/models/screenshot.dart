import 'package:hive/hive.dart';

part 'screenshot.g.dart';

@HiveType(typeId: 0)
class Screenshot extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fileName;

  @HiveField(2)
  final String filePath;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  String? ocrText;

  @HiveField(5)
  String? lamType;

  @HiveField(6)
  double? confidence;

  @HiveField(7)
  String? summary;

  @HiveField(8)
  String? actionType;

  @HiveField(9)
  bool actionCompleted;

  @HiveField(10)
  String? actionResult;

  Screenshot({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.timestamp,
    this.ocrText,
    this.lamType,
    this.confidence,
    this.summary,
    this.actionType,
    this.actionCompleted = false,
    this.actionResult,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'filePath': filePath,
    'timestamp': timestamp.toIso8601String(),
    'ocrText': ocrText,
    'lamType': lamType,
    'confidence': confidence,
    'summary': summary,
    'actionType': actionType,
    'actionCompleted': actionCompleted,
    'actionResult': actionResult,
  };

  factory Screenshot.fromJson(Map<String, dynamic> json) => Screenshot(
    id: json['id'],
    fileName: json['fileName'],
    filePath: json['filePath'],
    timestamp: DateTime.parse(json['timestamp']),
    ocrText: json['ocrText'],
    lamType: json['lamType'],
    confidence: json['confidence']?.toDouble(),
    summary: json['summary'],
    actionType: json['actionType'],
    actionCompleted: json['actionCompleted'] ?? false,
    actionResult: json['actionResult'],
  );

  String get typeEmoji {
    switch (lamType) {
      case 'flight': return '✈️';
      case 'recipe': return '🍳';
      case 'deadline': return '⏰';
      case 'product': return '🛒';
      case 'meeting': return '📅';
      case 'document': return '📄';
      default: return '📌';
    }
  }
}
