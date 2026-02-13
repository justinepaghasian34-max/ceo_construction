import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';

class CeoHome extends StatelessWidget {
  const CeoHome({super.key});

  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Executive Overview',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              context.push(RouteNames.notifications);
            },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              context.push(RouteNames.profile);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Executive overview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quick summary of reports, attendance, and material activity.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            const SizedBox(height: 16),
            _buildTopSummary(context, hive),
            const SizedBox(height: 16),
            _buildSecondarySummary(context, hive),
            const SizedBox(height: 16),
            _buildNavigationCards(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSummary(BuildContext context, HiveService hive) {
    return Row(
      children: [
        Expanded(
          child: StatsCard(
            title: 'Daily Reports',
            value: hive.totalDailyReports.toString(),
            icon: Icons.description,
            iconColor: AppTheme.deepBlue,
            subtitle: 'Total submitted',
            onTap: () => context.push(RouteNames.ceoReports),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatsCard(
            title: 'Attendance',
            value: hive.totalAttendanceRecords.toString(),
            icon: Icons.people,
            iconColor: AppTheme.softGreen,
            subtitle: 'Records logged',
            onTap: () => context.push(RouteNames.ceoReports),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondarySummary(BuildContext context, HiveService hive) {
    return Row(
      children: [
        Expanded(
          child: StatsCard(
            title: 'Material Usage',
            value: hive.totalMaterialUsageRecords.toString(),
            icon: Icons.inventory,
            iconColor: AppTheme.warningOrange,
            subtitle: 'Usage entries',
            onTap: () => context.push(RouteNames.ceoDashboard),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatsCard(
            title: 'Deliveries',
            value: hive.totalDeliveryRecords.toString(),
            icon: Icons.local_shipping,
            iconColor: AppTheme.deepBlue,
            subtitle: 'MDR records',
            onTap: () => context.push(RouteNames.ceoDashboard),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationCards(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 16),
        ActionCard(
          title: 'Executive Dashboard',
          subtitle: 'AI progress and overall status',
          icon: Icons.dashboard,
          iconColor: AppTheme.deepBlue,
          onTap: () => context.push(RouteNames.ceoDashboard),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Analytics',
          subtitle: 'Trends and performance',
          icon: Icons.show_chart,
          iconColor: AppTheme.softGreen,
          onTap: () => context.push(RouteNames.ceoAnalytics),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Reports',
          subtitle: 'Project and payroll summaries',
          icon: Icons.assessment,
          iconColor: AppTheme.warningOrange,
          onTap: () => context.push(RouteNames.ceoReports),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'History Timeline',
          subtitle: 'Latest critical events',
          icon: Icons.timeline,
          iconColor: AppTheme.mediumGray,
          onTap: () => context.push(RouteNames.adminHistory),
        ),
      ],
    );
  }
}
