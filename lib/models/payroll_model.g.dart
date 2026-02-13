// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payroll_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PayrollModelAdapter extends TypeAdapter<PayrollModel> {
  @override
  final int typeId = 6;

  @override
  PayrollModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PayrollModel(
      id: fields[0] as String,
      projectId: fields[1] as String,
      generatedBy: fields[2] as String,
      payrollPeriodStart: fields[3] as DateTime,
      payrollPeriodEnd: fields[4] as DateTime,
      items: (fields[5] as List).cast<PayrollItem>(),
      totalAmount: fields[6] as double,
      status: fields[7] as String,
      validatedBy: fields[8] as String?,
      validatedAt: fields[9] as DateTime?,
      paidBy: fields[10] as String?,
      paidAt: fields[11] as DateTime?,
      remarks: fields[12] as String?,
      createdAt: fields[13] as DateTime,
      updatedAt: fields[14] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PayrollModel obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.projectId)
      ..writeByte(2)
      ..write(obj.generatedBy)
      ..writeByte(3)
      ..write(obj.payrollPeriodStart)
      ..writeByte(4)
      ..write(obj.payrollPeriodEnd)
      ..writeByte(5)
      ..write(obj.items)
      ..writeByte(6)
      ..write(obj.totalAmount)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.validatedBy)
      ..writeByte(9)
      ..write(obj.validatedAt)
      ..writeByte(10)
      ..write(obj.paidBy)
      ..writeByte(11)
      ..write(obj.paidAt)
      ..writeByte(12)
      ..write(obj.remarks)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayrollModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PayrollItemAdapter extends TypeAdapter<PayrollItem> {
  @override
  final int typeId = 7;

  @override
  PayrollItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PayrollItem(
      workerId: fields[0] as String,
      workerName: fields[1] as String,
      position: fields[2] as String,
      dailyRate: fields[3] as double,
      daysWorked: fields[4] as int,
      regularHours: fields[5] as double,
      overtimeHours: fields[6] as double,
      grossPay: fields[7] as double,
      deductions: fields[8] as double,
      netPay: fields[9] as double,
      deductionBreakdown: (fields[10] as Map).cast<String, double>(),
    );
  }

  @override
  void write(BinaryWriter writer, PayrollItem obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.workerId)
      ..writeByte(1)
      ..write(obj.workerName)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.dailyRate)
      ..writeByte(4)
      ..write(obj.daysWorked)
      ..writeByte(5)
      ..write(obj.regularHours)
      ..writeByte(6)
      ..write(obj.overtimeHours)
      ..writeByte(7)
      ..write(obj.grossPay)
      ..writeByte(8)
      ..write(obj.deductions)
      ..writeByte(9)
      ..write(obj.netPay)
      ..writeByte(10)
      ..write(obj.deductionBreakdown);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayrollItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
