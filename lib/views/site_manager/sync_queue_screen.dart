import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_button.dart';

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({super.key});

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> {
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final items = HiveService.instance.getAllSyncQueueItems();

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
          'Sync Queue',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppButton(
              text: _isSyncing ? 'Syncing...' : 'Sync Now',
              onPressed: _isSyncing ? null : _syncNow,
              backgroundColor: AppTheme.deepBlue,
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No items in sync queue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final type = (item['type'] ?? 'unknown').toString();
                    final status = (item['status'] ?? AppConstants.syncStatusPending).toString();
                    final data = (item['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                    final projectId = (data['projectId'] ?? '').toString();

                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Type: $type',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          if (projectId.isNotEmpty)
                            Text(
                              'Project: $projectId',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            'Status: $status',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.mediumGray,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
    });

    final result = await SyncService.instance.syncPendingData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppTheme.softGreen : AppTheme.errorRed,
      ),
    );

    setState(() {
      _isSyncing = false;
    });
  }
}
