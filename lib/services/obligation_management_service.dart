import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/budget_model.dart';
import '../models/disbursement_model.dart';
import '../models/obligation_model.dart';
import 'firebase_service.dart';

class ObligationManagementController extends ChangeNotifier {
  ObligationManagementController(this._firebaseService);

  final FirebaseService _firebaseService;
  bool _isBusy = false;
  bool get isBusy => _isBusy;
  String? _error;
  String? get error => _error;

  Stream<List<ObligationModel>> watchObligations() {
    return _firebaseService.obligationsCollection
        .orderBy('dateObligated', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ObligationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<DisbursementModel>> watchDisbursements() {
    return _firebaseService.disbursementsCollection
        .orderBy('paymentDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DisbursementModel.fromFirestore(doc))
            .toList());
  }

  Future<void> saveObligation(ObligationModel obligation) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final budgetDoc = await _findBudgetForProjectAndCategory(
        projectId: obligation.projectId,
        category: obligation.category,
      );

      if (budgetDoc == null) {
        throw Exception(
          'No approved budget exists for ${obligation.projectName} in ${obligation.category}.',
        );
      }

      final budget = BudgetModel.fromFirestore(budgetDoc);
      final available = budget.allocatedAmount - budget.usedAmount;
      if (available < obligation.amount) {
        throw Exception(
          'Insufficient remaining budget. Available: ${budget.remainingAmount.toStringAsFixed(2)}',
        );
      }

      final docId = obligation.id.isEmpty ? const Uuid().v4() : obligation.id;
      final payload = ObligationModel(
        id: docId,
        obligationId: obligation.obligationId.isEmpty
            ? 'OB-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'
            : obligation.obligationId,
        projectId: obligation.projectId,
        projectName: obligation.projectName,
        projectCode: obligation.projectCode,
        budgetId: budget.id,
        supplier: obligation.supplier,
        category: obligation.category,
        description: obligation.description,
        amount: obligation.amount,
        fundingSource: obligation.fundingSource,
        purchaseRequestNo: obligation.purchaseRequestNo,
        purchaseOrderNo: obligation.purchaseOrderNo,
        dateObligated: obligation.dateObligated,
        expectedPaymentDate: obligation.expectedPaymentDate,
        responsibleOfficer: obligation.responsibleOfficer,
        status: obligation.status,
        remarks: obligation.remarks,
        createdAt: obligation.createdAt,
        updatedAt: DateTime.now(),
      ).toFirestore();

      await _firebaseService.obligationsCollection.doc(docId).set(payload);
      await _reconcileBudgetUsage(
          projectId: obligation.projectId, category: obligation.category);
      await _writeActivityLog(
        title:
            'Obligation ${obligation.obligationId.isEmpty ? 'saved' : 'updated'}',
        detail: '${obligation.projectName} - ${obligation.supplier}',
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteObligation(String id) async {
    final doc = await _firebaseService.obligationsCollection.doc(id).get();
    await doc.reference.delete();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      await _reconcileBudgetUsage(
        projectId: (data['projectId'] ?? '').toString(),
        category: (data['category'] ?? '').toString(),
      );
    }
  }

  Future<void> saveDisbursement(DisbursementModel disbursement) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final duplicate = await _firebaseService.disbursementsCollection
          .where('obligationId', isEqualTo: disbursement.obligationId)
          .get();

      if (duplicate.docs.isNotEmpty &&
          duplicate.docs.first.id != disbursement.id) {
        throw Exception(
          'A disbursement already exists for this obligation. Duplicate disbursements are not allowed.',
        );
      }

      final obligationDoc = await _firebaseService.obligationsCollection
          .doc(disbursement.obligationId)
          .get();

      if (!obligationDoc.exists) {
        throw Exception('The related obligation could not be found.');
      }

      final obligationData = obligationDoc.data() as Map<String, dynamic>;
      final budgetDoc = await _findBudgetForProjectAndCategory(
        projectId: (obligationData['projectId'] ?? '').toString(),
        category: (obligationData['category'] ?? '').toString(),
      );

      if (budgetDoc == null) {
        throw Exception('The related budget is missing.');
      }

      final budget = BudgetModel.fromFirestore(budgetDoc);
      final available = budget.allocatedAmount - budget.usedAmount;
      if (available < disbursement.amount) {
        throw Exception(
          'Insufficient remaining budget for disbursement release. Available: ${budget.remainingAmount.toStringAsFixed(2)}',
        );
      }

      final docId =
          disbursement.id.isEmpty ? const Uuid().v4() : disbursement.id;
      final payload = DisbursementModel(
        id: docId,
        disbursementId: disbursement.disbursementId.isEmpty
            ? 'DS-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'
            : disbursement.disbursementId,
        obligationId: disbursement.obligationId,
        projectId: disbursement.projectId,
        projectName: disbursement.projectName,
        budgetId: budget.id,
        supplier: disbursement.supplier,
        amount: disbursement.amount,
        paymentMethod: disbursement.paymentMethod,
        bankName: disbursement.bankName,
        referenceNumber: disbursement.referenceNumber,
        paymentDate: disbursement.paymentDate,
        approvedBy: disbursement.approvedBy,
        status: disbursement.status,
        remarks: disbursement.remarks,
        createdAt: disbursement.createdAt,
        updatedAt: DateTime.now(),
      ).toFirestore();

      await _firebaseService.disbursementsCollection.doc(docId).set(payload);
      await _reconcileBudgetUsage(
        projectId: disbursement.projectId,
        category: (obligationData['category'] ?? '').toString(),
      );
      await _writeActivityLog(
        title: 'Disbursement released',
        detail: '${disbursement.disbursementId} • ${disbursement.projectName}',
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteDisbursement(String id) async {
    final doc = await _firebaseService.disbursementsCollection.doc(id).get();
    await doc.reference.delete();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final obligationId = (data['obligationId'] ?? '').toString();
      final obligationDoc =
          await _firebaseService.obligationsCollection.doc(obligationId).get();
      if (obligationDoc.exists) {
        final obligationData = obligationDoc.data() as Map<String, dynamic>;
        await _reconcileBudgetUsage(
          projectId: (obligationData['projectId'] ?? '').toString(),
          category: (obligationData['category'] ?? '').toString(),
        );
      }
    }
  }

  Future<void> _reconcileBudgetUsage({
    required String projectId,
    required String category,
  }) async {
    final budgetSnap = await _firebaseService.budgetsCollection
        .where('projectId', isEqualTo: projectId)
        .where('budgetCategory', isEqualTo: category)
        .limit(1)
        .get();

    if (budgetSnap.docs.isEmpty) {
      return;
    }

    final budgetDoc = budgetSnap.docs.first;
    final budget = BudgetModel.fromFirestore(budgetDoc);

    final obligationsSnap = await _firebaseService.obligationsCollection
        .where('projectId', isEqualTo: projectId)
        .where('category', isEqualTo: category)
        .get();

    final disbursementsSnap = await _firebaseService.disbursementsCollection
        .where('projectId', isEqualTo: projectId)
        .get();

    double usedAmount = 0;
    for (final doc in obligationsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      usedAmount += _toDouble(data['amount']);
    }

    for (final doc in disbursementsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final obligationId = (data['obligationId'] ?? '').toString();
      if (obligationId.isEmpty) {
        continue;
      }

      final obligationDoc =
          await _firebaseService.obligationsCollection.doc(obligationId).get();

      if (!obligationDoc.exists) {
        continue;
      }

      final obligationData = obligationDoc.data() as Map<String, dynamic>;
      final obligationCategory = (obligationData['category'] ?? '').toString();
      if (obligationCategory != category) {
        continue;
      }

      usedAmount += _toDouble(data['amount']);
    }

    final payload = budget
        .copyWith(
          usedAmount: usedAmount,
          remainingAmount: budget.allocatedAmount - usedAmount,
          updatedAt: DateTime.now(),
        )
        .toFirestore();

    await _firebaseService.budgetsCollection.doc(budgetDoc.id).update(payload);
  }

  Future<DocumentSnapshot?> _findBudgetForProjectAndCategory({
    required String projectId,
    required String category,
  }) async {
    final snapshot = await _firebaseService.budgetsCollection
        .where('projectId', isEqualTo: projectId)
        .where('budgetCategory', isEqualTo: category)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(',', '').replaceAll('₱', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> _writeActivityLog(
      {required String title, required String detail}) async {
    await _firebaseService.activityLogsCollection.add({
      'title': title,
      'detail': detail,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'finance',
    });
  }
}

final obligationManagementControllerProvider =
    ChangeNotifierProvider<ObligationManagementController>((ref) {
  return ObligationManagementController(FirebaseService.instance);
});

final obligationsProvider = StreamProvider<List<ObligationModel>>((ref) {
  final firebase = FirebaseService.instance;
  return firebase.obligationsCollection
      .orderBy('dateObligated', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => ObligationModel.fromFirestore(doc))
          .toList());
});

final disbursementsProvider = StreamProvider<List<DisbursementModel>>((ref) {
  final firebase = FirebaseService.instance;
  return firebase.disbursementsCollection
      .orderBy('paymentDate', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => DisbursementModel.fromFirestore(doc))
          .toList());
});

final obligationStatusOptions = <String>[
  'Draft',
  'Pending Approval',
  'Approved',
  'Waiting for Disbursement',
  'Released',
  'Cancelled',
];

final paymentStatusOptions = <String>[
  'Pending',
  'Processing',
  'Completed',
  'Cancelled',
];

final paymentMethodOptions = <String>[
  'Cash',
  'Check',
  'Bank Transfer',
  'Online Payment',
];

String formatMoney(num value) {
  return '₱${value.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      )}';
}

String capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

class ObligationDashboardSummary {
  const ObligationDashboardSummary({
    required this.total,
    required this.pending,
    required this.approved,
    required this.released,
    required this.cancelled,
    required this.totalAmount,
  });

  final int total;
  final int pending;
  final int approved;
  final int released;
  final int cancelled;
  final double totalAmount;
}

class DisbursementDashboardSummary {
  const DisbursementDashboardSummary({
    required this.total,
    required this.pending,
    required this.processing,
    required this.completed,
    required this.cancelled,
    required this.totalAmount,
    required this.remainingBudget,
  });

  final int total;
  final int pending;
  final int processing;
  final int completed;
  final int cancelled;
  final double totalAmount;
  final double remainingBudget;
}

final appPrimaryColor = const Color(0xFF1A237E);
final appSecondaryColor = const Color(0xFF28A745);
final appWarningColor = const Color(0xFFFF9800);
final appBackgroundColor = const Color(0xFFF4F6F9);
final appAccentColor = const Color(0xFF6C757D);
