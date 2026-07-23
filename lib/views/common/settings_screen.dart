import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../services/hive_service.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../models/attendance_model.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    final s = v.toString();
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<AttendanceModel> _mergeAttendance({
    required List<AttendanceModel> local,
    required List<AttendanceModel> remote,
  }) {
    final map = <String, AttendanceModel>{
      for (final a in local) a.id: a,
      for (final a in remote) a.id: a,
    };
    return map.values.toList();
  }

  DateTime _startOfWeek(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final delta = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: delta < 0 ? 6 : delta));
  }

  String _formatShort(DateTime d) {
    return '${d.month}/${d.day}/${d.year}';
  }

  Future<void> _openWeekDetails(
    BuildContext context, {
    required String title,
    required List<AttendanceRecord> records,
  }) async {
    bool presentFor(AttendanceRecord r, int weekday) {
      switch (weekday) {
        case DateTime.monday:
          return r.monPresent;
        case DateTime.tuesday:
          return r.tuePresent;
        case DateTime.wednesday:
          return r.wedPresent;
        case DateTime.thursday:
          return r.thuPresent;
        case DateTime.friday:
          return r.friPresent;
        case DateTime.saturday:
          return r.satPresent;
        case DateTime.sunday:
          return false;
        default:
          return false;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final sorted = [...records]
          ..sort((a, b) => a.workerName.compareTo(b.workerName));

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + media.viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.darkGray,
                      ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = sorted[index];

                      Widget dayChip(String label, bool isPresent) {
                        final color =
                            isPresent ? AppTheme.softGreen : AppTheme.errorRed;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            label,
                            style:
                                Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                    ),
                          ),
                        );
                      }

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGray,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.deepBlue.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.workerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.darkGray,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                dayChip('Mon', presentFor(r, DateTime.monday)),
                                dayChip('Tue', presentFor(r, DateTime.tuesday)),
                                dayChip('Wed', presentFor(r, DateTime.wednesday)),
                                dayChip('Thu', presentFor(r, DateTime.thursday)),
                                dayChip('Fri', presentFor(r, DateTime.friday)),
                                dayChip('Sat', presentFor(r, DateTime.saturday)),
                                dayChip('Sun', presentFor(r, DateTime.sunday)),
                              ],
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;
    final localAll = user == null ? hive.getAllAttendance() : hive.getAttendanceByRecorder(user.id);
    final projectId = (user != null && user.assignedProjects.isNotEmpty) ? user.assignedProjects.first : null;

    if (user == null || projectId == null || projectId.isEmpty) {
      final Map<DateTime, List<AttendanceModel>> byWeek = {};
      for (final a in localAll) {
        final weekStart = _startOfWeek(a.attendanceDate);
        byWeek.putIfAbsent(weekStart, () => []).add(a);
      }
      final weeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));

      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Settings',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Attendance History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkGray,
                  ),
            ),
            const SizedBox(height: 12),
            if (weeks.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.deepBlue.withValues(alpha: 0.08)),
                ),
                child: Text(
                  'No attendance history yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              )
            else
              ...weeks.map((weekStart) {
                final list = byWeek[weekStart] ?? const <AttendanceModel>[];
                final sorted = [...list]
                  ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));
                final latest = sorted.first;

                final weekEnd = weekStart.add(const Duration(days: 6));
                final title = '${_formatShort(weekStart)} - ${_formatShort(weekEnd)}';
                final subtitle = '${latest.records.length} workers • last updated ${_formatShort(latest.attendanceDate)}';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    tileColor: AppTheme.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: AppTheme.deepBlue.withValues(alpha: 0.08),
                      ),
                    ),
                    title: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.darkGray,
                          ),
                    ),
                    subtitle: Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openWeekDetails(
                      context,
                      title: title,
                      records: latest.records,
                    ),
                  ),
                );
              }),
          ],
        ),
      );
    }

    final attendanceStream = FirebaseService.instance.firestore
        .collectionGroup('attendance')
        .where('recorderId', isEqualTo: user.id)
        .orderBy('attendanceDateTs', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: attendanceStream,
        builder: (context, snapshot) {
          List<AttendanceModel> remoteAll = const <AttendanceModel>[];
          if (snapshot.hasData) {
            remoteAll = snapshot.data!.docs
                .map((d) {
                  final raw = (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                  raw['id'] = d.id;
                  if (raw['attendanceDate'] == null && raw['attendanceDateTs'] != null) {
                    raw['attendanceDate'] = _toDateTime(raw['attendanceDateTs']).toIso8601String();
                  }
                  if (raw['createdAt'] == null && raw['createdAtTs'] != null) {
                    raw['createdAt'] = _toDateTime(raw['createdAtTs']).toIso8601String();
                  }
                  if (raw['updatedAt'] == null && raw['updatedAtTs'] != null) {
                    raw['updatedAt'] = _toDateTime(raw['updatedAtTs']).toIso8601String();
                  }
                  return AttendanceModel.fromJson(raw);
                })
                .toList();
          }

          final all = _mergeAttendance(local: localAll, remote: remoteAll);
          final Map<DateTime, List<AttendanceModel>> byWeek = {};
          for (final a in all) {
            final weekStart = _startOfWeek(a.attendanceDate);
            byWeek.putIfAbsent(weekStart, () => []).add(a);
          }
          final weeks = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'Attendance History',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkGray,
                    ),
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Unable to refresh attendance history. Showing offline records.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.errorRed,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              if (!snapshot.hasData)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (weeks.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.deepBlue.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    'No attendance history yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                )
              else
                ...weeks.map((weekStart) {
                  final list = byWeek[weekStart] ?? const <AttendanceModel>[];
                  final sorted = [...list]
                    ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));
                  final latest = sorted.first;

                  final weekEnd = weekStart.add(const Duration(days: 6));
                  final title = '${_formatShort(weekStart)} - ${_formatShort(weekEnd)}';
                  final subtitle = '${latest.records.length} workers • last updated ${_formatShort(latest.attendanceDate)}';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      tileColor: AppTheme.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: AppTheme.deepBlue.withValues(alpha: 0.08),
                        ),
                      ),
                      title: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkGray,
                            ),
                      ),
                      subtitle: Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openWeekDetails(
                        context,
                        title: title,
                        records: latest.records,
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
