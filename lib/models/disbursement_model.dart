import 'package:cloud_firestore/cloud_firestore.dart';

class DisbursementModel {
  DisbursementModel({
    required this.id,
    required this.disbursementId,
    required this.obligationId,
    required this.projectId,
    required this.projectName,
    required this.budgetId,
    required this.supplier,
    required this.amount,
    required this.paymentMethod,
    required this.bankName,
    required this.referenceNumber,
    required this.paymentDate,
    required this.approvedBy,
    required this.status,
    required this.remarks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String disbursementId;
  final String obligationId;
  final String projectId;
  final String projectName;
  final String budgetId;
  final String supplier;
  final double amount;
  final String paymentMethod;
  final String bankName;
  final String referenceNumber;
  final DateTime paymentDate;
  final String approvedBy;
  final String status;
  final String remarks;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DisbursementModel.fromFirestore(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    return DisbursementModel(
      id: snapshot.id,
      disbursementId: (data['disbursementId'] ?? '').toString(),
      obligationId: (data['obligationId'] ?? '').toString(),
      projectId: (data['projectId'] ?? '').toString(),
      projectName: (data['projectName'] ?? '').toString(),
      budgetId: (data['budgetId'] ?? '').toString(),
      supplier: (data['supplier'] ?? '').toString(),
      amount: _toDouble(data['amount']),
      paymentMethod: (data['paymentMethod'] ?? '').toString(),
      bankName: (data['bankName'] ?? '').toString(),
      referenceNumber: (data['referenceNumber'] ?? '').toString(),
      paymentDate: _toDateTime(data['paymentDate']),
      approvedBy: (data['approvedBy'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      remarks: (data['remarks'] ?? '').toString(),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'disbursementId': disbursementId,
      'obligationId': obligationId,
      'projectId': projectId,
      'projectName': projectName,
      'budgetId': budgetId,
      'supplier': supplier,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'bankName': bankName,
      'referenceNumber': referenceNumber,
      'paymentDate': Timestamp.fromDate(paymentDate),
      'approvedBy': approvedBy,
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
