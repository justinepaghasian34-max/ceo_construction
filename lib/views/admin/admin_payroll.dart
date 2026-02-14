import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payroll_model.dart';
import '../../models/attendance_model.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/audit_log_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

String formatCurrency(double value) {
  // Simple peso currency formatting: ₱1,234,567.89
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

String formatHours(double hours) {
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  final hoursStr = h.toString().padLeft(2, '0');
  final minutesStr = m.toString().padLeft(2, '0');
  return '$hoursStr:$minutesStr';
}

String shortProjectId(String projectId) {
  if (projectId.isEmpty) return 'Unknown';
  if (projectId.length <= 6) return projectId;
  return projectId.substring(0, 6);
}

class AdminPayroll extends StatefulWidget {
  const AdminPayroll({super.key});

  @override
  State<AdminPayroll> createState() => _AdminPayrollState();
}

class _AdminPayrollState extends State<AdminPayroll> {
  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collectionGroup('payroll');

    return AdminGlassScaffold(
      title: 'Payroll Monitoring',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(RouteNames.notifications),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.payroll,
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load payroll data',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final payrolls = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return PayrollModel.fromJson({'id': doc.id, ...data});
          }).toList();

          double totalPayroll = 0;
          double totalOvertimeHours = 0;
          double pendingPayoutTotal = 0;
          final Set<String> activeWorkerIds = {};
          final Map<String, Map<String, _WorkerPayrollEntry>>
          aggregatedByProject = {};
          final Map<String, String> validationStatusByProject = {};
          final List<_RecentPayout> recentPayouts = [];

          for (final payroll in payrolls) {
            totalPayroll += payroll.totalAmount;
            if (!payroll.isPaid) {
              pendingPayoutTotal += payroll.totalAmount;
            }

            final projectId = payroll.projectId.isNotEmpty
                ? payroll.projectId
                : 'Unknown site';

            final status = payroll.validationStatus;
            if (status != null && status.isNotEmpty) {
              final current = validationStatusByProject[projectId];
              if (current == null ||
                  current == 'unknown' ||
                  (current == 'validated' && status == 'needs_review')) {
                validationStatusByProject[projectId] = status;
              }
            }

            if (payroll.isPaid && payroll.paidAt != null) {
              for (final item in payroll.items) {
                recentPayouts.add(
                  _RecentPayout(
                    workerName: item.workerName,
                    amount: item.netPay,
                    date: payroll.paidAt!,
                  ),
                );
              }
            }

            final projectEntries = aggregatedByProject.putIfAbsent(
              projectId,
              () => {},
            );

            for (final item in payroll.items) {
              final workerKey = item.workerId.isNotEmpty
                  ? item.workerId
                  : item.workerName;
              activeWorkerIds.add(workerKey);
              totalOvertimeHours += item.overtimeHours;

              final existingEntry = projectEntries[workerKey];
              if (existingEntry == null) {
                final aggregatedItem = PayrollItem(
                  workerId: item.workerId,
                  workerName: item.workerName,
                  position: item.position,
                  dailyRate: item.dailyRate,
                  daysWorked: item.daysWorked,
                  regularHours: item.regularHours,
                  overtimeHours: item.overtimeHours,
                  grossPay: item.grossPay,
                  deductions: item.deductions,
                  netPay: item.netPay,
                  deductionBreakdown: Map<String, double>.from(
                    item.deductionBreakdown,
                  ),
                );

                projectEntries[workerKey] = _WorkerPayrollEntry(
                  item: aggregatedItem,
                  payrollStatus: payroll.status,
                  workerKey: workerKey,
                );
              } else {
                final aggregatedItem = existingEntry.item;
                aggregatedItem.regularHours += item.regularHours;
                aggregatedItem.overtimeHours += item.overtimeHours;
                aggregatedItem.grossPay += item.grossPay;
                aggregatedItem.deductions += item.deductions;
                aggregatedItem.netPay += item.netPay;

                item.deductionBreakdown.forEach((key, value) {
                  aggregatedItem.deductionBreakdown[key] =
                      (aggregatedItem.deductionBreakdown[key] ?? 0) + value;
                });

                final mergedStatus =
                    existingEntry.payrollStatus == 'paid' || payroll.isPaid
                    ? 'paid'
                    : payroll.status;

                projectEntries[workerKey] = _WorkerPayrollEntry(
                  item: aggregatedItem,
                  payrollStatus: mergedStatus,
                  workerKey: workerKey,
                );
              }
            }
          }

          final Map<String, List<_WorkerPayrollEntry>> itemsByProject = {};
          for (final entry in aggregatedByProject.entries) {
            final workers =
                entry.value.values
                    .where((e) => e.payrollStatus != 'paid')
                    .toList()
                  ..sort(
                    (a, b) => a.item.workerName.compareTo(b.item.workerName),
                  );

            if (workers.isNotEmpty) {
              itemsByProject[entry.key] = workers;
            }
          }

          recentPayouts.sort((a, b) => b.date.compareTo(a.date));
          final visiblePayouts = recentPayouts.take(5).toList();

          final hive = HiveService.instance;
          final allAttendance = hive.getAllAttendance();
          final now = DateTime.now();
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 1);

          final List<AttendanceModel> monthAttendance = allAttendance
              .where(
                (a) =>
                    !a.attendanceDate.isBefore(startOfMonth) &&
                    a.attendanceDate.isBefore(endOfMonth),
              )
              .toList();

          // Use current-month attendance when available; otherwise fall back to
          // all attendance so Admin still sees Site Manager data.
          final List<AttendanceModel> attendanceForPayroll =
              monthAttendance.isNotEmpty ? monthAttendance : allAttendance;

          return GlassCard(
            borderRadius: 18,
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SmartInsightCard(
                    title: 'Smart Insight',
                    message:
                        'Track pending payouts and overtime hours to avoid payroll delays.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      Widget buildStatCard({
                        required IconData icon,
                        required Color iconColor,
                        required String label,
                        required String value,
                      }) {
                        return AppCard(
                          padding: const EdgeInsets.all(16),
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
                                    child: Icon(
                                      icon,
                                      color: iconColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppTheme.mediumGray),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                value,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryBlue,
                                    ),
                              ),
                            ],
                          ),
                        );
                      }

                      final totalCard = buildStatCard(
                        icon: Icons.payments,
                        iconColor: AppTheme.softGreen,
                        label: 'Total payroll cost',
                        value: formatCurrency(totalPayroll),
                      );

                      final workersCard = buildStatCard(
                        icon: Icons.groups,
                        iconColor: AppTheme.primaryBlue,
                        label: 'Active workers',
                        value: activeWorkerIds.length.toString(),
                      );

                      final pendingCard = buildStatCard(
                        icon: Icons.pending_actions,
                        iconColor: AppTheme.warningOrange,
                        label: 'Pending payouts',
                        value: formatCurrency(pendingPayoutTotal),
                      );

                      final overtimeCard = buildStatCard(
                        icon: Icons.access_time,
                        iconColor: AppTheme.accentYellow,
                        label: 'Overtime hours',
                        value: '${formatHours(totalOvertimeHours)} hrs',
                      );

                      final isNarrow = constraints.maxWidth < 700;
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            totalCard,
                            const SizedBox(height: 12),
                            workersCard,
                            const SizedBox(height: 12),
                            pendingCard,
                            const SizedBox(height: 12),
                            overtimeCard,
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: totalCard),
                              const SizedBox(width: 12),
                              Expanded(child: workersCard),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: pendingCard),
                              const SizedBox(width: 12),
                              Expanded(child: overtimeCard),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Worker payroll details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (itemsByProject.isEmpty)
                    Text(
                      'No payroll data available yet.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                  if (itemsByProject.isNotEmpty) const SizedBox(height: 4),
                  if (itemsByProject.isNotEmpty)
                    for (final entry in itemsByProject.entries) ...[
                      GlassCard(
                        borderRadius: 16,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Site: ${shortProjectId(entry.key)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                if (validationStatusByProject[entry.key] !=
                                        null &&
                                    validationStatusByProject[entry.key]!
                                        .isNotEmpty)
                                  _buildValidationChip(
                                    context,
                                    validationStatusByProject[entry.key]!,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () => _showFullWorkerPayrollTable(
                                context,
                                entry.key,
                                entry.value,
                              ),
                              child: GlassDataTableTheme(
                                child: _buildWorkerPayrollDataTable(
                                  context,
                                  entry.value,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Tap table to view full payroll for this site',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.mediumGray,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: () => _submitProjectPayroll(entry.key),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Submit payroll for this site'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 12),
                  if (attendanceForPayroll.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _generatePayrollFromAttendance(attendanceForPayroll),
                        icon: const Icon(Icons.playlist_add_check),
                        label: const Text('Generate payroll from attendance'),
                      ),
                    ),
                  if (attendanceForPayroll.isEmpty)
                    Text(
                      'No attendance data available to generate payroll.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                  const SizedBox(height: 16),
                  _buildRecentPayrollPayoutsSection(context, visiblePayouts),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkerPayrollDataTable(
    BuildContext context,
    List<_WorkerPayrollEntry> entries,
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
          DataColumn(label: Text('Worker name')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Hours worked')),
          DataColumn(label: Text('Hourly rate')),
          DataColumn(label: Text('Total payout')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final workerEntry in entries)
            _buildWorkerPayrollRow(
              context,
              workerEntry.item,
              workerEntry.payrollStatus,
            ),
        ],
      ),
    );
  }

  Future<void> _submitProjectPayroll(String projectId) async {
    if (projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid project ID for payroll submission.'),
        ),
      );
      return;
    }

    final firebase = FirebaseService.instance;
    final firestore = FirebaseFirestore.instance;

    try {
      final querySnapshot = await firebase
          .payrollCollection(projectId)
          .where('status', isNotEqualTo: 'paid')
          .get();

      if (querySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pending payroll to submit for this site.'),
          ),
        );
        return;
      }

      final now = DateTime.now();
      final batch = firestore.batch();
      double totalAmount = 0;
      int totalWorkers = 0;

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final payroll = PayrollModel.fromJson({'id': doc.id, ...data});

        if (payroll.isPaid) {
          continue;
        }

        totalAmount += payroll.totalAmount;
        totalWorkers += payroll.totalWorkers;

        batch.update(doc.reference, <String, dynamic>{
          'status': 'paid',
          'paidBy': 'admin_submit',
          'paidAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
      }

      await batch.commit();

      await AuditLogService.instance.logAction(
        action: 'payroll_submitted_by_admin',
        projectId: projectId,
        details: {
          'totalAmount': totalAmount,
          'totalWorkers': totalWorkers,
          'payrollCount': querySnapshot.docs.length,
          'submittedAt': now.toIso8601String(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payroll submitted and marked as paid.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit payroll: $e')));
    }
  }

  Future<void> _generatePayrollFromAttendance(
    List<AttendanceModel> attendanceList,
  ) async {
    if (attendanceList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attendance data available to generate payroll.'),
        ),
      );
      return;
    }

    final Map<String, _AttendancePayrollAggregate> aggregates = {};

    for (final attendance in attendanceList) {
      for (final record in attendance.records) {
        final bool hasDayFlags =
            record.monPresent ||
            record.tuePresent ||
            record.wedPresent ||
            record.thuPresent ||
            record.friPresent ||
            record.satPresent;

        final bool isPresent = record.isPresent || hasDayFlags;
        if (!isPresent) continue;

        int daysForRecord = 0;
        if (record.monPresent) daysForRecord++;
        if (record.tuePresent) daysForRecord++;
        if (record.wedPresent) daysForRecord++;
        if (record.thuPresent) daysForRecord++;
        if (record.friPresent) daysForRecord++;
        if (record.satPresent) daysForRecord++;

        // Older records may only use the generic isPresent flag.
        if (daysForRecord == 0 && isPresent) {
          daysForRecord = 1;
        }

        final workerKey =
            '${attendance.projectId}_${record.workerId.isNotEmpty ? record.workerId : record.workerName}';

        final existing = aggregates[workerKey];
        if (existing == null) {
          aggregates[workerKey] = _AttendancePayrollAggregate(
            projectId: attendance.projectId,
            workerId: record.workerId,
            workerName: record.workerName,
            position: record.position,
            workerType: record.workerType,
            hourlyRate: record.rate > 0 ? record.rate / 8.0 : 0.0,
            daysPresent: daysForRecord,
            totalHours: record.totalHours,
          );
        } else {
          existing.daysPresent += daysForRecord;
          existing.totalHours += record.totalHours;

          // Prefer a non-zero rate if we encounter one later.
          if (existing.hourlyRate <= 0 && record.rate > 0) {
            existing.hourlyRate = record.rate / 8.0;
          }
        }
      }
    }

    if (aggregates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No present workers found in attendance.'),
        ),
      );
      return;
    }

    final Map<String, List<_AttendancePayrollAggregate>> aggregatesByProject =
        {};
    for (final aggregate in aggregates.values) {
      final projectId = aggregate.projectId;
      if (projectId.isEmpty) continue;
      aggregatesByProject.putIfAbsent(projectId, () => []).add(aggregate);
    }

    if (aggregatesByProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No project information available for attendance records.',
          ),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    final firebase = FirebaseService.instance;

    try {
      for (final entry in aggregatesByProject.entries) {
        final projectId = entry.key;
        final recordsForProject = entry.value;

        final payrollDocRef = firebase.payrollCollection(projectId).doc();
        final payrollId = payrollDocRef.id;

        final List<PayrollItem> items = [];
        double totalAmount = 0.0;

        for (final aggregate in recordsForProject) {
          final name = aggregate.workerName.trim();
          final position = aggregate.position.trim();
          final hours = aggregate.totalHours;
          final hourlyRate = aggregate.hourlyRate;

          if (name.isEmpty &&
              position.isEmpty &&
              hours <= 0 &&
              hourlyRate <= 0) {
            continue;
          }

          final total = hourlyRate > 0 && hours > 0 ? hourlyRate * hours : 0.0;
          totalAmount += total;

          items.add(
            PayrollItem(
              workerId: aggregate.workerId,
              workerName: name,
              position: position,
              dailyRate: 0,
              daysWorked: 0,
              regularHours: hours,
              overtimeHours: 0,
              grossPay: total,
              deductions: 0,
              netPay: total,
              deductionBreakdown: <String, double>{},
            ),
          );
        }

        if (items.isEmpty) {
          continue;
        }

        final payroll = PayrollModel(
          id: payrollId,
          projectId: projectId,
          generatedBy: 'admin_from_attendance',
          payrollPeriodStart: startOfMonth,
          payrollPeriodEnd: endOfMonth,
          items: items,
          totalAmount: totalAmount,
          createdAt: now,
          updatedAt: now,
        );

        await payrollDocRef.set(payroll.toJson());

        // Log payroll generation from attendance to audit trail (per project)
        await AuditLogService.instance.logAction(
          action: 'payroll_generated_from_attendance',
          projectId: projectId,
          details: {
            'payrollId': payrollId,
            'totalAmount': totalAmount,
            'itemsCount': items.length,
            'periodStart': startOfMonth.toIso8601String(),
            'periodEnd': endOfMonth.toIso8601String(),
          },
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payroll generated from attendance.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate payroll from attendance: $e'),
        ),
      );
    }
  }

  // Manual payroll generation has been removed; payroll is generated only
  // from site manager attendance and existing payroll documents.

  // Manual payroll UI helpers removed; payroll is fully driven by site
  // manager data and attendance.

  void _showFullWorkerPayrollTable(
    BuildContext context,
    String projectId,
    List<_WorkerPayrollEntry> entries,
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
                        'Worker payroll  Site: ${shortProjectId(projectId)}',
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
                    child: _buildWorkerPayrollDataTable(sheetContext, entries),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkerPayrollEntry {
  final PayrollItem item;
  final String payrollStatus;
  final String workerKey;

  _WorkerPayrollEntry({
    required this.item,
    required this.payrollStatus,
    required this.workerKey,
  });
}

class _ManualPayrollRowData {
  final TextEditingController nameController;
  final TextEditingController positionController;
  final TextEditingController ratePerHourController;
  final TextEditingController totalWorkHoursController;
  final TextEditingController totalAmountController;
  String projectId;
  String workerId;

  _ManualPayrollRowData()
    : nameController = TextEditingController(),
      positionController = TextEditingController(),
      ratePerHourController = TextEditingController(),
      totalWorkHoursController = TextEditingController(),
      totalAmountController = TextEditingController(),
      projectId = '',
      workerId = '';

  void dispose() {
    nameController.dispose();
    positionController.dispose();
    ratePerHourController.dispose();
    totalWorkHoursController.dispose();
    totalAmountController.dispose();
  }
}

class _AttendancePayrollAggregate {
  final String projectId;
  final String workerId;
  final String workerName;
  final String position;
  final String workerType;
  double hourlyRate;
  int daysPresent;
  double totalHours;

  _AttendancePayrollAggregate({
    required this.projectId,
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.workerType,
    required this.hourlyRate,
    required this.daysPresent,
    required this.totalHours,
  });
}

class _WeeklyAttendanceRow {
  final String workerName;
  final String position;
  final String workerType;
  final double rate;
  final Set<int> presentWeekdays; // DateTime.monday..DateTime.friday

  _WeeklyAttendanceRow({
    required this.workerName,
    required this.position,
    required this.workerType,
    required this.rate,
    required this.presentWeekdays,
  });
}

class _RecentPayout {
  final String workerName;
  final double amount;
  final DateTime date;

  _RecentPayout({
    required this.workerName,
    required this.amount,
    required this.date,
  });
}

class _AttendanceMonitoringPanel extends StatefulWidget {
  const _AttendanceMonitoringPanel();

  @override
  State<_AttendanceMonitoringPanel> createState() =>
      _AttendanceMonitoringPanelState();
}

class _AttendanceMonitoringPanelState
    extends State<_AttendanceMonitoringPanel> {
  DateTime _selectedDate = DateTime.now();
  bool _present = false;
  bool _absent = false;
  bool _onLeave = false;
  bool _late = false;

  List<AttendanceRecord> _availableWorkers = [];
  AttendanceRecord? _selectedWorker;

  @override
  void initState() {
    super.initState();
    _availableWorkers = _getWorkersForDate(_selectedDate);
    _loadWorkersFromFirestore(_selectedDate);
  }

  void _setStatusFromRecord(AttendanceRecord? record) {
    if (record == null) {
      _present = false;
      _absent = false;
      _onLeave = false;
      _late = false;
      return;
    }

    final remarks = (record.remarks ?? '').toLowerCase();
    final isLeave = !record.isPresent && remarks.contains('leave');
    final isLate = record.isPresent && remarks.contains('late');

    _present = record.isPresent;
    _onLeave = isLeave;
    _late = isLate;
    _absent = !record.isPresent && !isLeave;
  }

  void _updateForDate(DateTime date) {
    final workers = _getWorkersForDate(date);
    setState(() {
      _selectedDate = date;
      _availableWorkers = workers;
      _selectedWorker = null;
      _present = false;
      _absent = false;
      _onLeave = false;
      _late = false;
    });
    _loadWorkersFromFirestore(date);
  }

  List<AttendanceRecord> _getWorkersForDate(DateTime date) {
    final hive = HiveService.instance;
    final allAttendance = hive.getAllAttendance();

    final targetYear = date.year;
    final targetMonth = date.month;
    final targetDay = date.day;

    final Map<String, AttendanceRecord> workersByKey = {};

    for (final attendance in allAttendance) {
      final attDate = attendance.attendanceDate;
      if (attDate.year == targetYear &&
          attDate.month == targetMonth &&
          attDate.day == targetDay) {
        for (final record in attendance.records) {
          final key = '${record.workerId}_${record.workerName}';
          workersByKey.putIfAbsent(key, () => record);
        }
      }
    }

    final workers = workersByKey.values.toList()
      ..sort((a, b) => a.workerName.compareTo(b.workerName));
    return workers;
  }

  Future<void> _loadWorkersFromFirestore(DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final startIso = startOfDay.toIso8601String();
      final endIso = endOfDay.toIso8601String();

      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('attendance')
          .where('attendanceDate', isGreaterThanOrEqualTo: startIso)
          .where('attendanceDate', isLessThan: endIso)
          .get();

      final Map<String, AttendanceRecord> workersByKey = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final attendance = AttendanceModel.fromJson({'id': doc.id, ...data});

        for (final record in attendance.records) {
          final key = '${record.workerId}_${record.workerName}';
          workersByKey.putIfAbsent(key, () => record);
        }
      }

      final workers = workersByKey.values.toList()
        ..sort((a, b) => a.workerName.compareTo(b.workerName));

      if (!mounted) return;

      setState(() {
        _availableWorkers = workers;
        if (_selectedWorker != null) {
          final selectedKey =
              '${_selectedWorker!.workerId}_${_selectedWorker!.workerName}';
          _selectedWorker = workersByKey[selectedKey];
          _setStatusFromRecord(_selectedWorker);
        }
      });
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted) return;
    if (picked != null) {
      _updateForDate(picked);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    final day = date.day.toString().padLeft(2, '0');
    return '$month $day ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Monitoring',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.darkGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.mediumGray.withAlpha(60)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: AppTheme.primaryBlue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: _availableWorkers.isEmpty
                      ? Text(
                          'No workers with attendance yet',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<AttendanceRecord>(
                            isExpanded: true,
                            hint: const Text('Worker'),
                            value: _selectedWorker,
                            items: _availableWorkers
                                .map(
                                  (record) =>
                                      DropdownMenuItem<AttendanceRecord>(
                                        value: record,
                                        child: Text(record.workerName),
                                      ),
                                )
                                .toList(),
                            onChanged: (record) {
                              setState(() {
                                _selectedWorker = record;
                                _setStatusFromRecord(record);
                              });
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.mediumGray.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: AppTheme.primaryBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(_selectedDate),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppTheme.darkGray),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _present,
            onChanged: (value) {
              setState(() {
                _present = value ?? false;
                if (_present) {
                  _absent = false;
                  _onLeave = false;
                }
              });
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryBlue,
            checkColor: AppTheme.white,
            title: const Text('Present'),
          ),
          CheckboxListTile(
            value: _absent,
            onChanged: (value) {
              setState(() {
                _absent = value ?? false;
                if (_absent) {
                  _present = false;
                  _onLeave = false;
                }
              });
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryBlue,
            checkColor: AppTheme.white,
            title: const Text('Absent'),
          ),
          CheckboxListTile(
            value: _onLeave,
            onChanged: (value) {
              setState(() {
                _onLeave = value ?? false;
                if (_onLeave) {
                  _present = false;
                  _absent = false;
                }
              });
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryBlue,
            checkColor: AppTheme.white,
            title: const Text('On leave'),
          ),
          CheckboxListTile(
            value: _late,
            onChanged: (value) {
              setState(() {
                _late = value ?? false;
              });
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryBlue,
            checkColor: AppTheme.white,
            title: const Text('Late'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.deepBlue,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {},
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}

DataRow _buildWorkerPayrollRow(
  BuildContext context,
  PayrollItem item,
  String payrollStatus,
) {
  final hoursWorked = item.totalHours;
  final hourlyRate = hoursWorked > 0 ? item.grossPay / hoursWorked : 0.0;
  final totalPayroll = item.netPay;

  String statusLabel;
  Color statusColor;
  Color statusBackground;

  switch (payrollStatus) {
    case 'paid':
      statusLabel = 'Paid';
      statusColor = AppTheme.softGreen;
      statusBackground = AppTheme.softGreen.withAlpha(32);
      break;
    case 'returned':
      statusLabel = 'On hold';
      statusColor = AppTheme.warningOrange;
      statusBackground = AppTheme.warningOrange.withAlpha(32);
      break;
    default:
      statusLabel = 'Pending';
      statusColor = AppTheme.primaryBlue;
      statusBackground = AppTheme.primaryBlue.withAlpha(32);
      break;
  }

  return DataRow(
    cells: [
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            item.workerName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      DataCell(
        Text(item.position, style: Theme.of(context).textTheme.bodySmall),
      ),
      DataCell(
        Text(
          formatHours(hoursWorked),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          formatCurrency(hourlyRate),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          formatCurrency(totalPayroll),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: statusBackground,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            statusLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _buildWeeklyAttendanceTable(
  BuildContext context,
  List<_WeeklyAttendanceRow> weeklyRows,
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
        DataColumn(label: Text('No.')),
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Position / Skill')),
        DataColumn(label: Text('Rate')),
        DataColumn(label: Text('Mon')),
        DataColumn(label: Text('Tue')),
        DataColumn(label: Text('Wed')),
        DataColumn(label: Text('Thu')),
        DataColumn(label: Text('Fri')),
      ],
      rows: [
        for (int i = 0; i < weeklyRows.length; i++)
          DataRow(
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    weeklyRows[i].workerName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    '${weeklyRows[i].position}  ${weeklyRows[i].workerType == 'skilled' ? 'Skilled' : 'Labor'}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              DataCell(
                Text(
                  weeklyRows[i].rate.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              DataCell(
                Icon(
                  weeklyRows[i].presentWeekdays.contains(DateTime.monday)
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: weeklyRows[i].presentWeekdays.contains(DateTime.monday)
                      ? AppTheme.softGreen
                      : AppTheme.mediumGray,
                ),
              ),
              DataCell(
                Icon(
                  weeklyRows[i].presentWeekdays.contains(DateTime.tuesday)
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color:
                      weeklyRows[i].presentWeekdays.contains(DateTime.tuesday)
                      ? AppTheme.softGreen
                      : AppTheme.mediumGray,
                ),
              ),
              DataCell(
                Icon(
                  weeklyRows[i].presentWeekdays.contains(DateTime.wednesday)
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color:
                      weeklyRows[i].presentWeekdays.contains(DateTime.wednesday)
                      ? AppTheme.softGreen
                      : AppTheme.mediumGray,
                ),
              ),
              DataCell(
                Icon(
                  weeklyRows[i].presentWeekdays.contains(DateTime.thursday)
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color:
                      weeklyRows[i].presentWeekdays.contains(DateTime.thursday)
                      ? AppTheme.softGreen
                      : AppTheme.mediumGray,
                ),
              ),
              DataCell(
                Icon(
                  weeklyRows[i].presentWeekdays.contains(DateTime.friday)
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: weeklyRows[i].presentWeekdays.contains(DateTime.friday)
                      ? AppTheme.softGreen
                      : AppTheme.mediumGray,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

void _showWeeklyAttendanceBottomSheet(
  BuildContext context,
  List<_WeeklyAttendanceRow> weeklyRows,
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
                      'This week attendance checklist',
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
                  child: _buildWeeklyAttendanceTable(sheetContext, weeklyRows),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildValidationChip(BuildContext context, String status) {
  Color backgroundColor;
  Color textColor;
  String label;

  switch (status) {
    case 'validated':
      backgroundColor = AppTheme.softGreen.withAlpha(32);
      textColor = AppTheme.softGreen;
      label = 'Validated';
      break;
    case 'needs_review':
      backgroundColor = AppTheme.warningOrange.withAlpha(32);
      textColor = AppTheme.warningOrange;
      label = 'Needs review';
      break;
    default:
      backgroundColor = AppTheme.mediumGray.withAlpha(32);
      textColor = AppTheme.mediumGray;
      label = status;
      break;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Widget _buildAttendanceSummarySection(
  BuildContext context, {
  required int presentCount,
  required int absentCount,
  required int onLeaveCount,
  required int lateCount,
  required List<_WeeklyAttendanceRow> weeklyRows,
}) {
  String workerLabel(int count) => '$count Workers';

  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance summary',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Overview of worker attendance this month.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
        ),
        const SizedBox(height: 12),
        _buildAttendanceSummaryRow(
          context,
          icon: Icons.check_circle,
          iconColor: AppTheme.softGreen,
          label: 'Present',
          value: workerLabel(presentCount),
        ),
        const SizedBox(height: 8),
        _buildAttendanceSummaryRow(
          context,
          icon: Icons.cancel,
          iconColor: AppTheme.errorRed,
          label: 'Absent',
          value: workerLabel(absentCount),
        ),
        const SizedBox(height: 8),
        _buildAttendanceSummaryRow(
          context,
          icon: Icons.airline_seat_individual_suite,
          iconColor: AppTheme.warningOrange,
          label: 'On leave',
          value: workerLabel(onLeaveCount),
        ),
        const SizedBox(height: 8),
        _buildAttendanceSummaryRow(
          context,
          icon: Icons.schedule,
          iconColor: AppTheme.primaryBlue,
          label: 'Late arrivals',
          value: workerLabel(lateCount),
        ),
        const SizedBox(height: 16),
        if (weeklyRows.isNotEmpty) ...[
          Text(
            'This week attendance checklist',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showWeeklyAttendanceBottomSheet(context, weeklyRows),
            child: _buildWeeklyAttendanceTable(context, weeklyRows),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Tap table to view weekly checklist',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    ),
  );
}

Widget _buildAttendanceSummaryRow(
  BuildContext context, {
  required IconData icon,
  required Color iconColor,
  required String label,
  required String value,
}) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: iconColor.withAlpha(24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
      ),
    ],
  );
}

Widget _buildRecentPayrollPayoutsSection(
  BuildContext context,
  List<_RecentPayout> payouts,
) {
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent payroll payouts',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Latest payroll disbursements and adjustments.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
        ),
        const SizedBox(height: 12),
        if (payouts.isEmpty)
          Text(
            'No payroll payouts recorded yet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
          )
        else ...[
          for (final payout in payouts) ...[
            _buildRecentPayoutRow(context, payout),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: payouts.isEmpty ? null : () {},
            icon: const Icon(Icons.receipt_long),
            label: const Text('View all transactions'),
          ),
        ),
      ],
    ),
  );
}

Widget _buildRecentPayoutRow(BuildContext context, _RecentPayout payout) {
  final date = payout.date;
  final dateText =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.deepBlue.withAlpha(16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person, size: 18, color: AppTheme.deepBlue),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              payout.workerName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              dateText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.softGreen.withAlpha(32),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Paid',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.softGreen,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        formatCurrency(payout.amount),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.primaryBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
