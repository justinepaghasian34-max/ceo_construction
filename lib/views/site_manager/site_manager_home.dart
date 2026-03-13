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
import '../../widgets/common/app_button.dart';
import '../../widgets/common/status_chip.dart';
import 'widgets/site_manager_bottom_nav.dart';
import 'widgets/site_manager_card.dart';

class SiteManagerHome extends ConsumerStatefulWidget {
  final bool showBottomNav;
  final bool showBack;

  const SiteManagerHome({
    super.key,
    this.showBottomNav = false,
    this.showBack = true,
  });

  @override
  ConsumerState<SiteManagerHome> createState() => _SiteManagerHomeState();
}

class _SiteManagerHomeState extends ConsumerState<SiteManagerHome> {
  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _navigateFromDrawer(BuildContext context, String route) {
    Navigator.of(context).pop();
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final syncStats = SyncService.instance.getSyncStats();
    final hasProject = user != null && user.assignedProjects.isNotEmpty;

    final isNarrow = MediaQuery.of(context).size.width < 980;
    final hasDrawer = isNarrow;

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      drawer: hasDrawer ? _SiteManagerDrawer() : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: hasDrawer
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  tooltip: 'Menu',
                ),
              )
            : (widget.showBack
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null),
        title: const Text('Site Manager'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SyncButton(
              onPressed: () => _refreshData(),
              isSyncing: syncStats.isSyncing,
              pendingCount: syncStats.totalPending,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () {
                context.push(RouteNames.notifications);
              },
              tooltip: 'Notifications',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              onTap: () {
                context.push(RouteNames.profile);
              },
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.white.withValues(alpha: 0.20),
                  foregroundColor: AppTheme.white,
                  backgroundImage: (user?.profileImageUrl ?? '').trim().isEmpty
                      ? null
                      : NetworkImage(user!.profileImageUrl!.trim()),
                  child: ((user?.profileImageUrl ?? '').trim().isEmpty)
                      ? Text(
                          ((user?.firstName ?? '').trim().isNotEmpty
                                  ? user!.firstName.trim()[0]
                                  : 'S')
                              .toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _buildDashboardBanner(user),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildActiveProjectCard(user),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDashboardStatusCards(user),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildLatestSiteUpdateCard(user),
                  const SizedBox(height: 20),
                  _buildRecentReportsCard(user),
                  const SizedBox(height: 20),
                  _buildSyncStatusCard(syncStats),
                  const SizedBox(height: 20),
                  _buildMilestoneTimelineCard(user),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.showBottomNav
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _handleProjectDependentAction(hasProject, () {
                context.push(RouteNames.projectProgressUpdate);
              }),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Upload Site Progress'),
              backgroundColor: AppTheme.deepBlue,
              foregroundColor: AppTheme.white,
            ),
      bottomNavigationBar:
          widget.showBottomNav ? const SiteManagerBottomNav(currentIndex: 0) : null,
    );
  }

  Widget _buildDashboardBanner(UserModel? user) {
    final name = user == null
        ? 'Site Manager'
        : (user.firstName.isEmpty ? 'Site Manager' : user.firstName);
    final projectId = (user != null && user.assignedProjects.isNotEmpty)
        ? user.assignedProjects.first
        : null;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(22),
      ),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/unnamed.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(-0.35, -0.25),
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.expand();
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.deepBlueDark.withValues(alpha: 0.82),
                      AppTheme.deepBlue.withValues(alpha: 0.52),
                      AppTheme.deepBlue.withValues(alpha: 0.18),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Welcome, $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Let's get to work!",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (projectId != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Project: $projectId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveProjectCard(UserModel? user) {
    if (user == null || user.assignedProjects.isEmpty) {
      return const SizedBox.shrink();
    }

    final projectId = user.assignedProjects.first;
    final projectFuture =
        FirebaseService.instance.projectsCollection.doc(projectId).get();

    return FutureBuilder<DocumentSnapshot>(
      future: projectFuture,
      builder: (context, snapshot) {
        String projectName = projectId;
        double progress = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final rawName = (data?['name'] ?? data?['projectName'] ?? '').toString();
          if (rawName.trim().isNotEmpty) {
            projectName = rawName.trim();
          }

          final rawProgress = data?['progressPercentage'];
          if (rawProgress is num) progress = rawProgress.toDouble();
          if (rawProgress is String) {
            progress =
                double.tryParse(rawProgress.replaceAll('%', '').trim()) ?? 0;
          }
        }

        progress = progress.clamp(0, 100);

        return SiteManagerCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Active Project',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.darkGray,
                          ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGray,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppTheme.deepBlue.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          size: 14,
                          color: AppTheme.warningOrange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Sunny 30°C',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.darkGray,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                projectName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.deepBlueDark,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 10,
                        backgroundColor: AppTheme.lightGray,
                        valueColor:
                            const AlwaysStoppedAnimation(AppTheme.deepBlue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.deepBlue,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppTheme.mediumGray,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Project ID: $projectId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardStatusCards(UserModel? user) {
    final hiveService = HiveService.instance;
    final userId = user?.id;

    final dailyReportsCount = userId == null
        ? hiveService.totalDailyReports
        : hiveService.getDailyReportsByReporter(userId).length;

    final attendanceCount = userId == null
        ? hiveService.totalAttendanceRecords
        : hiveService.getAttendanceByRecorder(userId).length;

    Widget metricCard({
      required IconData icon,
      required Color tone,
      required String label,
      required String metric,
      required String subtitle,
    }) {
      return SiteManagerCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tone, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              metric,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkGray,
                    height: 1.0,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: metricCard(
            icon: Icons.description_outlined,
            tone: AppTheme.deepBlue,
            label: "Today's Reports",
            metric: dailyReportsCount.toString(),
            subtitle: 'Submitted',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: metricCard(
            icon: Icons.people_outline,
            tone: AppTheme.softGreen,
            label: 'Workers Present',
            metric: attendanceCount.toString(),
            subtitle: 'On site',
          ),
        ),
      ],
    );
  }

  Widget _buildMilestoneTimelineCard(UserModel? user) {
    final steps = <Map<String, dynamic>>[
      {
        'title': 'Site Preparation',
        'status': 'completed',
        'progress': 100.0,
        'confidence': 95.0,
      },
      {
        'title': 'Foundation Works',
        'status': 'completed',
        'progress': 100.0,
        'confidence': 92.0,
      },
      {
        'title': 'Structural Framing',
        'status': 'in_progress',
        'progress': 70.0,
        'confidence': 82.0,
      },
      {
        'title': 'Roofing Installation',
        'status': 'pending',
        'progress': 0.0,
        'confidence': null,
      },
      {
        'title': 'Finishing Works',
        'status': 'pending',
        'progress': 0.0,
        'confidence': null,
      },
    ];

    IconData iconFor(String s) {
      switch (s) {
        case 'completed':
          return Icons.check_circle;
        case 'in_progress':
          return Icons.hourglass_bottom;
        default:
          return Icons.radio_button_unchecked;
      }
    }

    Color colorFor(String s) {
      switch (s) {
        case 'completed':
          return AppTheme.softGreen;
        case 'in_progress':
          return AppTheme.warningOrange;
        default:
          return AppTheme.mediumGray;
      }
    }

    return SiteManagerCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Project Timeline',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          ...List.generate(steps.length, (index) {
            final s = steps[index];
            final isLast = index == steps.length - 1;
            return Column(
              children: [
                _buildTimelineMilestoneRow(
                  context,
                  step: s,
                  iconFor: iconFor,
                  colorFor: colorFor,
                ),
                if (!isLast) const SizedBox(height: 10),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineMilestoneRow(
    BuildContext context, {
    required Map<String, dynamic> step,
    required IconData Function(String) iconFor,
    required Color Function(String) colorFor,
  }) {
    final status = (step['status'] ?? '').toString();
    final progress = (step['progress'] is num)
        ? (step['progress'] as num).toDouble()
        : 0.0;
    final confidence = (step['confidence'] is num)
        ? (step['confidence'] as num).toDouble()
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(iconFor(status), color: colorFor(status), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (step['title'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    status == 'completed'
                        ? 'Completed'
                        : (status == 'in_progress' ? 'In Progress' : 'Pending'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.mediumGray),
                  ),
                  const SizedBox(width: 10),
                  if (status != 'pending')
                    Text(
                      'Progress: ${progress.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                ],
              ),
              if (confidence != null) ...[
                const SizedBox(height: 2),
                Text(
                  'AI Confidence: ${confidence.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLatestSiteUpdateCard(UserModel? user) {
    if (user == null || user.assignedProjects.isEmpty) {
      return const SizedBox.shrink();
    }

    final projectId = user.assignedProjects.first;
    final query = FirebaseService.instance.aiAnalysisCollection
        .where('kind', isEqualTo: 'govtrack_progress_report')
        .where('projectId', isEqualTo: projectId)
        .limit(10);

    return SiteManagerCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest Site Photo',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = (snapshot.data?.docs ?? const []).toList()
                ..sort((a, b) {
                  final ad = (a.data() as Map?)?.cast<String, dynamic>() ?? {};
                  final bd = (b.data() as Map?)?.cast<String, dynamic>() ?? {};
                  final at = ad['createdAt'];
                  final bt = bd['createdAt'];
                  DateTime? aDate;
                  if (at is Timestamp) aDate = at.toDate();
                  DateTime? bDate;
                  if (bt is Timestamp) bDate = bt.toDate();
                  final aMillis = aDate?.millisecondsSinceEpoch ?? 0;
                  final bMillis = bDate?.millisecondsSinceEpoch ?? 0;
                  return bMillis.compareTo(aMillis);
                });

              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGray,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          color: AppTheme.mediumGray),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No uploads yet. Tap “Upload Site Progress”.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final data =
                  (docs.first.data() as Map?)?.cast<String, dynamic>() ?? {};
              final imageUrl = (data['imageUrl'] ?? '').toString().trim();
              final submittedBy =
                  (data['submittedByName'] ?? '').toString().trim();
              final createdAt = data['createdAt'];
              final progress = data['progressPercent'];

              String dateText = '';
              if (createdAt is Timestamp) {
                final d = createdAt.toDate();
                dateText =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              }

              final pctText = (progress is num)
                  ? '${progress.toStringAsFixed(0)}%'
                  : '—';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      color: AppTheme.lightGray,
                      child: imageUrl.isEmpty
                          ? const Center(child: Icon(Icons.image_outlined))
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          submittedBy.isEmpty ? 'Uploaded by: —' : 'Uploaded by: $submittedBy',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ),
                      if (dateText.isNotEmpty)
                        Text(
                          dateText,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.deepBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.deepBlue.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'AI Estimated Progress',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.mediumGray,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Text(
                          pctText,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.deepBlue,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusCard(SyncStats syncStats) {
    if (syncStats.totalPending == 0) {
      return SiteManagerCard(
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

    return SiteManagerCard(
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

  Widget _buildRecentReportsCard(UserModel? user) {
    final hive = HiveService.instance;
    final userId = user?.id;

    final allReports = userId == null
        ? hive.getAllDailyReports()
        : hive.getDailyReportsByReporter(userId);

    allReports.sort((a, b) => b.reportDate.compareTo(a.reportDate));
    final recentReports = allReports.take(3).toList();

    return SiteManagerCard(
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

class _SiteManagerDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_SiteManagerHomeState>();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('GovTrack AI'),
              onTap: () {
                state?._navigateFromDrawer(context, RouteNames.govTrackAi);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Reports'),
              onTap: () {
                state?._navigateFromDrawer(context, '/site-manager/reports');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Queue'),
              onTap: () {
                state?._navigateFromDrawer(context, RouteNames.syncQueue);
              },
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () {
                state?._navigateFromDrawer(context, RouteNames.profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Notifications'),
              onTap: () {
                state?._navigateFromDrawer(context, RouteNames.notifications);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                state?._navigateFromDrawer(context, RouteNames.settings);
              },
            ),
          ],
        ),
      ),
    );
  }
}
