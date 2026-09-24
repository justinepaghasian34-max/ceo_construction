import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../models/budget_model.dart';
import 'firebase_service.dart';

class BudgetManagementController extends ChangeNotifier {
  BudgetManagementController(this._firebaseService);

  final FirebaseService _firebaseService;
  bool _isBusy = false;
  bool get isBusy => _isBusy;
  String? _error;
  String? get error => _error;

  Stream<List<BudgetModel>> watchBudgets() {
    return _firebaseService.budgetsCollection
        .orderBy('dateCreated', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BudgetModel.fromFirestore(doc))
            .toList());
  }

  Future<void> saveBudget(BudgetModel budget) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final docId = budget.id.isEmpty ? const Uuid().v4() : budget.id;
      final payload = budget
          .copyWith(
            id: docId,
            budgetId: budget.budgetId.isEmpty
                ? 'BUD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'
                : budget.budgetId,
            usedAmount: budget.usedAmount,
            remainingAmount: budget.remaining,
            updatedAt: DateTime.now(),
          )
          .toFirestore();

      await _firebaseService.budgetsCollection.doc(docId).set(payload);
      await _writeActivityLog(
        title: 'Budget ${budget.budgetId.isEmpty ? 'saved' : 'updated'}',
        detail: '${budget.projectName} • ${budget.budgetCategory}',
      );
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteBudget(String id) async {
    await _firebaseService.budgetsCollection.doc(id).delete();
  }

  Future<List<BudgetModel>> getProjectBudgets(String projectId) async {
    final snapshot = await _firebaseService.budgetsCollection
        .where('projectId', isEqualTo: projectId)
        .orderBy('dateCreated', descending: true)
        .get();

    return snapshot.docs.map((doc) => BudgetModel.fromFirestore(doc)).toList();
  }

  Future<void> reconcileBudgetUsage(
      {String? projectId, String? category}) async {
    final budgetsSnapshot = await _firebaseService.budgetsCollection.get();
    final obligationsSnapshot =
        await _firebaseService.obligationsCollection.get();
    final disbursementsSnapshot =
        await _firebaseService.disbursementsCollection.get();

    final obligationsByBudget = <String, double>{};
    final disbursementsByBudget = <String, double>{};

    for (final doc in obligationsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final obligationProjectId = (data['projectId'] ?? '').toString();
      final obligationCategory = (data['category'] ?? '').toString();
      final obligationAmount = _toDouble(data['amount']);
      final budgetId = (data['budgetId'] ?? '').toString();
      if (budgetId.isEmpty) {
        final budgetDoc = await _findBudgetForProjectAndCategory(
          projectId: obligationProjectId,
          category: obligationCategory,
        );
        if (budgetDoc == null) continue;
        await _updateBudgetUsageFromMaintainedAmounts(
          budgetDoc: budgetDoc,
          usedDelta: obligationAmount,
        );
        continue;
      }
      obligationsByBudget[budgetId] =
          (obligationsByBudget[budgetId] ?? 0.0) + obligationAmount;
    }

    for (final doc in disbursementsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = _toDouble(data['amount']);
      final budgetId = (data['budgetId'] ?? '').toString();
      if (budgetId.isEmpty) {
        final obligationDoc = await _firebaseService.obligationsCollection
            .doc((data['obligationId'] ?? '').toString())
            .get();
        if (!obligationDoc.exists) continue;
        final obligationData = obligationDoc.data() as Map<String, dynamic>;
        final projectId = (obligationData['projectId'] ?? '').toString();
        final category = (obligationData['category'] ?? '').toString();
        final budgetDoc = await _findBudgetForProjectAndCategory(
          projectId: projectId,
          category: category,
        );
        if (budgetDoc == null) continue;
        await _updateBudgetUsageFromMaintainedAmounts(
          budgetDoc: budgetDoc,
          usedDelta: amount,
        );
        continue;
      }
      disbursementsByBudget[budgetId] =
          (disbursementsByBudget[budgetId] ?? 0.0) + amount;
    }

    for (final doc in budgetsSnapshot.docs) {
      final budget = BudgetModel.fromFirestore(doc);
      if (projectId != null && budget.projectId != projectId) continue;
      if (category != null && budget.budgetCategory != category) continue;

      final usedFromObligations = obligationsByBudget[budget.id] ?? 0.0;
      final usedFromDisbursements = disbursementsByBudget[budget.id] ?? 0.0;
      final newUsedAmount = usedFromObligations + usedFromDisbursements;

      final payload = budget
          .copyWith(
            usedAmount: newUsedAmount,
            remainingAmount: budget.allocatedAmount - newUsedAmount,
            updatedAt: DateTime.now(),
          )
          .toFirestore();

      await _firebaseService.budgetsCollection.doc(doc.id).update(payload);
    }
  }

  Future<BudgetModel?> findBudgetForProjectAndCategory({
    required String projectId,
    required String category,
  }) async {
    final snapshot = await _firebaseService.budgetsCollection
        .where('projectId', isEqualTo: projectId)
        .where('budgetCategory', isEqualTo: category)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return BudgetModel.fromFirestore(snapshot.docs.first);
  }

  Future<void> validateBudgetAvailability({
    required String projectId,
    required String category,
    required double amount,
    String? existingObligationId,
  }) async {
    final budget = await findBudgetForProjectAndCategory(
      projectId: projectId,
      category: category,
    );

    if (budget == null) {
      throw Exception(
          'No approved budget exists for the selected project and category.');
    }

    if (budget.status.toLowerCase() != 'active') {
      throw Exception('The selected budget is not active.');
    }

    final budgetValue = budget.allocatedAmount;
    final budgetUsed = budget.usedAmount;
    final available = budgetValue - budgetUsed;
    if (available < amount) {
      throw Exception(
        'Insufficient remaining budget. Available: ${AppConstants.currencySymbol}${available.toStringAsFixed(2)}',
      );
    }
  }

  Future<void> _writeActivityLog({
    required String title,
    required String detail,
  }) async {
    try {
      await _firebaseService.activityLogsCollection.add({
        'title': title,
        'detail': detail,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'finance',
      });
    } catch (_) {
      // Budget save should succeed even if activity logging is unavailable.
    }
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

  Future<void> _updateBudgetUsageFromMaintainedAmounts({
    required DocumentSnapshot budgetDoc,
    required double usedDelta,
  }) async {
    final budget = BudgetModel.fromFirestore(budgetDoc);
    final nextUsed = budget.usedAmount + usedDelta;
    final nextRemaining = budget.allocatedAmount - nextUsed;

    await _firebaseService.budgetsCollection.doc(budgetDoc.id).update(
          BudgetModel(
            id: budgetDoc.id,
            budgetId: budget.budgetId,
            projectId: budget.projectId,
            projectName: budget.projectName,
            fiscalYear: budget.fiscalYear,
            budgetCategory: budget.budgetCategory,
            allocatedAmount: budget.allocatedAmount,
            usedAmount: nextUsed,
            remainingAmount: nextRemaining,
            dateCreated: budget.dateCreated,
            status: budget.status,
            remarks: budget.remarks,
            updatedAt: DateTime.now(),
          ).toFirestore(),
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
}

final budgetManagementControllerProvider =
    ChangeNotifierProvider<BudgetManagementController>((ref) {
  return BudgetManagementController(FirebaseService.instance);
});

final budgetsProvider = StreamProvider<List<BudgetModel>>((ref) {
  return FirebaseService.instance.budgetsCollection
      .orderBy('dateCreated', descending: true)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map((doc) => BudgetModel.fromFirestore(doc)).toList());
});

final budgetStatusOptions = <String>['Active', 'Completed', 'Cancelled'];
final budgetCategoryOptions = <String>[
  'Materials',
  'Payroll',
  'Equipment',
  'Utilities',
  'General',
];
