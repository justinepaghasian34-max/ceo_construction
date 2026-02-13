import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firebase_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';

class AdminFinancialMonitoring extends StatelessWidget {
  const AdminFinancialMonitoring({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Budget & Financial Monitoring',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<_FinancialOverviewData>(
        future: _loadFinancialOverview(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load financial data',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null || data.summaries.isEmpty) {
            return Center(
              child: Text(
                'No project financial data available yet.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
              ),
            );
          }

          final visibleSummaries = data.summaries.take(5).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 700;

                    Widget buildStatCard({
                      required IconData icon,
                      required Color iconColor,
                      required String label,
                      required String value,
                    }) {
                      return AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: iconColor.withAlpha(24),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(icon, color: iconColor, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppTheme.mediumGray),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              value,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryBlue,
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    final totalBudgetCard = buildStatCard(
                      icon: Icons.account_balance,
                      iconColor: AppTheme.deepBlue,
                      label: 'Total approved budget',
                      value: _formatCurrency(data.totalBudget),
                    );

                    final totalExpensesCard = buildStatCard(
                      icon: Icons.trending_up,
                      iconColor: AppTheme.accentYellow,
                      label: 'Total recorded expenses',
                      value: _formatCurrency(data.totalExpenses),
                    );

                    final utilizationText = data.totalBudget <= 0
                        ? '—'
                        : '${(data.totalExpenses / data.totalBudget * 100).clamp(0, 999).toStringAsFixed(1)}%';

                    final overBudgetLabel = data.overBudgetProjects == 1
                        ? 'project'
                        : 'projects';

                    final utilizationCard = buildStatCard(
                      icon: Icons.pie_chart,
                      iconColor: AppTheme.softGreen,
                      label:
                          'Overall utilization  ${data.overBudgetProjects} $overBudgetLabel over budget',
                      value: utilizationText,
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          totalBudgetCard,
                          const SizedBox(height: 12),
                          totalExpensesCard,
                          const SizedBox(height: 12),
                          utilizationCard,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: totalBudgetCard),
                            const SizedBox(width: 12),
                            Expanded(child: totalExpensesCard),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(children: [Expanded(child: utilizationCard)]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Budget vs expenses per project',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      _showFullBudgetVsExpensesTable(context, data.summaries),
                  child: _buildBudgetVsExpensesTable(context, visibleSummaries),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap table to view all projects',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.budgetFinancial,
      ),
    );
  }

  Widget _buildBudgetVsExpensesTable(
    BuildContext context,
    List<_ProjectFinancialSummary> summaries,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.mediumGray,
        ),
        columns: const [
          DataColumn(label: Text('Project')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Budget')),
          DataColumn(label: Text('Expenses')),
          DataColumn(label: Text('Profit')),
          DataColumn(label: Text('Utilization')),
        ],
        rows: [
          for (final item in summaries)
            _buildProjectFinancialRow(context, item),
        ],
      ),
    );
  }

  void _showFullBudgetVsExpensesTable(
    BuildContext context,
    List<_ProjectFinancialSummary> summaries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Budget vs expenses per project',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildBudgetVsExpensesTable(
                        sheetContext,
                        summaries,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_FinancialOverviewData> _loadFinancialOverview() async {
    final firebase = FirebaseService.instance;
    final firestore = FirebaseFirestore.instance;

    final projectsSnap = await firebase.projectsCollection.get();
    final disbursementsSnap = await firebase.disbursementsCollection.get();
    final payrollSnap = await firestore.collectionGroup('payroll').get();

    final Map<String, double> materialsExpensesByProject = {};
    final Map<String, double> payrollExpensesByProject = {};
    final Map<String, double> otherExpensesByProject = {};
    final Map<String, List<_ExpenseDetail>> expenseDetailsByProject = {};
    final Map<String, double> expensesByProject = {};
    double totalExpenses = 0;

    for (final doc in disbursementsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final projectId = (data['projectId'] ?? '').toString();
      if (projectId.isEmpty) {
        continue;
      }
      final rawAmount = data['amount'];
      double amount;
      if (rawAmount is num) {
        amount = rawAmount.toDouble();
      } else if (rawAmount is String) {
        final cleaned = rawAmount
            .replaceAll(',', '')
            .replaceAll('₱', '')
            .trim();
        amount = double.tryParse(cleaned) ?? 0.0;
      } else {
        amount = 0.0;
      }
      if (amount <= 0) {
        continue;
      }

      final type = (data['type'] ?? '').toString();
      String category;
      if (type == 'material_request') {
        category = 'materials';
      } else if (type == 'payroll') {
        category = 'payroll';
      } else {
        category = 'other';
      }

      if (category == 'materials') {
        materialsExpensesByProject[projectId] =
            (materialsExpensesByProject[projectId] ?? 0.0) + amount;
      } else if (category == 'payroll') {
        payrollExpensesByProject[projectId] =
            (payrollExpensesByProject[projectId] ?? 0.0) + amount;
      } else {
        otherExpensesByProject[projectId] =
            (otherExpensesByProject[projectId] ?? 0.0) + amount;
      }

      expensesByProject[projectId] =
          (expensesByProject[projectId] ?? 0.0) + amount;
      totalExpenses += amount;

      final subject = (data['subject'] ?? data['description'] ?? 'Expense')
          .toString();
      expenseDetailsByProject
          .putIfAbsent(projectId, () => [])
          .add(
            _ExpenseDetail(
              category: category,
              description: subject,
              amount: amount,
            ),
          );
    }

    for (final doc in payrollSnap.docs) {
      final data = doc.data();
      final projectId = (data['projectId'] ?? '').toString();
      if (projectId.isEmpty) {
        continue;
      }

      final rawAmount = data['totalAmount'];
      double amount;
      if (rawAmount is num) {
        amount = rawAmount.toDouble();
      } else if (rawAmount is String) {
        final cleaned = rawAmount
            .replaceAll(',', '')
            .replaceAll('₱', '')
            .trim();
        amount = double.tryParse(cleaned) ?? 0.0;
      } else {
        amount = 0.0;
      }

      if (amount <= 0) {
        continue;
      }

      payrollExpensesByProject[projectId] =
          (payrollExpensesByProject[projectId] ?? 0.0) + amount;
      expensesByProject[projectId] =
          (expensesByProject[projectId] ?? 0.0) + amount;
      totalExpenses += amount;

      final status = (data['status'] ?? '').toString();
      final description = status.isEmpty ? 'Payroll' : 'Payroll ($status)';
      expenseDetailsByProject
          .putIfAbsent(projectId, () => [])
          .add(
            _ExpenseDetail(
              category: 'payroll',
              description: description,
              amount: amount,
            ),
          );
    }

    final List<_ProjectFinancialSummary> summaries = [];
    double totalBudget = 0;
    int overBudgetProjects = 0;

    for (final doc in projectsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final projectId = doc.id;
      final name = (data['name'] ?? 'Untitled').toString();
      final status = (data['status'] ?? 'unknown').toString();

      final progressRaw = data['progressPercentage'];
      double progress;
      if (progressRaw is num) {
        progress = progressRaw.toDouble();
      } else if (progressRaw is String) {
        final cleaned = progressRaw.replaceAll('%', '').trim();
        progress = double.tryParse(cleaned) ?? 0.0;
      } else {
        progress = 0.0;
      }

      final budgetRaw = data['contractAmount'] ?? data['approvedBudget'];
      double budget;
      if (budgetRaw is num) {
        budget = budgetRaw.toDouble();
      } else if (budgetRaw is String) {
        final cleaned = budgetRaw
            .replaceAll(',', '')
            .replaceAll('₱', '')
            .trim();
        budget = double.tryParse(cleaned) ?? 0.0;
      } else {
        budget = 0.0;
      }

      final materialsExpenses = materialsExpensesByProject[projectId] ?? 0.0;
      final payrollExpenses = payrollExpensesByProject[projectId] ?? 0.0;
      final otherExpenses = otherExpensesByProject[projectId] ?? 0.0;
      final expenses =
          expensesByProject[projectId] ??
          (materialsExpenses + payrollExpenses + otherExpenses);

      totalBudget += budget;
      if (budget > 0 && expenses > budget) {
        overBudgetProjects++;
      }

      summaries.add(
        _ProjectFinancialSummary(
          projectId: projectId,
          name: name,
          status: status,
          progress: progress,
          budget: budget,
          expenses: expenses,
          materialsExpenses: materialsExpenses,
          payrollExpenses: payrollExpenses,
          otherExpenses: otherExpenses,
          expenseDetails:
              expenseDetailsByProject[projectId] ?? const <_ExpenseDetail>[],
        ),
      );
    }

    summaries.sort((a, b) => b.utilization.compareTo(a.utilization));

    return _FinancialOverviewData(
      summaries: summaries,
      totalBudget: totalBudget,
      totalExpenses: totalExpenses,
      overBudgetProjects: overBudgetProjects,
    );
  }
}

