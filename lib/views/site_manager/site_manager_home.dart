import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../models/user_model.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/status_chip.dart';

class SiteManagerHome extends ConsumerStatefulWidget {
  const SiteManagerHome({super.key});

  @override
  ConsumerState<SiteManagerHome> createState() => _SiteManagerHomeState();
}

class _SiteManagerHomeState extends ConsumerState<SiteManagerHome> {
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final syncStats = SyncService.instance.getSyncStats();
    final hasProject = user != null && user.assignedProjects.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Site Manager'),
            if (user != null)
              Text(
                'Welcome, ${user.firstName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.white.withAlpha(200),
                ),
              ),
          ],
        ),
        actions: [
          SyncButton(
            onPressed: () => _refreshData(),
            isSyncing: syncStats.isSyncing,
            pendingCount: syncStats.totalPending,
          ),
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
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Site manager overview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Monitor sync status, project assignment, and recent activity.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            const SizedBox(height: 16),
            _buildSyncStatusCard(syncStats),
            const SizedBox(height: 16),
            _buildCurrentProjectCard(user),
            const SizedBox(height: 16),
            _buildQuickStatsGrid(user),
            const SizedBox(height: 16),
            _buildMainActionsGrid(user),
            const SizedBox(height: 16),
            _buildRecentReportsCard(user),
          ],
        ),
      ),
      floatingActionButton: AppFloatingActionButton(
        onPressed: () => _handleProjectDependentAction(hasProject, () {
          context.push(RouteNames.dailyReport);
        }),
        icon: Icons.add,
        tooltip: 'New Daily Report',
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: _onBottomNavTap,
        backgroundColor: AppTheme.white,
        selectedItemColor: AppTheme.deepBlue,
        unselectedItemColor: AppTheme.deepBlue,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync),
            label: 'Sync',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentProjectCard(UserModel? user) {
    if (user == null || user.assignedProjects.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(
              Icons.location_off,
              color: AppTheme.mediumGray,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No project assigned',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final projectId = user.assignedProjects.first;
    final hive = HiveService.instance;

    // Compute last report date for this Site Manager and project from local data
    final projectReports = hive
        .getDailyReportsByProject(projectId)
        .where((report) => report.reporterId == user.id)
        .toList()
      ..sort((a, b) => b.reportDate.compareTo(a.reportDate));

    final DateTime? lastReportDate =
        projectReports.isNotEmpty ? projectReports.first.reportDate : null;

    // Compute pending sync items for this project (daily reports + attendance)
    final pendingReports = hive.getPendingSyncReportsForProject(projectId).length;
    final pendingAttendance =
        hive.getPendingSyncAttendanceForProject(projectId).length;
    final pendingTotal = pendingReports + pendingAttendance;

    final String lastReportText = lastReportDate == null
        ? 'No daily reports created yet for this project.'
        : 'Last daily report: ${lastReportDate.day}/${lastReportDate.month}/${lastReportDate.year}';

    final String pendingText = pendingTotal == 0
        ? 'No pending sync items for this project.'
        : 'Pending sync items (this project): $pendingTotal';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseService.instance.projectsCollection.doc(projectId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AppCard(
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.deepBlue),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Loading project...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }

        String title;
        String subtitle;
        double? progress;

        if (!snapshot.hasData || !snapshot.data!.exists) {
          title = 'Project: $projectId';
          subtitle = 'Assigned project';
        } else {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final name = (data?['name'] ?? 'Project $projectId').toString();
          final location = (data?['location'] ?? '').toString();
          progress = (data?['progressPercentage'] ?? 0).toDouble();
          title = name;
          subtitle = location.isNotEmpty
              ? 'Project ID: $projectId • $location'
              : 'Project ID: $projectId';
        }

        return AppCard(
          child: Row(
            children: [
              Icon(
                Icons.location_on,
                color: AppTheme.deepBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Progress: ${((progress ?? 0).clamp(0, 100)).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.deepBlue,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastReportText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pendingText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: pendingTotal == 0
                                ? AppTheme.softGreen
                                : AppTheme.warningOrange,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncStatusCard(SyncStats syncStats) {
    if (syncStats.totalPending == 0) {
      return AppCard(
        backgroundColor: AppTheme.softGreen.withAlpha(25),
        child: Row(
          children: [
            Icon(
              Icons.cloud_done,
              color: AppTheme.softGreen,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All data synced',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.softGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Your data is up to date',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      backgroundColor: AppTheme.warningOrange.withAlpha(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                syncStats.isSyncing ? Icons.sync : Icons.cloud_off,
                color: AppTheme.warningOrange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncStats.isSyncing ? 'Syncing data...' : 'Pending sync',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.warningOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${syncStats.totalPending} items waiting to sync',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                    ),
                  ],
                ),
              ),
              if (!syncStats.isSyncing)
                AppButton(
                  text: 'Sync Now',
                  onPressed: _syncData,
                  backgroundColor: AppTheme.warningOrange,
                ),
            ],
          ),
          if (syncStats.totalPending > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (syncStats.pendingDailyReports > 0) ...[
                  StatusChip(
                    label: '${syncStats.pendingDailyReports} Reports',
                    status: StatusType.warning,
                    isSmall: true,
                  ),
                  const SizedBox(width: 8),
                ],
                if (syncStats.pendingAttendance > 0) ...[
                  StatusChip(
                    label: '${syncStats.pendingAttendance} Attendance',
                    status: StatusType.warning,
                    isSmall: true,
                  ),
                  const SizedBox(width: 8),
                ],
                if (syncStats.pendingQueueItems > 0)
                  StatusChip(
                    label: '${syncStats.pendingQueueItems} Others',
                    status: StatusType.warning,
                    isSmall: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickStatsGrid(UserModel? user) {
    final hiveService = HiveService.instance;
    final userId = user?.id;

    final dailyReportsCount = userId == null
        ? hiveService.totalDailyReports
        : hiveService.getDailyReportsByReporter(userId).length;

    final attendanceCount = userId == null
        ? hiveService.totalAttendanceRecords
        : hiveService.getAttendanceByRecorder(userId).length;

    return Row(
      children: [
        Expanded(
          child: StatsCard(
            title: 'Daily Reports',
            value: dailyReportsCount.toString(),
            icon: Icons.description,
            iconColor: AppTheme.deepBlue,
            subtitle: 'Total created',
            onTap: () => context.push('/site-manager/reports'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatsCard(
            title: 'Attendance',
            value: attendanceCount.toString(),
            icon: Icons.people,
            iconColor: AppTheme.softGreen,
            subtitle: 'Records logged',
            onTap: () => context.push(RouteNames.attendance),
          ),
        ),
      ],
    );
  }

  Widget _buildMainActionsGrid(UserModel? user) {
    final hasProject = user != null && user.assignedProjects.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildActionTile(
              title: 'Daily Report',
              subtitle: 'Create new report',
              icon: Icons.description,
              color: AppTheme.deepBlue,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.dailyReport);
              }),
            ),
            _buildActionTile(
              title: 'Attendance',
              subtitle: 'Log worker hours',
              icon: Icons.people,
              color: AppTheme.softGreen,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.attendance);
              }),
            ),
            _buildActionTile(
              title: 'Project Progress',
              subtitle: 'Update status',
              icon: Icons.timeline,
              color: AppTheme.deepBlue,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.projectProgressUpdate);
              }),
            ),
            _buildActionTile(
              title: 'Material Usage',
              subtitle: 'Track materials',
              icon: Icons.inventory,
              color: AppTheme.warningOrange,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.materialUsage);
              }),
            ),
            _buildActionTile(
              title: 'Deliveries',
              subtitle: 'Material delivery',
              icon: Icons.local_shipping,
              color: AppTheme.deepBlue,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.materialDelivery);
              }),
            ),
            _buildActionTile(
              title: 'Material Request',
              subtitle: 'Subject for admin',
              icon: Icons.assignment_outlined,
              color: AppTheme.softGreen,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.materialRequest);
              }),
            ),
            _buildActionTile(
              title: 'Issues',
              subtitle: 'Report problems',
              icon: Icons.warning,
              color: AppTheme.errorRed,
              onTap: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.issues);
              }),
            ),
            _buildActionTile(
              title: 'Sync Queue',
              subtitle: 'View pending sync',
              icon: Icons.sync,
              color: AppTheme.mediumGray,
              onTap: () => context.push(RouteNames.syncQueue),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AppCard(
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReportsCard(UserModel? user) {
    final hive = HiveService.instance;
    final userId = user?.id;

    final allReports = userId == null
        ? hive.getAllDailyReports()
        : hive.getDailyReportsByReporter(userId);

    allReports.sort((a, b) => b.reportDate.compareTo(a.reportDate));
    final recentReports = allReports.take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent Reports',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/site-manager/reports'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recentReports.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 48,
                    color: AppTheme.mediumGray,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No reports created yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    text: 'Create First Report',
                    onPressed: () => context.push(RouteNames.dailyReport),
                    backgroundColor: AppTheme.softGreen,
                  ),
                ],
              ),
            )
          else
            ...recentReports.map((report) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description,
                    color: AppTheme.deepBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${report.reportDate.day}/${report.reportDate.month}/${report.reportDate.year}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${report.workAccomplishments.length} accomplishments',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ReportStatusChip(
                    reportStatus: report.status,
                    isSmall: true,
                  ),
                  const SizedBox(width: 8),
                  SyncStatusChip(
                    syncStatus: report.syncStatus,
                    isSmall: true,
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Future<void> _syncData() async {
    final result = await SyncService.instance.syncPendingData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppTheme.softGreen : AppTheme.errorRed,
        ),
      );
      
      setState(() {}); // Refresh the UI
    }
  }

  Future<void> _refreshData() async {
    await _syncData();
    // Refresh the current user so assignedProjects reflects latest Admin assignments
    await AuthService.instance.refreshUserData();
    if (mounted) {
      ref.invalidate(currentUserProvider);
    }
  }

  void _onBottomNavTap(int index) {
    if (_currentTabIndex == index) {
      return;
    }

    setState(() {
      _currentTabIndex = index;
    });

    switch (index) {
      case 0:
        // Home - already on SiteManagerHome
        break;
      case 1:
        // Reports
        context.push('/site-manager/reports');
        break;
      case 2:
        // Sync
        context.push(RouteNames.syncQueue);
        break;
    }
  }

  void _handleProjectDependentAction(bool hasProject, VoidCallback action) {
    if (hasProject) {
      action();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'No project assigned. Please contact your administrator to be assigned to a project before using this feature.',
        ),
        backgroundColor: AppTheme.errorRed,
      ),
    );
  }
}
