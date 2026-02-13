import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/status_chip.dart';

class MaterialUsageScreen extends StatelessWidget {
  const MaterialUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usages = HiveService.instance.getAllMaterialUsage();

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
          'Material Usage',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: usages.isEmpty
          ? Center(
              child: Text(
                'No material usage records yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: usages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final usage = usages[index];
                final materialName = (usage['materialName'] ?? 'Material').toString();
                final quantity = (usage['quantity'] ?? 0).toString();
                final unit = (usage['unit'] ?? '').toString();
                final projectId = (usage['projectId'] ?? '').toString();
                final reportId = (usage['reportId'] ?? '').toString();
                final syncStatus = (usage['syncStatus'] ?? AppConstants.syncStatusPending).toString();

                return AppCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory,
                        color: AppTheme.warningOrange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              materialName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty: $quantity $unit',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Project: $projectId • Report: $reportId',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SyncStatusChip(
                        syncStatus: syncStatus,
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
