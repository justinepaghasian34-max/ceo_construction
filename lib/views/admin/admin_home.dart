import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/firebase_service.dart';
import '../../services/archive_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/motion_widgets.dart';
import '../../widgets/common/storage_network_image.dart';
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
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.dashboard,
      ),
      child: StaggerColumn(
        interval: const Duration(milliseconds: 150),
        itemDuration: const Duration(milliseconds: 820),
        children: [
          _buildSmartInsightCard(context),
          const SizedBox(height: 14),
          _buildKpiRow(context, hive),
          const SizedBox(height: 14),
          _buildSiteWeatherMapCard(context),
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
            icon: Icons.trending_up_rounded,
            onTap: () => context.push(RouteNames.adminFinancialMonitoring),
          ),
          _KpiCard(
            title: 'Cost Performance Index (CPI)',
            value: '1.10',
            badgeText: 'On Track',
            badgeColor: const Color(0xFF22C55E),
            accent: const Color(0xFF22C55E),
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => context.push(RouteNames.adminFinancialMonitoring),
          ),
          _KpiCard(
            title: 'Schedule Performance Index (SPI)',
            value: '0.05',
            accent: const Color(0xFFF97316),
            icon: Icons.schedule_rounded,
            onTap: () => context.push(RouteNames.adminProgressReports),
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
    const borderRadius = 16.0;
    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<WeatherNow>(
        future: WeatherService.instance.getCurrentWeatherByCity('Manila,PH'),
        builder: (context, snapshot) {
          final temp = snapshot.data?.temperatureC;
          final description = snapshot.data?.description ?? '';
          final workHours =
              (temp == null) ? 7 : (temp <= 26 ? 9 : (temp <= 30 ? 8 : 7));
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteNames.adminWeatherForecast),
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      ),
    );
  }

  Widget _buildSiteWeatherMapCard(BuildContext context) {
    const borderRadius = 16.0;

    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.thunderstorm_outlined,
                    size: 18, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Site Weather Map',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.softGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Live',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.softGreen,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'View live weather conditions at all project sites on an '
            'interactive map. Rain alerts are sent automatically.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mediumGray,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WeatherConditionDot(
                  color: AppTheme.warningOrange, label: 'Sunny'),
              const SizedBox(width: 12),
              _WeatherConditionDot(
                  color: AppTheme.mediumGray, label: 'Cloudy'),
              const SizedBox(width: 12),
              _WeatherConditionDot(
                  color: const Color(0xFF3B82F6), label: 'Raining'),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppTheme.mediumGray.withValues(alpha: 0.5),
              ),
            ],
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteNames.adminSiteWeatherMap),
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
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
        final cleaned =
            rawAmount.replaceAll(',', '').replaceAll('₱', '').trim();
        amount = double.tryParse(cleaned) ?? 0.0;
      } else {
        amount = 0.0;
      }
      expensesByProject[projectId] =
          (expensesByProject[projectId] ?? 0) + amount;
    }

    final coverByProjectId = <String, String>{};
    final coverByProjectName = <String, String>{};
    final latestAt = <String, DateTime>{};
    try {
      final reportsSnap = await firebase.aiAnalysisCollection
          .where(
            'kind',
            whereIn: const <String>[
              'govtrack_progress_report',
              'govtrack_image_progress_submit',
            ],
          )
          .get();
      for (final report in reportsSnap.docs) {
        final reportData = (report.data() as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final images = ProgressReportImages.extract(reportData);
        if (images.isEmpty) continue;
        final projectId = (reportData['projectId'] ?? '').toString();
        final projectName = (reportData['projectName'] ?? '').toString();
        DateTime created = DateTime.fromMillisecondsSinceEpoch(0);
        final rawCreated = reportData['createdAt'];
        if (rawCreated is Timestamp) created = rawCreated.toDate();
        if (rawCreated is DateTime) created = rawCreated;
        if (projectId.isNotEmpty) {
          final prev = latestAt[projectId];
          if (prev == null || created.isAfter(prev)) {
            latestAt[projectId] = created;
            coverByProjectId[projectId] = images.first;
          }
        }
        if (projectName.isNotEmpty) {
          final key = 'name:$projectName';
          final prev = latestAt[key];
          if (prev == null || created.isAfter(prev)) {
            latestAt[key] = created;
            coverByProjectName[projectName] = images.first;
          }
        }
      }
    } catch (_) {}

    final List<Map<String, dynamic>> summaries = [];
    for (final doc in projectsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (ArchiveService.isArchived(data)) continue;
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
        final cleaned =
            budgetRaw.replaceAll(',', '').replaceAll('₱', '').trim();
        budget = double.tryParse(cleaned) ?? 0.0;
      } else {
        budget = 0.0;
      }
      final expenses = expensesByProject[projectId] ?? 0.0;

      summaries.add({
        'id': projectId,
        'name': name,
        'status': status,
        'progress': progress,
        'budget': budget,
        'expenses': expenses,
        'siteManagerName': siteManagerName,
        'coverImage': coverByProjectId[projectId] ??
            coverByProjectName[name] ??
            '',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dividerThickness: 0,
              columnSpacing: 16,
              dataRowMinHeight: 88,
              dataRowMaxHeight: 128,
              columns: const [
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Resident Engineer')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Progress')),
                DataColumn(label: Text('Budget & expense %')),
                DataColumn(label: Text('AI Health')),
              ],
              rows: [
                for (final item in rows) _buildProjectSummaryRow(context, item),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullProjectActivityTable(
    BuildContext context,
    List<Map<String, dynamic>> summaries,
  ) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width * 0.88, 1100.0);
    final height = math.min(size.height * 0.88, 860.0);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close all projects activity',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: Material(
            color: Colors.white,
            elevation: 18,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_rounded,
                            color: AppTheme.deepBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All projects activity',
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _HorizontalProjectStrip(summaries: summaries),
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
      final utilization =
          budget <= 0 ? 0.0 : (expenses / budget).clamp(0.0, 2.0);
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

    final double utilization =
        budget <= 0 ? 0.0 : (expenses / budget).clamp(0.0, 2.0);
    final double utilizationPercent =
        budget <= 0 ? 0.0 : (utilization * 100).clamp(0.0, 999.0);

    final siteManagerLabel =
        siteManagerName.isEmpty ? 'Unassigned' : siteManagerName;

    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProjectCoverThumb(
                  source: (item['coverImage'] ?? '').toString(),
                  size: 48,
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
                  value:
                      budget <= 0 ? 0.0 : (expenses / budget).clamp(0.0, 1.0),
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
    required this.icon,
    this.badgeText,
    this.badgeColor,
    this.onTap,
  });

  final String title;
  final String value;
  final Color accent;
  final IconData icon;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const borderRadius = 16.0;
    final card = GlassCard(
      borderRadius: borderRadius,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const Spacer(),
              if (badgeText != null && badgeText!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accent).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
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
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.mediumGray,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 4,
              backgroundColor: accent.withValues(alpha: 0.12),
              color: accent,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: card,
        ),
      ),
    );
  }
}

