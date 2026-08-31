import 'package:cloud_firestore/cloud_firestore.dart';

class ObligationModel {
  ObligationModel({
    required this.id,
    required this.obligationId,
    required this.projectId,
    required this.projectName,
    required this.projectCode,
    required this.budgetId,
    required this.supplier,
    required this.category,
    required this.description,
    required this.amount,
    required this.fundingSource,
    required this.purchaseRequestNo,
    required this.purchaseOrderNo,
    required this.dateObligated,
    required this.expectedPaymentDate,
    required this.responsibleOfficer,
    required this.status,
    required this.remarks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String obligationId;
  final String projectId;
  final String projectName;
  final String projectCode;
  final String budgetId;
  final String supplier;
  final String category;
  final String description;
  final double amount;
  final String fundingSource;
  final String purchaseRequestNo;
  final String purchaseOrderNo;
  final DateTime dateObligated;
  final DateTime expectedPaymentDate;
  final String responsibleOfficer;
  final String status;
  final String remarks;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ObligationModel.fromFirestore(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    return ObligationModel(
      id: snapshot.id,
      obligationId: (data['obligationId'] ?? '').toString(),
      projectId: (data['projectId'] ?? '').toString(),
      projectName: (data['projectName'] ?? '').toString(),
      projectCode: (data['projectCode'] ?? '').toString(),
      budgetId: (data['budgetId'] ?? '').toString(),
      supplier: (data['supplier'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      amount: _toDouble(data['amount']),
      fundingSource: (data['fundingSource'] ?? '').toString(),
      purchaseRequestNo: (data['purchaseRequestNo'] ?? '').toString(),
      purchaseOrderNo: (data['purchaseOrderNo'] ?? '').toString(),
      dateObligated: _toDateTime(data['dateObligated']),
      expectedPaymentDate: _toDateTime(data['expectedPaymentDate']),
      responsibleOfficer: (data['responsibleOfficer'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      remarks: (data['remarks'] ?? '').toString(),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'obligationId': obligationId,
      'projectId': projectId,
      'projectName': projectName,
      'projectCode': projectCode,
      'budgetId': budgetId,
      'supplier': supplier,
      'category': category,
      'description': description,
      'amount': amount,
      'fundingSource': fundingSource,
      'purchaseRequestNo': purchaseRequestNo,
      'purchaseOrderNo': purchaseOrderNo,
      'dateObligated': Timestamp.fromDate(dateObligated),
      'expectedPaymentDate': Timestamp.fromDate(expectedPaymentDate),
      'responsibleOfficer': responsibleOfficer,
      'status': status,
      'remarks': remarks,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
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
