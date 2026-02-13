// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProjectModelAdapter extends TypeAdapter<ProjectModel> {
  @override
  final int typeId = 1;

  @override
  ProjectModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProjectModel(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String,
      location: fields[3] as String,
      contractorName: fields[4] as String,
      contractAmount: fields[5] as double,
      startDate: fields[6] as DateTime,
      endDate: fields[7] as DateTime,
      status: fields[8] as String,
      progressPercentage: fields[9] as double,
      projectManager: fields[10] as String,
      assignedUsers: (fields[11] as List).cast<String>(),
      wbsStructure: (fields[12] as Map?)?.cast<String, dynamic>(),
      createdAt: fields[13] as DateTime,
      updatedAt: fields[14] as DateTime,
      isActive: fields[15] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ProjectModel obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.location)
      ..writeByte(4)
      ..write(obj.contractorName)
      ..writeByte(5)
      ..write(obj.contractAmount)
      ..writeByte(6)
      ..write(obj.startDate)
      ..writeByte(7)
      ..write(obj.endDate)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.progressPercentage)
      ..writeByte(10)
      ..write(obj.projectManager)
      ..writeByte(11)
      ..write(obj.assignedUsers)
      ..writeByte(12)
      ..write(obj.wbsStructure)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.updatedAt)
      ..writeByte(15)
      ..write(obj.isActive);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
