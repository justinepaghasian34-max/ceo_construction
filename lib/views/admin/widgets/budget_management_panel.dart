import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/budget_model.dart';
import '../../../services/budget_management_service.dart';
import '../../../services/firebase_service.dart';
import '../../../utils/dialog_utils.dart';
import '../../../widgets/common/app_card.dart';
import 'admin_glass_layout.dart';

class BudgetManagementPanel extends ConsumerStatefulWidget {
  const BudgetManagementPanel({super.key});

  @override
  ConsumerState<BudgetManagementPanel> createState() =>
      _BudgetManagementPanelState();
}

class _BudgetManagementPanelState extends ConsumerState<BudgetManagementPanel> {
  bool _isLoadingProjects = true;
  List<_ProjectOption> _projectOptions = const [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final snapshot = await FirebaseService.instance.projectsCollection.get();
    final options = snapshot.docs
        .where((doc) => !doc.data().toString().contains('archived'))
        .map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _ProjectOption(
        id: doc.id,
        name: (data['name'] ?? 'Untitled').toString(),
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      _projectOptions = options;
      _isLoadingProjects = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final budgetsAsync = ref.watch(budgetsProvider);
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Budget Management',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showBudgetDialog(context, budget: null),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Budget'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          budgetsAsync.when(
            data: (budgets) {
              final totalBudget = budgets.fold<double>(
                  0, (sum, item) => sum + item.allocatedAmount);
              final allocatedBudget = budgets.fold<double>(
                  0, (sum, item) => sum + item.allocatedAmount);
              final usedBudget =
                  budgets.fold<double>(0, (sum, item) => sum + item.usedAmount);
              final remainingBudget = budgets.fold<double>(
                  0, (sum, item) => sum + item.remainingAmount);

              return Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 900;
                      final cards = [
                        _SummaryCard(
                            label: 'Total Budget',
                            value: _formatCurrency(totalBudget),
                            icon: Icons.account_balance),
                        _SummaryCard(
                            label: 'Allocated Budget',
                            value: _formatCurrency(allocatedBudget),
                            icon: Icons.receipt_long),
                        _SummaryCard(
                            label: 'Used Budget',
                            value: _formatCurrency(usedBudget),
                            icon: Icons.money_off_csred_outlined),
                        _SummaryCard(
                            label: 'Remaining Budget',
                            value: _formatCurrency(remainingBudget),
                            icon: Icons.pending_actions),
                      ];

                      if (isNarrow) {
                        return Column(
                          children: cards
                              .map((card) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: card,
                                  ))
                              .toList(),
                        );
                      }

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: cards
                            .map((card) => SizedBox(width: 240, child: card))
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Budget records',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (budgets.isEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: GlassCard(
                        borderRadius: 14,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No budget records available yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.mediumGray),
                          ),
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 980) {
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: budgets.length,
                            itemBuilder: (context, index) {
                              final budget = budgets[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _BudgetListTile(
                                  budget: budget,
                                  onView: () =>
                                      _showBudgetDetails(context, budget),
                                  onEdit: () => _showBudgetDialog(context,
                                      budget: budget),
                                  onDelete: () =>
                                      _confirmDelete(context, budget),
                                ),
                              );
                            },
                          );
                        }

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingTextStyle: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              columns: const [
                                DataColumn(label: Text('Budget ID')),
                                DataColumn(label: Text('Project')),
                                DataColumn(label: Text('Fiscal Year')),
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('Allocated')),
                                DataColumn(label: Text('Used')),
                                DataColumn(label: Text('Remaining')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Date Created')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: budgets
                                  .map((budget) => DataRow(cells: [
                                        DataCell(Text(budget.budgetId)),
                                        DataCell(Text(budget.projectName)),
                                        DataCell(Text(budget.fiscalYear)),
                                        DataCell(Text(budget.budgetCategory)),
                                        DataCell(Text(_formatCurrency(
                                            budget.allocatedAmount))),
                                        DataCell(Text(_formatCurrency(
                                            budget.usedAmount))),
                                        DataCell(Text(
                                            _formatCurrency(
                                                budget.remainingAmount),
                                            style: TextStyle(
                                                color:
                                                    budget.remainingAmount < 0
                                                        ? AppTheme.errorRed
                                                        : AppTheme.softGreen))),
                                        DataCell(Text(budget.status)),
                                        DataCell(Text(DateFormat('MMM dd, yyyy')
                                            .format(budget.dateCreated))),
                                        DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                onPressed: () =>
                                                    _showBudgetDetails(
                                                        context, budget),
                                                icon: const Icon(Icons
                                                    .remove_red_eye_outlined)),
                                            IconButton(
                                                onPressed: () =>
                                                    _showBudgetDialog(context,
                                                        budget: budget),
                                                icon: const Icon(
                                                    Icons.edit_outlined)),
                                            IconButton(
                                                onPressed: () => _confirmDelete(
                                                    context, budget),
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                color: AppTheme.errorRed),
                                          ],
                                        )),
                                      ]))
                                  .toList(),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
            error: (error, stackTrace) => Center(child: Text(error.toString())),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Future<void> _showBudgetDialog(
    BuildContext context, {
    BudgetModel? budget,
  }) async {
    final controller = ref.read(budgetManagementControllerProvider.notifier);
    final budgetIdController =
        TextEditingController(text: budget?.budgetId ?? '');
    final fiscalYearController = TextEditingController(
        text: budget?.fiscalYear ?? DateTime.now().year.toString());
    final categoryController =
        TextEditingController(text: budget?.budgetCategory ?? 'Materials');
    final allocatedController = TextEditingController(
        text: budget?.allocatedAmount.toStringAsFixed(2) ?? '');
    final usedController = TextEditingController(
        text: budget?.usedAmount.toStringAsFixed(2) ?? '0.00');
    final remarksController =
        TextEditingController(text: budget?.remarks ?? '');
    String? selectedProjectId = budget?.projectId;
    String? selectedProjectName = budget?.projectName;
    String selectedStatus = budget?.status ?? 'Active';
    final createdDate = budget?.dateCreated ?? DateTime.now();
    final formKey = GlobalKey<FormState>();

    await showCenteredDialog<void>(
      context: context,
      maxWidth: 600,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (sbContext, setDialogState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        budget == null ? 'Add Budget' : 'Edit Budget',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 20),
                      if (_isLoadingProjects)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: selectedProjectId,
                          decoration:
                              const InputDecoration(labelText: 'Project'),
                          items: _projectOptions.map((project) {
                            return DropdownMenuItem<String>(
                              value: project.id,
                              child: Text(project.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            final option = _projectOptions.firstWhere(
                                (item) => item.id == value,
                                orElse: () =>
                                    const _ProjectOption(id: '', name: ''));
                            setDialogState(() {
                              selectedProjectId = value;
                              selectedProjectName = option.name;
                            });
                          },
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fiscalYearController,
                        decoration:
                            const InputDecoration(labelText: 'Fiscal Year'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: categoryController.text,
                        decoration:
                            const InputDecoration(labelText: 'Budget Category'),
                        items: const [
                          DropdownMenuItem(
                              value: 'Materials', child: Text('Materials')),
                          DropdownMenuItem(
                              value: 'Payroll', child: Text('Payroll')),
                          DropdownMenuItem(
                              value: 'Equipment', child: Text('Equipment')),
                          DropdownMenuItem(
                              value: 'Utilities', child: Text('Utilities')),
                          DropdownMenuItem(
                              value: 'General', child: Text('General')),
                        ],
                        onChanged: (value) =>
                            categoryController.text = value ?? '',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: allocatedController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Allocated Amount'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: usedController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Used Amount'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: budgetStatusOptions.map((status) {
                          return DropdownMenuItem(
                              value: status, child: Text(status));
                        }).toList(),
                        onChanged: (value) => setDialogState(
                            () => selectedStatus = value ?? 'Active'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: remarksController,
                        decoration:
                            const InputDecoration(labelText: 'Remarks'),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () async {
                              if (selectedProjectId == null ||
                                  selectedProjectId!.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Please choose a project first.'),
                                  ),
                                );
                                return;
                              }

                              final payload = BudgetModel(
                                id: budget?.id ?? '',
                                budgetId: budgetIdController.text.trim(),
                                projectId: selectedProjectId!,
                                projectName: selectedProjectName ?? '',
                                fiscalYear: fiscalYearController.text.trim(),
                                budgetCategory: categoryController.text.trim(),
                                allocatedAmount: double.tryParse(
                                        allocatedController.text) ??
                                    0.0,
                                usedAmount:
                                    double.tryParse(usedController.text) ?? 0.0,
                                remainingAmount: (double.tryParse(
                                            allocatedController.text) ??
                                        0.0) -
                                    (double.tryParse(usedController.text) ??
                                        0.0),
                                dateCreated: createdDate,
                                status: selectedStatus,
                                remarks: remarksController.text.trim(),
                                updatedAt: DateTime.now(),
                              );

                              await controller.saveBudget(payload);
                              if (!mounted) return;
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    budget == null
                                        ? 'Budget saved successfully.'
                                        : 'Budget updated successfully.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBudgetDetails(BuildContext context, BudgetModel budget) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(budget.budgetId),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Project: ${budget.projectName}'),
              const SizedBox(height: 6),
              Text('Fiscal Year: ${budget.fiscalYear}'),
              const SizedBox(height: 6),
              Text('Category: ${budget.budgetCategory}'),
              const SizedBox(height: 6),
              Text('Allocated: ${_formatCurrency(budget.allocatedAmount)}'),
              const SizedBox(height: 6),
              Text('Used: ${_formatCurrency(budget.usedAmount)}'),
              const SizedBox(height: 6),
              Text('Remaining: ${_formatCurrency(budget.remainingAmount)}'),
              const SizedBox(height: 6),
              Text('Status: ${budget.status}'),
              const SizedBox(height: 6),
              Text('Remarks: ${budget.remarks.isEmpty ? '—' : budget.remarks}'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close')),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, BudgetModel budget) async {
    final controller = ref.read(budgetManagementControllerProvider.notifier);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Budget'),
        content: Text('Delete ${budget.budgetId} for ${budget.projectName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete ?? false) {
      await controller.deleteBudget(budget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Budget deleted.')));
    }
  }

  String _formatCurrency(double value) {
    return '₱${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withAlpha(24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mediumGray)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetListTile extends StatelessWidget {
  const _BudgetListTile({
    required this.budget,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetModel budget;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(budget.budgetId,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700))),
                Text(budget.status,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.primaryBlue)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                '${budget.projectName} • ${budget.fiscalYear} • ${budget.budgetCategory}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(
                        'Allocated: ₱${budget.allocatedAmount.toStringAsFixed(2)}')),
                Expanded(
                    child:
                        Text('Used: ₱${budget.usedAmount.toStringAsFixed(2)}')),
              ],
            ),
            const SizedBox(height: 6),
            Text('Remaining: ₱${budget.remainingAmount.toStringAsFixed(2)}'),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.remove_red_eye_outlined),
                    label: const Text('View')),
                TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit')),
                TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectOption {
  const _ProjectOption({required this.id, required this.name});
  final String id;
  final String name;
}