class _HorizontalProjectStrip extends StatefulWidget {
  const _HorizontalProjectStrip({required this.summaries});

  final List<Map<String, dynamic>> summaries;

  @override
  State<_HorizontalProjectStrip> createState() =>
      _HorizontalProjectStripState();
}

class _HorizontalProjectStripState extends State<_HorizontalProjectStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final next = _scroll.offset + event.scrollDelta.dy + event.scrollDelta.dx;
    _scroll.jumpTo(
      next.clamp(0.0, _scroll.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = math.min(
          constraints.maxHeight - 36,
          math.max(420.0, constraints.maxWidth * 0.42),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.summaries.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Scroll left or right to see every site',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ),
            Expanded(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.summaries.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return _ProjectActivityTile(
                        item: widget.summaries[index],
                        size: tileSize,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProjectCoverThumb extends StatelessWidget {
  const _ProjectCoverThumb({required this.source, this.size = 48});

  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
        child: source.trim().isEmpty
            ? ColoredBox(
                color: AppTheme.lightGray,
                child: Icon(
                  Icons.apartment_outlined,
                  size: size * 0.42,
                  color: AppTheme.mediumGray,
                ),
              )
            : StorageNetworkImage(source: source, fit: BoxFit.cover),
      ),
    );
  }
}

class _ProjectActivityTile extends StatelessWidget {
  const _ProjectActivityTile({
    required this.item,
    this.size = 260,
  });

  final Map<String, dynamic> item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? 'Untitled').toString();
    final siteManagerName = (item['siteManagerName'] ?? '').toString();
    final status = (item['status'] ?? '').toString();
    final progress = (item['progress'] is num)
        ? (item['progress'] as num).toDouble()
        : 0.0;
    final budget = (item['budget'] is num)
        ? (item['budget'] as num).toDouble()
        : 0.0;
    final expenses = (item['expenses'] is num)
        ? (item['expenses'] as num).toDouble()
        : 0.0;
    final cover = (item['coverImage'] ?? '').toString();
    final formattedStatus = status.isEmpty
        ? '—'
        : status[0].toUpperCase() + status.substring(1);

    return Material(
      elevation: 5,
      shadowColor: Colors.black26,
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: cover.isEmpty
                  ? ColoredBox(
                      color: AppTheme.lightGray,
                      child: Icon(
                        Icons.apartment_outlined,
                        size: 42,
                        color: AppTheme.mediumGray,
                      ),
                    )
                  : StorageNetworkImage(source: cover, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    siteManagerName.isEmpty ? 'Unassigned' : siteManagerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          formattedStatus,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.softGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    budget <= 0
                        ? 'Budget: —'
                        : 'Budget: ${budget.toStringAsFixed(0)}  ·  Expense: ${expenses.toStringAsFixed(0)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherConditionDot extends StatelessWidget {
  const _WeatherConditionDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.mediumGray,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