class _FinancialOverviewData {
  final List<_ProjectFinancialSummary> summaries;
  final double totalBudget;
  final double totalExpenses;
  final int overBudgetProjects;

  const _FinancialOverviewData({
    required this.summaries,
    required this.totalBudget,
    required this.totalExpenses,
    required this.overBudgetProjects,
  });
}

class _ExpenseDetail {
  final String category;
  final String description;
  final double amount;

  const _ExpenseDetail({
    required this.category,
    required this.description,
    required this.amount,
  });
}

class _ProjectFinancialSummary {
  final String projectId;
  final String name;
  final String status;
  final double progress;
  final double budget;
  final double expenses;
  final double materialsExpenses;
  final double payrollExpenses;
  final double otherExpenses;
  final List<_ExpenseDetail> expenseDetails;

  const _ProjectFinancialSummary({
    required this.projectId,
    required this.name,
    required this.status,
    required this.progress,
    required this.budget,
    required this.expenses,
    required this.materialsExpenses,
    required this.payrollExpenses,
    required this.otherExpenses,
    required this.expenseDetails,
  });

  double get profit => budget - expenses;

  double get remaining => profit;

  double get utilization =>
      budget <= 0 ? 0.0 : (expenses / budget).clamp(0.0, 2.0);
}

DataRow _buildProjectFinancialRow(
  BuildContext context,
  _ProjectFinancialSummary item,
) {
  Color statusColor;
  final normalizedStatus = item.status.toLowerCase();
  if (normalizedStatus == 'ongoing') {
    statusColor = AppTheme.softGreen;
  } else if (normalizedStatus == 'completed') {
    statusColor = AppTheme.primaryBlue;
  } else if (normalizedStatus == 'pending') {
    statusColor = AppTheme.warningOrange;
  } else {
    statusColor = AppTheme.mediumGray;
  }

  String formattedStatus;
  if (item.status.isEmpty) {
    formattedStatus = '—';
  } else {
    formattedStatus = item.status[0].toUpperCase() + item.status.substring(1);
  }
  final utilizationPercent = item.budget <= 0
      ? '—'
      : '${(item.utilization * 100).toStringAsFixed(0)}%';

  Color utilizationColor;
  if (item.budget <= 0 && item.expenses <= 0) {
    utilizationColor = AppTheme.mediumGray;
  } else if (item.utilization < 0.7) {
    utilizationColor = AppTheme.primaryBlue;
  } else if (item.utilization <= 1.0) {
    utilizationColor = AppTheme.accentYellow;
  } else {
    utilizationColor = AppTheme.errorRed;
  }

  return DataRow(
    cells: [
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            item.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      DataCell(
        Text(
          formattedStatus,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: statusColor),
        ),
      ),
      DataCell(
        Text(
          _formatCurrency(item.budget),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          _formatCurrency(item.expenses),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.primaryBlue,
            decoration: TextDecoration.underline,
          ),
        ),
        onTap: () => _showExpenseBreakdown(context, item),
      ),
      DataCell(
        Text(
          _formatCurrency(item.profit),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          utilizationPercent,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: utilizationColor),
        ),
      ),
    ],
  );
}

