import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/firebase_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;

    return AdminGlassScaffold(
      title: 'Executive Dashboard',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(RouteNames.notifications),
        ),
        IconButton(
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () => context.push(RouteNames.adminAuditTrail),
        ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.dashboard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSmartInsightCard(context),
          const SizedBox(height: 14),
          _buildKpiRow(context, hive),
          const SizedBox(height: 14),
          _buildProjectActivityCard(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSmartInsightCard(BuildContext context) {
    return const SmartInsightCard(
      title: 'Smart Insight',
      message:
          'Based on current SPI of 1.05, Project Alpha will complete 4 days ahead.\nReallocate 2 idle team members to Project Beta?',
    );
  }

  Widget _buildKpiRow(BuildContext context, HiveService hive) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1000;
        const kpiHeight = 150.0;

        final List<Widget> cards = [
          _KpiCard(
            title: 'Net Margin',
            value: '18.2%',
            accent: const Color(0xFF2DD4BF),
          ),
          _KpiCard(
            title: 'Cost Performance Index (CPI)',
            value: '1.10',
            badgeText: 'On Track',
            badgeColor: const Color(0xFF22C55E),
            accent: const Color(0xFF22C55E),
          ),
          _KpiCard(
            title: 'Schedule Performance Index (SPI)',
            value: '0.05',
            accent: const Color(0xFFF97316),
          ),
        ];

        Widget wrapKpiCard(Widget child) {
          return SizedBox(height: kpiHeight, child: child);
        }

        final weatherCard = wrapKpiCard(_buildWeatherRiskCard(context, hive));

        if (isNarrow) {
          return Column(
            children: [
              ...cards.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: wrapKpiCard(c),
                ),
              ),
              weatherCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: wrapKpiCard(cards[0])),
            const SizedBox(width: 12),
            Expanded(child: wrapKpiCard(cards[1])),
            const SizedBox(width: 12),
            Expanded(child: wrapKpiCard(cards[2])),
            const SizedBox(width: 12),
            Expanded(child: weatherCard),
          ],
        );
      },
    );
  }

  Widget _buildWeatherRiskCard(BuildContext context, HiveService hive) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<WeatherNow>(
        future: WeatherService.instance.getCurrentWeatherByCity('Manila,PH'),
        builder: (context, snapshot) {
          final temp = snapshot.data?.temperatureC;
          final description = snapshot.data?.description ?? '';
          final workHours = (temp == null)
              ? 7
              : (temp <= 26 ? 9 : (temp <= 30 ? 8 : 7));
          final label = snapshot.connectionState == ConnectionState.waiting
              ? 'Loading…'
              : (description.isEmpty ? 'Weather Risk' : 'Weather Risk');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.wb_sunny_outlined,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      temp == null ? '—' : '${temp.toStringAsFixed(0)}°C',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Workable Hours:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '$workHours / 10',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (workHours / 10).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  color: const Color(0xFF2DD4BF),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProjectActivityCard(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: _buildActivityProjectSummaryCard(context),
    );
  }

  Future<List<Map<String, dynamic>>> _loadProjectActivitySummary() async {
    final firebase = FirebaseService.instance;

    final projectsSnap = await firebase.projectsCollection.get();
    final disbursementsSnap = await firebase.disbursementsCollection.get();

    final Map<String, double> expensesByProject = {};
    for (final doc in disbursementsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final projectId = (data['projectId'] ?? '').toString();
      if (projectId.isEmpty) continue;
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
      expensesByProject[projectId] =
          (expensesByProject[projectId] ?? 0) + amount;
    }

    final List<Map<String, dynamic>> summaries = [];
    for (final doc in projectsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final projectId = doc.id;

      final name = (data['name'] ?? 'Untitled').toString();
      final status = (data['status'] ?? 'unknown').toString();
      final siteManagerName = (data['siteManagerName'] ?? '').toString();
      final progressRaw = data['progressPercentage'];
      final double progress;
      if (progressRaw is num) {
        progress = progressRaw.toDouble();
      } else if (progressRaw is String) {
        final cleaned = progressRaw.replaceAll('%', '').trim();
        progress = double.tryParse(cleaned) ?? 0.0;
      } else {
        progress = 0.0;
      }

      final budgetRaw = data['contractAmount'] ?? data['approvedBudget'];
      final double budget;
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
      final expenses = expensesByProject[projectId] ?? 0.0;

      summaries.add({
        'name': name,
        'status': status,
        'progress': progress,
        'budget': budget,
        'expenses': expenses,
        'siteManagerName': siteManagerName,
      });
    }

    return summaries;
  }

  Widget _buildActivityProjectSummaryCard(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadProjectActivitySummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading activity project summary…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return AppCard(
            child: Text(
              'Failed to load activity project summary.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
            ),
          );
        }

        final summaries = snapshot.data ?? const <Map<String, dynamic>>[];
        if (summaries.isEmpty) {
          return AppCard(
            child: Text(
              'No projects found yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
            ),
          );
        }

        final visible = summaries.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project Activity Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showFullProjectActivityTable(context, summaries),
              child: GlassDataTableTheme(
                child: _buildProjectActivityDataTable(context, visible),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Tap table to view all projects',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProjectActivityDataTable(
    BuildContext context,
    List<Map<String, dynamic>> rows,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dividerThickness: 0,
        columnSpacing: 16,
        dataRowMinHeight: 88,
        dataRowMaxHeight: 128,
        columns: const [
          DataColumn(label: Text('Project')),
          DataColumn(label: Text('Site manager')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Progress')),
          DataColumn(label: Text('Budget & expense %')),
          DataColumn(label: Text('AI Health')),
        ],
        rows: [for (final item in rows) _buildProjectSummaryRow(context, item)],
      ),
    );
  }

  void _showFullProjectActivityTable(
    BuildContext context,
    List<Map<String, dynamic>> summaries,
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
                        'All projects activity',
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
                      child: _buildProjectActivityDataTable(
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

  DataRow _buildProjectSummaryRow(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final name = (item['name'] ?? 'Untitled').toString();
    final siteManagerName = (item['siteManagerName'] ?? '').toString();
    final status = (item['status'] ?? 'unknown').toString();
    final progress = (item['progress'] ?? 0.0) as double;
    final budget = (item['budget'] ?? 0.0) as double;
    final expenses = (item['expenses'] ?? 0.0) as double;

    String healthLabel;
    Color healthColor;
    Color statusColor;

    if (budget <= 0 && expenses <= 0) {
      healthLabel = 'No data';
      healthColor = AppTheme.mediumGray;
    } else {
      final utilization = budget <= 0
          ? 0.0
          : (expenses / budget).clamp(0.0, 2.0);
      if (utilization < 0.7) {
        healthLabel = 'Healthy';
        healthColor = AppTheme.primaryBlue;
      } else if (utilization <= 1.0) {
        healthLabel = 'Watch';
        healthColor = AppTheme.accentYellow;
      } else {
        healthLabel = 'Over budget';
        healthColor = AppTheme.errorRed;
      }
    }

    final normalizedStatus = status.toLowerCase();
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
    if (status.isEmpty) {
      formattedStatus = '—';
    } else {
      formattedStatus = status[0].toUpperCase() + status.substring(1);
    }

    final double utilization = budget <= 0
        ? 0.0
        : (expenses / budget).clamp(0.0, 2.0);
    final double utilizationPercent = budget <= 0
        ? 0.0
        : (utilization * 100).clamp(0.0, 999.0);

    final siteManagerLabel = siteManagerName.isEmpty
        ? 'Unassigned'
        : siteManagerName;

    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.business,
                    size: 16,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Text(
            siteManagerLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mediumGray,
                ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              formattedStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (progress / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  color: const Color(0xFF2DD4BF),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${progress.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.75),
                    ),
              ),
            ],
          ),
        ),
        DataCell(
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  budget <= 0
                      ? 'Budget: —'
                      : 'Budget: ${budget.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withValues(alpha: 0.75),
                      ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: budget <= 0
                      ? 0.0
                      : (expenses / budget).clamp(0.0, 1.0),
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  color: const Color(0xFF2DD4BF),
                ),
                const SizedBox(height: 2),
                Text(
                  budget <= 0
                      ? 'Expense: —'
                      : 'Expense: ${expenses.toStringAsFixed(0)} (${utilizationPercent.toStringAsFixed(0)}%)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Text(
            healthLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: healthColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.accent,
    this.badgeText,
    this.badgeColor,
  });

  final String title;
  final String value;
  final Color accent;
  final String? badgeText;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (badgeText != null && badgeText!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accent).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (badgeColor ?? accent).withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    badgeText!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badgeColor ?? accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 2,
            width: 48,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
