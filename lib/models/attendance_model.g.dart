// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AttendanceModelAdapter extends TypeAdapter<AttendanceModel> {
  @override
  final int typeId = 4;

  @override
  AttendanceModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AttendanceModel(
      id: fields[0] as String,
      projectId: fields[1] as String,
      recorderId: fields[2] as String,
      attendanceDate: fields[3] as DateTime,
      records: (fields[4] as List).cast<AttendanceRecord>(),
      status: fields[5] as String,
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime,
      syncStatus: fields[8] as String,
      syncedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, AttendanceModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.projectId)
      ..writeByte(2)
      ..write(obj.recorderId)
      ..writeByte(3)
      ..write(obj.attendanceDate)
      ..writeByte(4)
      ..write(obj.records)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.syncStatus)
      ..writeByte(9)
      ..write(obj.syncedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AttendanceRecordAdapter extends TypeAdapter<AttendanceRecord> {
  @override
  final int typeId = 5;

  @override
  AttendanceRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AttendanceRecord(
      workerId: fields[0] as String,
      workerName: fields[1] as String,
      position: fields[2] as String,
      isPresent: fields[3] as bool,
      timeIn: fields[4] as DateTime?,
      timeOut: fields[5] as DateTime?,
      hoursWorked: fields[6] as double,
      overtimeHours: fields[7] as double,
      remarks: fields[8] as String?,
      amTimeIn: fields[9] as DateTime?,
      amTimeOut: fields[10] as DateTime?,
      pmTimeIn: fields[11] as DateTime?,
      pmTimeOut: fields[12] as DateTime?,
      workerType: (fields[13] as String?) ?? 'labor',
      rate: (fields[14] as double?) ?? 0.0,
      monPresent: (fields[15] as bool?) ?? false,
      tuePresent: (fields[16] as bool?) ?? false,
      wedPresent: (fields[17] as bool?) ?? false,
      thuPresent: (fields[18] as bool?) ?? false,
      friPresent: (fields[19] as bool?) ?? false,
      satPresent: (fields[20] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, AttendanceRecord obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.workerId)
      ..writeByte(1)
      ..write(obj.workerName)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.isPresent)
      ..writeByte(4)
      ..write(obj.timeIn)
      ..writeByte(5)
      ..write(obj.timeOut)
      ..writeByte(6)
      ..write(obj.hoursWorked)
      ..writeByte(7)
      ..write(obj.overtimeHours)
      ..writeByte(8)
      ..write(obj.remarks)
      ..writeByte(9)
      ..write(obj.amTimeIn)
      ..writeByte(10)
      ..write(obj.amTimeOut)
      ..writeByte(11)
      ..write(obj.pmTimeIn)
      ..writeByte(12)
      ..write(obj.pmTimeOut)
      ..writeByte(13)
      ..write(obj.workerType)
      ..writeByte(14)
      ..write(obj.rate)
      ..writeByte(15)
      ..write(obj.monPresent)
      ..writeByte(16)
      ..write(obj.tuePresent)
      ..writeByte(17)
      ..write(obj.wedPresent)
      ..writeByte(18)
      ..write(obj.thuPresent)
      ..writeByte(19)
      ..write(obj.friPresent)
      ..writeByte(20)
      ..write(obj.satPresent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