void _showExpenseBreakdown(
  BuildContext context,
  _ProjectFinancialSummary item,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final materials = item.expenseDetails
          .where((e) => e.category == 'materials')
          .toList();
      final payroll = item.expenseDetails
          .where((e) => e.category == 'payroll')
          .toList();
      final other = item.expenseDetails
          .where((e) => e.category == 'other')
          .toList();

      Widget buildCategorySection({
        required String title,
        required double total,
        required List<_ExpenseDetail> details,
        required Color color,
      }) {
        return ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                _formatCurrency(total),
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
            ],
          ),
          children: [
            if (details.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'No records for this category.',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                ),
              )
            else
              ...details.map(
                (d) => ListTile(
                  dense: true,
                  title: Text(d.description),
                  trailing: Text(
                    _formatCurrency(d.amount),
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        );
      }

      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Expense breakdown',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.name,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total expenses: ${_formatCurrency(item.expenses)}',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      buildCategorySection(
                        title: 'Materials',
                        total: item.materialsExpenses,
                        details: materials,
                        color: AppTheme.primaryBlue,
                      ),
                      buildCategorySection(
                        title: 'Payroll',
                        total: item.payrollExpenses,
                        details: payroll,
                        color: AppTheme.softGreen,
                      ),
                      buildCategorySection(
                        title: 'Other',
                        total: item.otherExpenses,
                        details: other,
                        color: AppTheme.accentYellow,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _formatCurrency(double value) {
  final amount = value.toStringAsFixed(2);
  final parts = amount.split('.');
  final integerPart = parts[0];
  final decimalPart = parts[1];

  final buffer = StringBuffer();
  int count = 0;
  for (int i = integerPart.length - 1; i >= 0; i--) {
    buffer.write(integerPart[i]);
    count++;
    if (count == 3 && i != 0) {
      buffer.write(',');
      count = 0;
    }
  }
  final formattedInt = buffer.toString().split('').reversed.join();
  return '₱$formattedInt.$decimalPart';
}
