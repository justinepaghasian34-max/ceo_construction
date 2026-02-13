import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../services/hive_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/status_chip.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;

    final allAttendance = user == null
        ? hive.getAllAttendance()
        : hive.getAttendanceByRecorder(user.id);

    final attendanceList = allAttendance
      ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

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
          'Attendance',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: attendanceList.isEmpty
          ? Center(
              child: Text(
                'No attendance records yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: attendanceList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final attendance = attendanceList[index];
                final date = attendance.attendanceDate;
                final dateText = '${date.day}/${date.month}/${date.year}';

                return AppCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.people,
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
                              'Project: ${attendance.projectId}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Present: ${attendance.presentWorkers} / ${attendance.totalWorkers} (${attendance.attendanceRate.toStringAsFixed(0)}%)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SyncStatusChip(
                        syncStatus: attendance.syncStatus,
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
