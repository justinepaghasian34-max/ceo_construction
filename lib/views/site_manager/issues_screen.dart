import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';

class IssuesScreen extends StatelessWidget {
  const IssuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = HiveService.instance.getAllDailyReports()
        .where((r) => r.issues.isNotEmpty)
        .toList()
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
          'Issues & NCR',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: reports.isEmpty
          ? Center(
              child: Text(
                'No issues reported yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
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
                final firstIssue = report.issues.first;

                return AppCard(
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
                        '${report.issues.length} issue(s)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        firstIssue,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
