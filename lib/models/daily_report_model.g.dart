// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_report_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DailyReportModelAdapter extends TypeAdapter<DailyReportModel> {
  @override
  final int typeId = 2;

  @override
  DailyReportModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyReportModel(
      id: fields[0] as String,
      projectId: fields[1] as String,
      reporterId: fields[2] as String,
      reportDate: fields[3] as DateTime,
      weatherCondition: fields[4] as String,
      temperatureC: fields[5] as double,
      workAccomplishments: (fields[6] as List).cast<WorkAccomplishment>(),
      issues: (fields[7] as List).cast<String>(),
      attachmentUrls: (fields[8] as List).cast<String>(),
      status: fields[9] as String,
      remarks: fields[10] as String?,
      createdAt: fields[11] as DateTime,
      updatedAt: fields[12] as DateTime,
      syncStatus: fields[13] as String,
      syncedAt: fields[14] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DailyReportModel obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.projectId)
      ..writeByte(2)
      ..write(obj.reporterId)
      ..writeByte(3)
      ..write(obj.reportDate)
      ..writeByte(4)
      ..write(obj.weatherCondition)
      ..writeByte(5)
      ..write(obj.temperatureC)
      ..writeByte(6)
      ..write(obj.workAccomplishments)
      ..writeByte(7)
      ..write(obj.issues)
      ..writeByte(8)
      ..write(obj.attachmentUrls)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.remarks)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.updatedAt)
      ..writeByte(13)
      ..write(obj.syncStatus)
      ..writeByte(14)
      ..write(obj.syncedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyReportModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class WorkAccomplishmentAdapter extends TypeAdapter<WorkAccomplishment> {
  @override
  final int typeId = 3;

  @override
  WorkAccomplishment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkAccomplishment(
      id: fields[0] as String,
      wbsCode: fields[1] as String,
      description: fields[2] as String,
      unit: fields[3] as String,
      quantityAccomplished: fields[4] as double,
      percentageComplete: fields[5] as double,
      remarks: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WorkAccomplishment obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.wbsCode)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.unit)
      ..writeByte(4)
      ..write(obj.quantityAccomplished)
      ..writeByte(5)
      ..write(obj.percentageComplete)
      ..writeByte(6)
      ..write(obj.remarks);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkAccomplishmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
