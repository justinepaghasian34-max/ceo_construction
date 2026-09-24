import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_model.dart';
import '../../../services/firebase_service.dart';
import '../../../services/hive_service.dart';
import '../../../services/govtrack_project_progress_service.dart';
import '../../../services/sync_service.dart' show SyncStats;
import '../../../widgets/common/construction_progress_panel.dart';
import '../../../widgets/common/site_weather_conditions_card.dart';
import 'site_manager_card.dart';

/// Modern site-manager home dashboard (mockup-aligned layout).
class SiteManagerDashboardBody extends StatelessWidget {
  const SiteManagerDashboardBody({
    super.key,
    required this.user,
    required this.syncStats,
    required this.onRefresh,
    required this.onProjectAction,
  });

  final UserModel? user;
  final SyncStats syncStats;
  final Future<void> Function() onRefresh;
  final void Function(bool hasProject, VoidCallback action) onProjectAction;

  @override
  Widget build(BuildContext context) {
    final projectId = (user != null && user!.assignedProjects.isNotEmpty)
        ? user!.assignedProjects.first
        : null;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding:
            EdgeInsets.only(bottom: 88 + MediaQuery.of(context).padding.bottom),
        children: [
          _DashboardHeader(user: user, syncStats: syncStats),
          if (projectId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _HeroProjectCard(projectId: projectId),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _CompactWeatherTile(projectId: projectId),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _OverviewGrid(user: user, projectId: projectId),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _ProgressAndActivity(projectId: projectId),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _QuickActionsRow(
                onProjectAction: onProjectAction,
                hasProject: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _LatestPhotosRow(projectId: projectId),
            ),
            _AskGovtrackBar(),
          ] else
            Padding(
              padding: const EdgeInsets.all(24),
              child: SiteManagerCard(
                child: Text(
                  'No project assigned yet. Contact your admin to assign a project.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.user, required this.syncStats});

  final UserModel? user;
  final SyncStats syncStats;

  @override
  Widget build(BuildContext context) {
    final firstName = (user?.firstName ?? '').trim();
    final greetingName = firstName.isEmpty ? 'Resident Engineer' : firstName;
    final syncLabel = syncStats.isSyncing
        ? 'Syncing…'
        : (syncStats.totalPending > 0
            ? '${syncStats.totalPending} pending'
            : 'Synced');

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTheme.residentHeaderGradient,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Builder(
                  builder: (ctx) => IconButton(
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.menu, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: Text(
                    firstName.isEmpty ? greeting : '$greeting, $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push(RouteNames.notifications),
                  icon:
                      const Icon(Icons.notifications_none, color: Colors.white),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push(RouteNames.profile),
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      greetingName.isNotEmpty
                          ? greetingName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ProjectNameChip(
                    projectId:
                        (user != null && user!.assignedProjects.isNotEmpty)
                            ? user!.assignedProjects.first
                            : null,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        syncStats.totalPending > 0
                            ? Icons.cloud_sync
                            : Icons.check_circle,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        syncLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectNameChip extends StatelessWidget {
  const _ProjectNameChip({this.projectId});
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    if (projectId == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseService.instance.projectsCollection.doc(projectId).get(),
      builder: (context, snap) {
        var label = projectId!;
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>?;
          final name =
              (data?['name'] ?? data?['projectName'] ?? '').toString().trim();
          if (name.isNotEmpty) label = name;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.apartment_outlined,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white),
            ],
          ),
        );
      },
    );
  }
}

class _HeroProjectCard extends StatelessWidget {
  const _HeroProjectCard({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseService.instance.projectsCollection.doc(projectId).get(),
      builder: (context, snap) {
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final name = (data['name'] ?? data['projectName'] ?? 'Active Project')
            .toString();
        final subtitle =
            (data['description'] ?? 'Commercial Building Project').toString();
        final progressRaw = data['progressPercentage'] ?? data['progress'];
        final progress = progressRaw is num
            ? progressRaw.toDouble().clamp(0, 100)
            : (double.tryParse(
                    progressRaw?.toString().replaceAll('%', '').trim() ?? '') ??
                0);
        final target =
            _formatTargetDate(data['targetCompletion'] ?? data['endDate']);

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/unnamed.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: AppTheme.residentBlue),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 110,
                top: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.residentBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ACTIVE PROJECT',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                top: 24,
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress / 100,
                        strokeWidth: 7,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFF22C55E),
                      ),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  children: [
                    _HeroStatPill(
                        icon: Icons.people_outline,
                        label: 'Workers On Site'),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 52,
                child: Text(
                  'Target Completion: $target',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTargetDate(dynamic raw) {
  if (raw == null) return '—';
  if (raw is Timestamp) {
    final d = raw.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }
  final s = raw.toString();
  if (s.contains('T')) return s.split('T').first;
  return s;
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({this.user, this.projectId});
  final UserModel? user;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;
    final userId = user?.id;
    final reports = userId == null
        ? hive.totalDailyReports
        : hive.getDailyReportsByReporter(userId).length;
    final attendance = userId == null
        ? hive.totalAttendanceRecords
        : hive.getAttendanceByRecorder(userId).length;

    // Live material low-stock count from Hive — this project only
    final assignedProjectId = projectId;
    final allMaterials = hive.getAllMaterialInventory().where((m) {
      if (assignedProjectId == null || assignedProjectId.isEmpty) return false;
      return (m['projectId'] ?? '').toString() == assignedProjectId;
    }).toList();
    final lowStockCount = allMaterials.where((m) {
      final qty = m['quantity'] ?? m['currentStock'] ?? m['stock'];
      final min = m['minimumStock'] ?? m['minStock'] ?? m['threshold'] ?? 10;
      final q = qty is num ? qty.toDouble() : double.tryParse(qty?.toString() ?? '') ?? 0;
      final t = min is num ? min.toDouble() : double.tryParse(min?.toString() ?? '') ?? 10;
      return q <= t;
    }).length;

    // Open issues count from Hive requests
    final pendingRequests = hive.getAllMaterialRequests().where((r) {
      if ((r['status'] ?? '').toString().toLowerCase() != 'pending') {
        return false;
      }
      if (assignedProjectId == null || assignedProjectId.isEmpty) return false;
      return (r['projectId'] ?? '').toString() == assignedProjectId;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Overview',
          onSeeAll: () => context.push('/site-manager/reports'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OverviewTile(
                color: const Color(0xFF8B5CF6),
                icon: Icons.description_outlined,
                title: 'Daily Reports',
                value: '$reports',
                subtitle: 'Submitted Today',
                progress: reports > 0 ? 0.6 : 0.05,
                onTap: () => context.push(RouteNames.dailyReport),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverviewTile(
                color: const Color(0xFF22C55E),
                icon: Icons.people_outline,
                title: 'Workers On Site',
                value: '$attendance',
                subtitle: 'Present Today',
                progress: attendance > 0 ? 0.5 : 0.05,
                onTap: () => context.push(RouteNames.attendance),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OverviewTile(
                color: const Color(0xFFF97316),
                icon: Icons.inventory_2_outlined,
                title: 'Materials',
                value: lowStockCount > 0 ? '$lowStockCount' : 'OK',
                subtitle: lowStockCount > 0 ? 'Low Stock' : 'All stocked',
                progress: lowStockCount > 0 ? 0.25 : 0.9,
                onTap: () => context.push(RouteNames.siteManagerMaterials),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverviewTile(
                color: const Color(0xFFEF4444),
                icon: Icons.pending_actions_outlined,
                title: 'Requests',
                value: '$pendingRequests',
                subtitle: 'Pending',
                progress: pendingRequests > 0 ? 0.4 : 0.05,
                onTap: () => context.go(RouteNames.govTrackAi),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.progress,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.mediumGray,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.mediumGray),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: color.withValues(alpha: 0.15),
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AskGovtrackBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppTheme.residentBlue,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => context.go(RouteNames.govTrackAi),
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Ask BuildIQ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _ProgressAndActivity extends StatelessWidget {
  const _ProgressAndActivity({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectProgressSnapshot>(
      future: GovtrackProjectProgressService.load(projectId),
      builder: (context, snap) {
        final p = snap.data;
        final overall = p?.overallPercent ?? 0;
        final progressCard = ConstructionProgressPanel(
          title: 'Project Progress',
          overallPercent: overall,
          stages: ConstructionProgressPanel.dashboardStages(
            foundation: p?.foundation ?? 0,
            structural: p?.structural ?? 0,
            electrical: p?.electrical ?? 0,
            finishing: p?.finishing ?? 0,
          ),
        );

        return LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 700;
            final activityCard = _TodayActivityCard(projectId: projectId);

            if (stacked) {
              return Column(
                children: [
                  progressCard,
                  const SizedBox(height: 14),
                  activityCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: progressCard),
                const SizedBox(width: 14),
                Expanded(child: activityCard),
              ],
            );
          },
        );
      },
    );
  }
}

class _TodayActivityCard extends StatelessWidget {
  const _TodayActivityCard({required this.projectId});
  final String projectId;

  static const _fallback = [
    _ActivityItem(time: '08:00 AM', text: 'Workers checked in'),
    _ActivityItem(time: '09:30 AM', text: 'Cement delivery received'),
    _ActivityItem(time: '11:00 AM', text: 'Safety inspection completed'),
    _ActivityItem(time: '01:30 PM', text: 'Daily report submitted'),
  ];

  Future<List<_ActivityItem>> _load() async {
    final items = <_ActivityItem>[];
    try {
      final projectRef =
          FirebaseService.instance.projectsCollection.doc(projectId);
      final attendance = await projectRef
          .collection(AppConstants.attendanceSubCollection)
          .orderBy('createdAt', descending: true)
          .limit(2)
          .get();
      for (final doc in attendance.docs) {
        final d = (doc.data() as Map<String, dynamic>?) ?? {};
        final ts = d['createdAt'];
        items.add(_ActivityItem(
          time: _formatTime(ts),
          text: (d['status'] ?? 'Attendance recorded').toString(),
        ));
      }

      final reports = await projectRef
          .collection(AppConstants.dailyReportsSubCollection)
          .orderBy('createdAt', descending: true)
          .limit(2)
          .get();
      for (final doc in reports.docs) {
        final d = (doc.data() as Map<String, dynamic>?) ?? {};
        items.add(_ActivityItem(
          time: _formatTime(d['createdAt']),
          text: 'Daily report submitted',
        ));
      }
    } catch (_) {}

    if (items.isEmpty) return _fallback;
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items.take(4).toList();
  }

  static String _formatTime(dynamic ts) {
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    if (dt == null) return '--:--';
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ActivityItem>>(
      future: _load(),
      builder: (context, snap) {
        final items = snap.data ?? _fallback;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Today's Activity",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(RouteNames.attendance),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.residentBlue,
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    child: const Text('See All'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...List.generate(items.length, (i) {
                final isLast = i == items.length - 1;
                return _ActivityTimelineRow(
                  item: items[i],
                  showLine: !isLast,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityItem {
  const _ActivityItem({required this.time, required this.text});
  final String time;
  final String text;
  int get sortKey {
    final parts = time.split(' ');
    if (parts.length < 2) return 0;
    final hm = parts[0].split(':');
    var h = int.tryParse(hm.first) ?? 0;
    final m = int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0;
    if (parts[1] == 'PM' && h < 12) h += 12;
    if (parts[1] == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }
}

class _ActivityTimelineRow extends StatelessWidget {
  const _ActivityTimelineRow({required this.item, required this.showLine});
  final _ActivityItem item;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.time,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactWeatherTile extends StatelessWidget {
  const _CompactWeatherTile({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseService.instance.projectsCollection.doc(projectId).get(),
      builder: (context, snap) {
        final raw = snap.data?.data();
        final data = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        final loc = (data['location'] ?? '').toString().trim();
        final label = (data['geoAddress'] ?? data['name'] ?? loc).toString().trim();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                context.push(RouteNames.siteManagerWeatherForecast),
            borderRadius: BorderRadius.circular(20),
            child: SiteWeatherConditionsCard(
              projectLocation: loc.isEmpty ? null : loc,
              latitude: lat,
              longitude: lon,
              locationLabel: label.isEmpty ? null : label,
              margin: EdgeInsets.zero,
              compact: true,
            ),
          ),
        );
      },
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onProjectAction,
    required this.hasProject,
  });

  final void Function(bool hasProject, VoidCallback action) onProjectAction;
  final bool hasProject;

  @override
  Widget build(BuildContext context) {
    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Upload Site Photo',
                  onTap: () => onProjectAction(hasProject,
                      () => context.push(RouteNames.projectProgressUpdate)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.assignment_outlined,
                  label: 'Daily Report',
                  onTap: () => onProjectAction(
                      hasProject, () => context.push(RouteNames.dailyReport)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.residentBlue),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestPhotosRow extends StatelessWidget {
  const _LatestPhotosRow({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseService.instance.aiAnalysisCollection
        .where('kind', isEqualTo: 'govtrack_progress_report')
        .where('projectId', isEqualTo: projectId)
        .limit(8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Latest Site Photos', onSeeAll: () {}),
        const SizedBox(height: 10),
        SizedBox(
          height: 88,
          child: StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return SiteManagerCard(
                  margin: EdgeInsets.zero,
                  child: Center(
                    child: Text(
                      'No site photos yet',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mediumGray),
                    ),
                  ),
                );
              }

              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length.clamp(0, 6),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final data =
                      (docs[i].data() as Map?)?.cast<String, dynamic>() ?? {};
                  final url = (data['imageUrl'] ?? '').toString();
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 120,
                      color: AppTheme.lightGray,
                      child: url.isEmpty
                          ? const Icon(Icons.image_outlined)
                          : Image.network(url, fit: BoxFit.cover),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.onSeeAll});
  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        TextButton(onPressed: onSeeAll, child: const Text('See All')),
      ],
    );
  }
}
