import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'payroll_model.g.dart';

DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.replaceAll(',', '').replaceAll('₱', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }
  return 0.0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final cleaned = value.replaceAll(',', '').trim(); 
    return int.tryParse(cleaned) ?? 0;
  }
  return 0;
}

Map<String, double> _parseDeductionBreakdown(dynamic value) {
  if (value == null) {
    return <String, double>{};
  }
  if (value is Map) {
    final result = <String, double>{};
    value.forEach((key, v) {
      result[key.toString()] = _toDouble(v);
    });
    return result;
  }
  return <String, double>{};
}

@HiveType(typeId: 6)
class PayrollModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String projectId;

  @HiveField(2)
  String generatedBy;

  @HiveField(3)
  DateTime payrollPeriodStart;

  @HiveField(4)
  DateTime payrollPeriodEnd;

  @HiveField(5)
  List<PayrollItem> items;

  @HiveField(6)
  double totalAmount;

  @HiveField(7)
  String status;

  @HiveField(8)
  String? validatedBy;

  @HiveField(9)
  DateTime? validatedAt;

  @HiveField(10)
  String? paidBy;

  @HiveField(11)
  DateTime? paidAt;

  @HiveField(12)
  String? remarks;

  @HiveField(13)
  DateTime createdAt;

  @HiveField(14)
  DateTime updatedAt;

  String? validationStatus;

  Map<String, dynamic>? validationResults;

  PayrollModel({
    required this.id,
    required this.projectId,
    required this.generatedBy,
    required this.payrollPeriodStart,
    required this.payrollPeriodEnd,
    required this.items,
    required this.totalAmount,
    this.status = 'generated',
    this.validatedBy,
    this.validatedAt,
    this.paidBy,
    this.paidAt,
    this.remarks,
    required this.createdAt,
    required this.updatedAt,
    this.validationStatus,
    this.validationResults,
  });

  bool get isGenerated => status == 'generated';
  bool get isValidated => status == 'validated';
  bool get isPaid => status == 'paid';
  bool get isReturned => status == 'returned';

  int get totalWorkers => items.length;

  factory PayrollModel.fromJson(Map<String, dynamic> json) {
    return PayrollModel(
      id: json['id'] ?? '',
      projectId: json['projectId'] ?? '',
      generatedBy: json['generatedBy'] ?? '',
      payrollPeriodStart: _parseDateTime(json['payrollPeriodStart']),
      payrollPeriodEnd: _parseDateTime(json['payrollPeriodEnd']),
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => PayrollItem.fromJson(e))
              .toList() ??
          [],
      totalAmount: _toDouble(json['totalAmount']),
      status: json['status'] ?? 'generated',
      validatedBy: json['validatedBy'],
      validatedAt: json['validatedAt'] != null ? _parseDateTime(json['validatedAt']) : null,
      paidBy: json['paidBy'],
      paidAt: json['paidAt'] != null ? _parseDateTime(json['paidAt']) : null,
      remarks: json['remarks'],
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      validationStatus: json['validationStatus'],
      validationResults: json['validationResults'] != null
          ? Map<String, dynamic>.from(json['validationResults'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'generatedBy': generatedBy,
      'payrollPeriodStart': payrollPeriodStart.toIso8601String(),
      'payrollPeriodEnd': payrollPeriodEnd.toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
      'totalAmount': totalAmount,
      'status': status,
      'validatedBy': validatedBy,
      'validatedAt': validatedAt?.toIso8601String(),
      'paidBy': paidBy,
      'paidAt': paidAt?.toIso8601String(),
      'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'validationStatus': validationStatus,
      'validationResults': validationResults,
    };
  }
}

@HiveType(typeId: 7)
class PayrollItem extends HiveObject {
  @HiveField(0)
  String workerId;

  @HiveField(1)
  String workerName;

  @HiveField(2)
  String position;

  @HiveField(3)
  double dailyRate;

  @HiveField(4)
  int daysWorked;

  @HiveField(5)
  double regularHours;

  @HiveField(6)
  double overtimeHours;

  @HiveField(7)
  double grossPay;

  @HiveField(8)
  double deductions;

  @HiveField(9)
  double netPay;

  @HiveField(10)
  Map<String, double> deductionBreakdown;

  PayrollItem({
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.dailyRate,
    required this.daysWorked,
    required this.regularHours,
    required this.overtimeHours,
    required this.grossPay,
    required this.deductions,
    required this.netPay,
    required this.deductionBreakdown,
  });

  double get totalHours => regularHours + overtimeHours;

  factory PayrollItem.fromJson(Map<String, dynamic> json) {
    return PayrollItem(
      workerId: json['workerId'] ?? '',
      workerName: json['workerName'] ?? '',
      position: json['position'] ?? '',
      dailyRate: _toDouble(json['dailyRate']),
      daysWorked: _toInt(json['daysWorked']),
      regularHours: _toDouble(json['regularHours']),
      overtimeHours: _toDouble(json['overtimeHours']),
      grossPay: _toDouble(json['grossPay']),
      deductions: _toDouble(json['deductions']),
      netPay: _toDouble(json['netPay']),
      deductionBreakdown: _parseDeductionBreakdown(json['deductionBreakdown']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workerId': workerId,
      'workerName': workerName,
      'position': position,
      'dailyRate': dailyRate,
      'daysWorked': daysWorked,
      'regularHours': regularHours,
      'overtimeHours': overtimeHours,
      'grossPay': grossPay,
      'deductions': deductions,
      'netPay': netPay,
      'deductionBreakdown': deductionBreakdown,
    };
  }
}
