import 'package:flutter_test/flutter_test.dart';
import 'package:coecons/models/budget_model.dart';

void main() {
  test('remaining budget is derived automatically from allocated and used amounts', () {
    final budget = BudgetModel(
      id: 'budget-1',
      budgetId: 'BUD-10001',
      projectId: 'proj-1',
      projectName: 'Project Alpha',
      fiscalYear: '2026',
      budgetCategory: 'Materials',
      allocatedAmount: 500000,
      usedAmount: 275000,
      remainingAmount: 225000,
      dateCreated: DateTime(2026, 1, 5),
      status: 'Active',
      remarks: 'Primary materials control budget',
      updatedAt: DateTime(2026, 1, 5),
    );

    expect(budget.remaining, 225000);
    expect(budget.remainingAmount, 225000);
  });
}
