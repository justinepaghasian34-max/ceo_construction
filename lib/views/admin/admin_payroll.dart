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
  const AdminPayroll({
    super.key,
    this.showSidebar = true,
    this.showBottomNav = true,
    this.sidebarMode = AdminSidebarMode.full,
  });

  final bool showSidebar;
  final bool showBottomNav;
  final AdminSidebarMode sidebarMode;

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
      showSidebar: widget.showSidebar,
      sidebarMode: widget.sidebarMode,
      bottomNavigationBar: widget.showBottomNav
          ? const AdminBottomNavBar(
              current: AdminNavItem.payroll,
            )
          : null,
      child: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load payroll data: ${snapshot.error}',
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
          final Map<String, String> activeWorkerNameByKey = {};
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
              if (item.workerName.trim().isNotEmpty) {
                activeWorkerNameByKey[workerKey] = item.workerName.trim();
              }
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

          final now = DateTime.now();
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 1);

          final attendanceQuery = FirebaseFirestore.instance
              .collectionGroup('attendance')
              .limit(400);

          return StreamBuilder<QuerySnapshot>(
            stream: attendanceQuery.snapshots(),
            builder: (context, attendanceSnap) {
              if (attendanceSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Unable to load attendance from Firestore: ${attendanceSnap.error}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.warningOrange),
                    ),
                  ),
                );
              }
              final attendanceDocs = attendanceSnap.data?.docs ?? const [];
              final attendanceForPayroll = attendanceDocs
                  .map((doc) {
                    final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
                        <String, dynamic>{};
                    return AttendanceModel.fromJson({'id': doc.id, ...data});
                  })
                  .where((attendance) {
                    final d = attendance.attendanceDate;
                    return !d.isBefore(startOfMonth) && d.isBefore(endOfMonth);
                  })
                  .toList();

              final Map<String, _AttendanceWorkerSummary> attendanceSummary = {};
              for (final attendance in attendanceForPayroll) {
                final day = DateTime(
                  attendance.attendanceDate.year,
                  attendance.attendanceDate.month,
                  attendance.attendanceDate.day,
                );
                for (final record in attendance.records) {
                  final hasDayFlags = record.monPresent ||
                      record.tuePresent ||
                      record.wedPresent ||
                      record.thuPresent ||
                      record.friPresent ||
                      record.satPresent;
                  final isPresent = record.isPresent || hasDayFlags;
                  if (!isPresent) continue;

                  final key =
                      '${attendance.projectId}_${record.workerId.isNotEmpty ? record.workerId : record.workerName}';
                  final existing = attendanceSummary[key];
                  if (existing == null) {
                    attendanceSummary[key] = _AttendanceWorkerSummary(
                      projectId: attendance.projectId,
                      workerId: record.workerId,
                      workerName: record.workerName,
                      position: record.position,
                      rate: record.rate,
                      attendedDays: {day},
                    );
                  } else {
                    existing.attendedDays.add(day);
                    if (existing.position.trim().isEmpty &&
                        record.position.trim().isNotEmpty) {
                      existing.position = record.position;
                    }
                    if (existing.rate <= 0 && record.rate > 0) {
                      existing.rate = record.rate;
                    }
                    if (existing.workerName.trim().isEmpty &&
                        record.workerName.trim().isNotEmpty) {
                      existing.workerName = record.workerName;
                    }
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.instance.projectsCollection.snapshots(),
                builder: (context, projectsSnap) {
                  final Map<String, String> projectNameById = {};
                  final projectDocs = projectsSnap.data?.docs ?? const [];
                  for (final doc in projectDocs) {
                    final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
                        <String, dynamic>{};
                    final name = (data['name'] ?? '').toString().trim();
                    projectNameById[doc.id] =
                        name.isNotEmpty ? name : doc.id;
                  }

                  String siteLabel(String projectId) {
                    final name = projectNameById[projectId];
                    if (name != null && name.isNotEmpty) return name;
                    return shortProjectId(projectId);
                  }

                  final pendingProjectEntries = itemsByProject.entries.toList()
                    ..sort(
                      (a, b) => siteLabel(a.key)
                          .toLowerCase()
                          .compareTo(siteLabel(b.key).toLowerCase()),
                    );

                  if (projectsSnap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Unable to load projects: ${projectsSnap.error}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.warningOrange),
                        ),
                      ),
                    );
                  }

                  if (!projectsSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

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
                  _sectionHeading(
                    context,
                    title: 'Overview',
                    subtitle: 'Totals across every project in this payroll period',
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      void showSummarySheet({
                        required String title,
                        required Widget child,
                      }) {
                        showCenteredAdminDialog<void>(
                          context: context,
                          maxWidth: 420,
                          maxHeightFactor: 0.7,
                          builder: (dialogContext) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  adminDialogTitleRow(
                                    context: dialogContext,
                                    title: title,
                                  ),
                                  const SizedBox(height: 8),
                                  Flexible(child: child),
                                ],
                              ),
                            );
                          },
                        );
                      }

                      void showTotalPayrollDetails() {
                        final paidTotal = (totalPayroll - pendingPayoutTotal)
                            .clamp(0.0, double.infinity)
                            .toDouble();
                        showSummarySheet(
                          title: 'Total payroll cost',
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Total payroll'),
                                trailing: Text(
                                  formatCurrency(totalPayroll),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Paid payouts'),
                                trailing: Text(
                                  formatCurrency(paidTotal),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Pending payouts'),
                                trailing: Text(
                                  formatCurrency(pendingPayoutTotal),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      void showActiveWorkersDetails() {
                        final names = activeWorkerNameByKey.values.toSet().toList()
                          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                        showSummarySheet(
                          title: 'Active workers',
                          child: names.isEmpty
                              ? const Center(child: Text('No active workers yet.'))
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: names.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (ctx, i) {
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.10),
                                        child: Text(
                                          names[i].isNotEmpty ? names[i][0].toUpperCase() : '?',
                                          style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      title: Text(names[i]),
                                    );
                                  },
                                ),
                        );
                      }

                      void showPendingPayoutsDetails() {
                        final entries = itemsByProject.entries.toList()
                          ..sort((a, b) => siteLabel(a.key).compareTo(siteLabel(b.key)));

                        showSummarySheet(
                          title: 'Pending payouts',
                          child: entries.isEmpty
                              ? const Center(child: Text('No pending payouts.'))
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (ctx, i) {
                                    final projectId = entries[i].key;
                                    final workers = entries[i].value;
                                    final siteTotal = workers.fold<double>(0, (a, b) => a + b.item.netPay);
                                    return AppCard(
                                      padding: const EdgeInsets.all(12),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _showFullWorkerPayrollTable(
                                          context,
                                          projectId,
                                          workers,
                                          projectName: siteLabel(projectId),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  siteLabel(projectId),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${workers.length} worker(s) pending',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: AppTheme.mediumGray,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                formatCurrency(siteTotal),
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.w800,
                                                      color: AppTheme.primaryBlue,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Icon(Icons.chevron_right, color: AppTheme.mediumGray),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        );
                      }

                      void showOvertimeDetails() {
                        final Map<String, double> overtimeByWorker = {};
                        for (final projectEntry in aggregatedByProject.entries) {
                          for (final e in projectEntry.value.values) {
                            final h = e.item.overtimeHours;
                            if (h <= 0) continue;
                            overtimeByWorker[e.workerKey] = (overtimeByWorker[e.workerKey] ?? 0) + h;
                          }
                        }
                        final rows = overtimeByWorker.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));

                        showSummarySheet(
                          title: 'Overtime hours',
                          child: rows.isEmpty
                              ? const Center(child: Text('No overtime recorded.'))
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (ctx, i) {
                                    final key = rows[i].key;
                                    final name = activeWorkerNameByKey[key] ?? key;
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Text(
                                        '${formatHours(rows[i].value)} hrs',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryBlue,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                        );
                      }

                      Widget buildStatCard({
                        required IconData icon,
                        required Color iconColor,
                        required String label,
                        required String value,
                        VoidCallback? onTap,
                      }) {
                        return AppCard(
                          padding: const EdgeInsets.all(16),
                          onTap: onTap,
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
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
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
                        onTap: showTotalPayrollDetails,
                      );

                      final workersCard = buildStatCard(
                        icon: Icons.groups,
                        iconColor: AppTheme.primaryBlue,
                        label: 'Active workers',
                        value: activeWorkerIds.length.toString(),
                        onTap: showActiveWorkersDetails,
                      );

                      final pendingCard = buildStatCard(
                        icon: Icons.pending_actions,
                        iconColor: AppTheme.warningOrange,
                        label: 'Pending payouts',
                        value: formatCurrency(pendingPayoutTotal),
                        onTap: showPendingPayoutsDetails,
                      );

                      final overtimeCard = buildStatCard(
                        icon: Icons.access_time,
                        iconColor: AppTheme.accentYellow,
                        label: 'Overtime hours',
                        value: '${formatHours(totalOvertimeHours)} hrs',
                        onTap: showOvertimeDetails,
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
                  _sectionHeading(
                    context,
                    title: 'Generate payroll',
                    subtitle:
                        'Create pending payouts from this month’s attendance records',
                  ),
                  _generatePayrollActionCard(
                    context,
                    hasAttendance: attendanceForPayroll.isNotEmpty,
                    onGenerate: () =>
                        _generatePayrollFromAttendance(attendanceForPayroll),
                  ),
                  _sectionHeading(
                    context,
                    title: 'Pending payroll by project',
                    subtitle: pendingProjectEntries.isEmpty
                        ? 'No unpaid payroll yet'
                        : '${pendingProjectEntries.length} project${pendingProjectEntries.length == 1 ? '' : 's'} with unpaid workers',
                  ),
                  if (pendingProjectEntries.isEmpty)
                    _emptyHint(
                      context,
                      'No pending payroll yet. Generate from attendance, or wait for site records.',
                    )
                  else
                    for (final entry in pendingProjectEntries)
                      _projectPayrollCard(
                        context,
                        projectId: entry.key,
                        projectName: siteLabel(entry.key),
                        workers: entry.value,
                        validationStatus:
                            validationStatusByProject[entry.key],
                      ),
                  if (attendanceSummary.isNotEmpty) ...[
                    _sectionHeading(
                      context,
                      title: 'Attendance this month',
                      subtitle: 'Days present grouped by project',
                    ),
                    _buildAttendanceSummarySection(
                      context,
                      summaries: attendanceSummary.values.toList(),
                      siteLabel: siteLabel,
                    ),
                  ],
                  _sectionHeading(
                    context,
                    title: 'Recent payouts',
                    subtitle: 'Latest paid disbursements',
                  ),
                  _buildRecentPayrollPayoutsSection(context, visiblePayouts),
                    ],
                  ),
                ),
              );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.mediumGray,
            ),
      ),
    );
  }

  Widget _generatePayrollActionCard(
    BuildContext context, {
    required bool hasAttendance,
    required VoidCallback onGenerate,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasAttendance
                    ? 'Attendance is ready for this month'
                    : 'No attendance recorded this month',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                hasAttendance
                    ? 'Generate unpaid payroll per project from present workers.'
                    : 'Payroll can be generated once site attendance is submitted.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      height: 1.35,
                    ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: hasAttendance ? onGenerate : null,
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: const Text('Generate from attendance'),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.deepBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_available_outlined,
                        color: AppTheme.deepBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.deepBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: AppTheme.deepBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: text),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _projectPayrollCard(
    BuildContext context, {
    required String projectId,
    required String projectName,
    required List<_WorkerPayrollEntry> workers,
    String? validationStatus,
  }) {
    final preview = workers.take(4).toList();
    final remaining = workers.length - preview.length;
    final total = workers.fold<double>(0, (acc, e) => acc + e.item.netPay);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.deepBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.apartment_outlined,
                  size: 18,
                  color: AppTheme.deepBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workers.length} worker${workers.length == 1 ? '' : 's'}  ·  ${formatCurrency(total)} pending',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                  ],
                ),
              ),
              if (validationStatus != null && validationStatus.isNotEmpty)
                _buildValidationChip(context, validationStatus),
            ],
          ),
          const SizedBox(height: 12),
          for (final worker in preview) _workerPreviewRow(context, worker),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '+ $remaining more worker${remaining == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showFullWorkerPayrollTable(
                  context,
                  projectId,
                  workers,
                  projectName: projectName,
                ),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('View details'),
              ),
              FilledButton.icon(
                onPressed: () => _submitProjectPayroll(projectId),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Submit payroll'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _workerPreviewRow(BuildContext context, _WorkerPayrollEntry entry) {
    final item = entry.item;
    final name = item.workerName.trim().isEmpty ? 'Worker' : item.workerName;
    final status = entry.payrollStatus.trim().isEmpty
        ? 'pending'
        : entry.payrollStatus.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.deepBlue.withValues(alpha: 0.1),
            child: Text(
              name[0].toUpperCase(),
              style: const TextStyle(
                color: AppTheme.deepBlue,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  [
                    if (item.position.trim().isNotEmpty) item.position.trim(),
                    formatHours(item.regularHours + item.overtimeHours),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCurrency(item.netPay),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryBlue,
                    ),
              ),
              Text(
                status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummarySection(
    BuildContext context, {
    required List<_AttendanceWorkerSummary> summaries,
    required String Function(String projectId) siteLabel,
  }) {
    final grouped = <String, List<_AttendanceWorkerSummary>>{};
    for (final summary in summaries) {
      grouped.putIfAbsent(summary.projectId, () => []).add(summary);
    }
    final projectIds = grouped.keys.toList()
      ..sort(
        (a, b) => siteLabel(a).toLowerCase().compareTo(siteLabel(b).toLowerCase()),
      );

    return Column(
      children: [
        for (final projectId in projectIds)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteLabel(projectId),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 8),
                for (final worker in (grouped[projectId]!
                  ..sort(
                    (a, b) => a.workerName
                        .toLowerCase()
                        .compareTo(b.workerName.toLowerCase()),
                  )))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            worker.workerName.trim().isEmpty
                                ? 'Worker'
                                : worker.workerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${worker.attendedDays.length} day${worker.attendedDays.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.mediumGray,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (worker.rate > 0) ...[
                          const SizedBox(width: 12),
                          Text(
                            formatCurrency(worker.rate),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.deepBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  DataRow _buildWorkerPayrollRow(
    BuildContext context,
    PayrollItem item,
    String payrollStatus,
  ) {
    final status = payrollStatus.toLowerCase();
    final statusLabel = status.isEmpty ? 'pending' : status;

    Color statusColor;
    Color statusBackground;
    if (statusLabel == 'paid') {
      statusColor = AppTheme.softGreen;
      statusBackground = AppTheme.softGreen.withAlpha(32);
    } else if (statusLabel == 'needs_review') {
      statusColor = AppTheme.warningOrange;
      statusBackground = AppTheme.warningOrange.withAlpha(32);
    } else {
      statusColor = AppTheme.mediumGray;
      statusBackground = AppTheme.mediumGray.withAlpha(32);
    }

    return DataRow(
      cells: [
        DataCell(
          Text(
            item.workerName,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        DataCell(
          Text(
            item.position,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            formatHours(item.regularHours + item.overtimeHours),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            item.regularHours > 0 ? formatCurrency(item.grossPay / item.regularHours) : '-',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            formatCurrency(item.netPay),
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

  Widget _buildWorkerPayrollDataTable(
    BuildContext context,
    List<_WorkerPayrollEntry> entries,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
          ),
        );
      },
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

      if (!mounted) return;

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

      if (totalAmount > 0) {
        await firebase.disbursementsCollection.add({
          'projectId': projectId,
          'amount': totalAmount,
          'type': 'payroll',
          'subject': 'Payroll payout',
          'workerCount': totalWorkers,
          'paidAt': now.toIso8601String(),
          'createdAt': now.toIso8601String(),
        });
      }

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
    List<_WorkerPayrollEntry> entries, {
    String? projectName,
  }) {
    showCenteredAdminDialog<void>(
      context: context,
      maxWidth: 900,
      maxHeightFactor: 0.8,
      builder: (dialogContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              adminDialogTitleRow(
                context: dialogContext,
                title:
                    'Worker payroll — ${projectName ?? shortProjectId(projectId)}',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _buildWorkerPayrollDataTable(dialogContext, entries),
              ),
            ],
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

class _AttendanceWorkerSummary {
  final String projectId;
  String workerId;
  String workerName;
  String position;
  double rate;
  final Set<DateTime> attendedDays;

  _AttendanceWorkerSummary({
    required this.projectId,
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.rate,
    required this.attendedDays,
  });
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

  List<AttendanceRecord> _getAbsentWorkersForDate(DateTime date) {
    final workers = _getWorkersForDate(date);
    final absent = workers.where((w) => !w.isPresent).toList()
      ..sort((a, b) => a.workerName.compareTo(b.workerName));
    return absent;
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
    final absentWorkers = _getAbsentWorkersForDate(_selectedDate);
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
          const SizedBox(height: 12),
          Text(
            'Absent workers (${absentWorkers.length})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mediumGray,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (absentWorkers.isEmpty)
            Text(
              'No absences for this date.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mediumGray),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: absentWorkers
                  .take(20)
                  .map(
                    (w) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.errorRed.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        w.workerName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.errorRed,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  )
                  .toList(),
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

Widget _buildRecentPayrollPayoutsSection(
  BuildContext context,
  List<_RecentPayout> payouts,
) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            onPressed: payouts.isEmpty
                ? null
                : () => _showAllTransactionsSheet(context, payouts),
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

  return InkWell(
    onTap: () => _showPayoutDetailsSheet(context, payout),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.deepBlue.withAlpha(16),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.person, size: 18, color: AppTheme.deepBlue),
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
      ),
    ),
  );
}

void _showPayoutDetailsSheet(BuildContext context, _RecentPayout payout) {
  final date = payout.date;
  final dateText =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  showCenteredAdminDialog<void>(
    context: context,
    maxWidth: 420,
    maxHeightFactor: 0.55,
    builder: (dialogContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            adminDialogTitleRow(
              context: dialogContext,
              title: 'Payout details',
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppTheme.lightGray,
                child: Icon(Icons.person, color: AppTheme.deepBlue),
              ),
              title: Text(payout.workerName),
              subtitle: Text(dateText),
              trailing: Text(
                formatCurrency(payout.amount),
                style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryBlue,
                    ),
              ),
            ),
            const Divider(height: 16),
            Text(
              'Status: Paid',
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
    },
  );
}

void _showAllTransactionsSheet(
  BuildContext context,
  List<_RecentPayout> payouts,
) {
  final sorted = [...payouts]..sort((a, b) => b.date.compareTo(a.date));

  showCenteredAdminDialog<void>(
    context: context,
    maxWidth: 520,
    maxHeightFactor: 0.75,
    builder: (dialogContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            adminDialogTitleRow(
              context: dialogContext,
              title: 'All transactions',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final payout = sorted[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      payout.workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${payout.date.year.toString().padLeft(4, '0')}-'
                      '${payout.date.month.toString().padLeft(2, '0')}-'
                      '${payout.date.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: Text(
                      formatCurrency(payout.amount),
                      style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryBlue,
                          ),
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _showPayoutDetailsSheet(context, payout);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
