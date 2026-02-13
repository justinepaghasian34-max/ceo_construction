import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../services/hive_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/status_chip.dart';

class SiteManagerReportsScreen extends ConsumerWidget {
  const SiteManagerReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;

    final allReports = user == null
        ? hive.getAllDailyReports()
        : hive.getDailyReportsByReporter(user.id);

    final reports = allReports
      ..sort((a, b) => b.reportDate.compareTo(a.reportDate));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Daily Reports',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: reports.isEmpty
          ? Center(
              child: Text(
                'No daily reports created yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final report = reports[index];
                final date = report.reportDate;
                final dateText = '${date.day}/${date.month}/${date.year}';

                return AppCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.description,
                        color: AppTheme.deepBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateText,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Project: ${report.projectId}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${report.workAccomplishments.length} work items, ${report.issues.length} issues',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ReportStatusChip(
                        reportStatus: report.status,
                        isSmall: true,
                      ),
                      const SizedBox(width: 4),
                      SyncStatusChip(
                        syncStatus: report.syncStatus,
                        isSmall: true,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
