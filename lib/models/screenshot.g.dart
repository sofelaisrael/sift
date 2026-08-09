// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screenshot.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScreenshotAdapter extends TypeAdapter<Screenshot> {
  @override
  final int typeId = 0;

  @override
  Screenshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Screenshot(
      id: fields[0] as String,
      fileName: fields[1] as String,
      filePath: fields[2] as String,
      timestamp: fields[3] as DateTime,
      ocrText: fields[4] as String?,
      lamType: fields[5] as String?,
      confidence: fields[6] as double?,
      summary: fields[7] as String?,
      actionType: fields[8] as String?,
      actionCompleted: fields[9] as bool,
      actionResult: fields[10] as String?,
      description: fields[11] as String?,
      objects: (fields[12] as List).cast<String>(),
      recognitions: (fields[13] as List).cast<String>(),
      webResults: (fields[14] as List? ?? const [])
          .map((dynamic e) => (e as Map).cast<String, String>())
          .toList(),
      isFavorite: fields[15] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Screenshot obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fileName)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.ocrText)
      ..writeByte(5)
      ..write(obj.lamType)
      ..writeByte(6)
      ..write(obj.confidence)
      ..writeByte(7)
      ..write(obj.summary)
      ..writeByte(8)
      ..write(obj.actionType)
      ..writeByte(9)
      ..write(obj.actionCompleted)
      ..writeByte(10)
      ..write(obj.actionResult)
      ..writeByte(11)
      ..write(obj.description)
      ..writeByte(12)
      ..write(obj.objects)
      ..writeByte(13)
      ..write(obj.recognitions)
      ..writeByte(14)
      ..write(obj.webResults)
      ..writeByte(15)
      ..write(obj.isFavorite);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenshotAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
