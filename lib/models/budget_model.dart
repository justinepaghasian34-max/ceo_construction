import 'package:cloud_firestore/cloud_firestore.dart';

class BudgetModel {
  BudgetModel({
    required this.id,
    required this.budgetId,
    required this.projectId,
    required this.projectName,
    required this.fiscalYear,
    required this.budgetCategory,
    required this.allocatedAmount,
    required this.usedAmount,
    required this.remainingAmount,
    required this.dateCreated,
    required this.status,
    required this.remarks,
    required this.updatedAt,
  });

  final String id;
  final String budgetId;
  final String projectId;
  final String projectName;
  final String fiscalYear;
  final String budgetCategory;
  final double allocatedAmount;
  final double usedAmount;
  final double remainingAmount;
  final DateTime dateCreated;
  final String status;
  final String remarks;
  final DateTime updatedAt;

  double get remaining => allocatedAmount - usedAmount;

  factory BudgetModel.fromFirestore(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    final allocated = _toDouble(data['allocatedAmount']);
    final used = _toDouble(data['usedAmount']);
    final remaining = _toDouble(data['remainingAmount']);

    return BudgetModel(
      id: snapshot.id,
      budgetId: (data['budgetId'] ?? '').toString(),
      projectId: (data['projectId'] ?? '').toString(),
      projectName: (data['projectName'] ?? '').toString(),
      fiscalYear: (data['fiscalYear'] ?? '').toString(),
      budgetCategory: (data['budgetCategory'] ?? '').toString(),
      allocatedAmount: allocated,
      usedAmount: used,
      remainingAmount: remaining > 0 ? remaining : (allocated - used),
      dateCreated: _toDateTime(data['dateCreated']),
      status: (data['status'] ?? 'Active').toString(),
      remarks: (data['remarks'] ?? '').toString(),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    final computedRemaining = allocatedAmount - usedAmount;
    return {
      'budgetId': budgetId,
      'projectId': projectId,
      'projectName': projectName,
      'fiscalYear': fiscalYear,
      'budgetCategory': budgetCategory,
      'allocatedAmount': allocatedAmount,
      'usedAmount': usedAmount,
      'remainingAmount': computedRemaining,
      'dateCreated': Timestamp.fromDate(dateCreated),
      'status': status,
      'remarks': remarks,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  BudgetModel copyWith({
    String? id,
    String? budgetId,
    String? projectId,
    String? projectName,
    String? fiscalYear,
    String? budgetCategory,
    double? allocatedAmount,
    double? usedAmount,
    double? remainingAmount,
    DateTime? dateCreated,
    String? status,
    String? remarks,
    DateTime? updatedAt,
  }) {
    return BudgetModel(
      id: id ?? this.id,
      budgetId: budgetId ?? this.budgetId,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      budgetCategory: budgetCategory ?? this.budgetCategory,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      usedAmount: usedAmount ?? this.usedAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      dateCreated: dateCreated ?? this.dateCreated,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(',', '').replaceAll('₱', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
