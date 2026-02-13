import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/status_chip.dart';

class MaterialDeliveryScreen extends StatelessWidget {
  const MaterialDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deliveries = HiveService.instance.getAllDeliveries();

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
          'Material Delivery',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: deliveries.isEmpty
          ? Center(
              child: Text(
                'No delivery records yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final delivery = deliveries[index];
                final description = (delivery['description'] ?? 'Delivery').toString();
                final supplier = (delivery['supplier'] ?? '').toString();
                final projectId = (delivery['projectId'] ?? '').toString();
                final syncStatus = (delivery['syncStatus'] ?? AppConstants.syncStatusPending).toString();

                return AppCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_shipping,
                        color: AppTheme.deepBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              description,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            if (supplier.isNotEmpty)
                              Text(
                                'Supplier: $supplier',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                    ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Project: $projectId',
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
