import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_model.dart';
import '../../services/attendance_worker_registry_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/auth_service.dart';
import '../../services/geo_tag_service.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/firebase_service.dart';
import '../../services/weekly_attendance_service.dart';
import '../../widgets/common/site_weather_conditions_card.dart';
import 'widgets/site_manager_bottom_nav.dart';
import 'widgets/site_manager_card.dart';
import 'widgets/weekly_attendance_checklist.dart';
import 'widgets/worker_mon_fri_schedule_card.dart';

class ManualWorkerInput {
  const ManualWorkerInput({
    required this.workerName,
    required this.position,
    this.rate = 0,
  });

  final String workerName;
  final String position;
  final double rate;
}

/// Site manager attendance — manual checklist only (no fingerprint).
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({
    super.key,
    this.showBottomNav = false,
    this.showBack = true,
  });

  final bool showBottomNav;
  final bool showBack;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen>
    with TickerProviderStateMixin {
  static const Color _headerBlue = Color(0xFF1E3A8A);

  final _searchController = TextEditingController();
  String _positionFilter = 'All';
  String _statusFilter = 'All';
  DateTime _selectedDate = DateTime.now();
  DateTime _weekAnchor = DateTime.now();

  final Set<String> _touchedWorkers = <String>{};
  late final TabController _viewTabs;
  final _weeklyService = WeeklyAttendanceService();
  final _registry = AttendanceWorkerRegistryService.instance;
  String? _projectId;
  String? _projectLocation;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _viewTabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncChecklistForSelectedDate();
      _loadProjectLocation();
    });
  }

  Future<void> _loadProjectLocation() async {
    final user = ref.read(currentUserProvider);
    final pid = user?.assignedProjects.isNotEmpty == true
        ? user!.assignedProjects.first
        : _projectId;
    if (pid == null) return;
    try {
      final snap = await FirebaseService.instance.projectsCollection.doc(pid).get();
      final raw = snap.data();
      final loc = raw is Map ? (raw['location'] ?? '').toString().trim() : '';
      if (mounted) setState(() => _projectLocation = loc.isEmpty ? null : loc);
    } catch (_) {}
  }

  Future<void> _syncChecklistForSelectedDate() async {
    if (_syncing) return;
    _syncing = true;
    await _getOrCreateAttendanceForDate(_selectedDate);
    _syncing = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewTabs.dispose();
    super.dispose();
  }

  DateTime _normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfWeek(DateTime d) {
    final date = _normalizeDate(d);
    final delta = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: delta < 0 ? 6 : delta));
  }

  String _formatDateLabel(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(BuildContext context, DateTime? t) {
    if (t == null) return '--';
    return TimeOfDay.fromDateTime(t).format(context);
  }

  AttendanceRecord _recordFromRegistered(RegisteredWorker w) {
    return AttendanceRecord(
      workerId: w.workerId,
      workerName: w.workerName,
      position: w.position,
      rate: w.rate,
      workerType: w.position.toLowerCase(),
      isPresent: false,
    );
  }

  bool _syncRosterIntoAttendance(AttendanceModel attendance, List<RegisteredWorker> roster) {
    var changed = false;
    for (final w in roster) {
      final key = w.workerId.toLowerCase();
      final idx = attendance.records.indexWhere((r) {
        final id = (r.workerId.trim().isNotEmpty ? r.workerId : r.workerName).trim().toLowerCase();
        return id == key || r.workerName.trim().toLowerCase() == w.workerName.trim().toLowerCase();
      });
      if (idx < 0) {
        attendance.records.add(_recordFromRegistered(w));
        changed = true;
      } else {
        final r = attendance.records[idx];
        if (r.rate != w.rate || r.position != w.position || r.workerName != w.workerName) {
          r.rate = w.rate;
          r.position = w.position;
          r.workerName = w.workerName;
          changed = true;
        }
      }
    }
    return changed;
  }

  Future<AttendanceModel?> _getOrCreateAttendanceForDate(DateTime date) async {
    final target = _normalizeDate(date);
    var user = ref.read(currentUserProvider);
    if (user == null || user.assignedProjects.isEmpty) {
      final refreshed = await AuthService.instance.refreshUserData();
      if (refreshed) {
        ref.invalidate(currentUserProvider);
        user = ref.read(currentUserProvider);
      }
    }

    final projects = user?.assignedProjects;
    final userId = user?.id;
    if (user == null || projects == null || projects.isEmpty || userId == null) {
      return null;
    }

    final hive = HiveService.instance;
    final existing = hive.getAttendanceByRecorder(userId);

    AttendanceRecord cloneForNewDay(AttendanceRecord r) {
      return AttendanceRecord(
        workerId: r.workerId,
        workerName: r.workerName,
        position: r.position,
        isPresent: false,
        timeIn: null,
        timeOut: null,
        hoursWorked: r.hoursWorked,
        overtimeHours: r.overtimeHours,
        workerType: r.workerType,
        rate: r.rate,
      );
    }

    final projectId = projects.first;
    _projectId = projectId;
    final roster = _registry.loadRoster(projectId);

    AttendanceModel? existingDoc;
    for (final a in existing) {
      if (_isSameDay(a.attendanceDate, target)) {
        existingDoc = a;
        break;
      }
    }

    AttendanceModel dayAttendance;
    if (existingDoc != null) {
      dayAttendance = existingDoc;
    } else {
      final isWeekStart = target.weekday == DateTime.monday;
      final startOfWeek = _startOfWeek(target);
      final previousInWeek = existing
          .where(
            (a) =>
                a.projectId == projectId &&
                !a.attendanceDate.isAfter(target.subtract(const Duration(days: 1))) &&
                !a.attendanceDate.isBefore(startOfWeek),
          )
          .toList()
        ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

      final List<AttendanceRecord> records;
      if (!isWeekStart && previousInWeek.isNotEmpty) {
        records = previousInWeek.first.records.map(cloneForNewDay).toList();
      } else {
        records = roster.map(_recordFromRegistered).toList();
      }

      dayAttendance = AttendanceModel(
        id: const Uuid().v4(),
        projectId: projectId,
        recorderId: userId,
        attendanceDate: target,
        records: records,
        status: 'draft',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );
      await hive.saveAttendance(dayAttendance);
    }

    if (_syncRosterIntoAttendance(dayAttendance, roster)) {
      dayAttendance.updatedAt = DateTime.now();
      await hive.saveAttendance(dayAttendance);
    }

    return dayAttendance;
  }

  Future<void> _showRegisterWorkerSheet() async {
    final result = await showModalBottomSheet<ManualWorkerInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _RegisterWorkerSheet(),
    );
    if (!mounted || result == null) return;
    await _registerWorker(result);
  }

  Future<void> _registerWorker(ManualWorkerInput input) async {
    final attendance = await _getOrCreateAttendanceForDate(_selectedDate);
    if (attendance == null || _projectId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project assigned. Contact admin.')),
      );
      return;
    }

    final name = input.workerName.trim();
    if (name.isEmpty) return;

    final roster = _registry.loadRoster(_projectId!);
    if (roster.any((w) => w.workerName.toLowerCase() == name.toLowerCase())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name is already registered.')),
      );
      return;
    }

    await _registry.registerWorker(
      projectId: _projectId!,
      workerName: name,
      position: input.position,
      rate: input.rate,
    );

    final updatedRoster = _registry.loadRoster(_projectId!);
    _syncRosterIntoAttendance(attendance, updatedRoster);
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);

    if (mounted) setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name registered — added to checklist.'),
        backgroundColor: AppTheme.softGreen,
      ),
    );
  }

  Future<void> _removeWorker(AttendanceModel attendance, AttendanceRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove registered worker?'),
        content: Text(
          'Remove ${record.workerName} from the site roster? '
          'They will no longer appear on future checklists.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (_projectId != null) {
      await _registry.removeWorker(_projectId!, record.workerId);
    }
    attendance.records.remove(record);
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);
    if (mounted) setState(() {});
  }

  bool _canEditDate(DateTime date) {
    return !_normalizeDate(date).isAfter(_normalizeDate(DateTime.now()));
  }

  Future<void> _pickTimeIn(AttendanceRecord record) async {
    final initial = record.timeIn != null
        ? TimeOfDay.fromDateTime(record.timeIn!)
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final d = _normalizeDate(_selectedDate);
    record.timeIn = DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
  }

  Future<void> _markPresent(AttendanceModel attendance, AttendanceRecord record) async {
    final now = DateTime.now();
    record.isPresent = true;
    record.timeIn ??= _isSameDay(_selectedDate, now)
        ? now
        : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 8, 0);
    record.remarks = 'manual_present';
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);
    _touchedWorkers.add(record.workerId);
    if (mounted) setState(() {});
  }

  Future<void> _markAbsent(AttendanceModel attendance, AttendanceRecord record) async {
    record.isPresent = false;
    record.timeIn = null;
    record.timeOut = null;
    record.remarks = 'absent_marked';
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);
    _touchedWorkers.add(record.workerId);
    if (mounted) setState(() {});
  }

  Future<void> _markLate(AttendanceModel attendance, AttendanceRecord record) async {
    final d = _normalizeDate(_selectedDate);
    record.isPresent = true;
    record.timeIn = DateTime(d.year, d.month, d.day, 8, 30);
    record.remarks = 'late_marked';
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);
    _touchedWorkers.add(record.workerId);
    if (mounted) setState(() {});
  }

  String _weeklyStatusLabel(WeeklyDayStatus status) {
    switch (status) {
      case WeeklyDayStatus.present:
        return 'Present';
      case WeeklyDayStatus.late:
        return 'Late';
      case WeeklyDayStatus.absent:
        return 'Absent';
      case WeeklyDayStatus.dayOff:
        return 'Day Off';
      case WeeklyDayStatus.pending:
        return 'Pending';
    }
  }

  Future<void> _handleWeeklyCellTap(WeeklyWorkerRow worker, WeeklyDayCell cell) async {
    if (cell.date.isAfter(_normalizeDate(DateTime.now()))) return;
    final picked = await showWeeklyStatusPickerSheet(
      context,
      workerName: worker.workerName,
      day: cell.date,
      current: cell.status,
    );
    if (!mounted || picked == null) return;
    await _applyWeeklyDayStatus(worker, cell.date, picked);
    if (mounted) setState(() {});
  }

  Future<void> _applyWeeklyDayStatus(
    WeeklyWorkerRow worker,
    DateTime day,
    WeeklyDayStatus status,
  ) async {
    final attendance = await _getOrCreateAttendanceForDate(day);
    if (attendance == null) return;

    final workerKey = worker.workerId.trim().toLowerCase();
    var index = attendance.records.indexWhere((r) {
      final key = (r.workerId.trim().isNotEmpty ? r.workerId : r.workerName).trim().toLowerCase();
      return key == workerKey;
    });

    AttendanceRecord record;
    if (index >= 0) {
      record = attendance.records[index];
    } else {
      record = AttendanceRecord(
        workerId: worker.workerId,
        workerName: worker.workerName,
        position: worker.position,
        rate: worker.templateRecord?.rate ?? 0,
      );
      attendance.records.add(record);
    }

    final dayNorm = _normalizeDate(day);
    final isToday = _isSameDay(dayNorm, _normalizeDate(DateTime.now()));
    final now = DateTime.now();

    switch (status) {
      case WeeklyDayStatus.present:
        record.isPresent = true;
        record.timeIn = isToday ? now : DateTime(dayNorm.year, dayNorm.month, dayNorm.day, 8, 0);
        record.remarks = 'manual_present';
      case WeeklyDayStatus.late:
        record.isPresent = true;
        record.timeIn = isToday ? now : DateTime(dayNorm.year, dayNorm.month, dayNorm.day, 8, 30);
        record.remarks = 'late_marked';
      case WeeklyDayStatus.absent:
        record.isPresent = false;
        record.timeIn = null;
        record.remarks = 'absent_marked';
      case WeeklyDayStatus.dayOff:
        record.isPresent = false;
        record.timeIn = null;
        record.remarks = 'day_off';
      case WeeklyDayStatus.pending:
        return;
    }

    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);
    _touchedWorkers.add(record.workerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${worker.workerName}: ${_weeklyStatusLabel(status)}'),
        backgroundColor: AppTheme.softGreen,
      ),
    );
  }

  Future<void> _pickAttendanceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = _normalizeDate(picked);
        _touchedWorkers.clear();
      });
      await _syncChecklistForSelectedDate();
    }
  }

  Future<void> _submitAttendance(AttendanceModel attendance) async {
    final geoTag = await GeoTagService.instance.captureGeoTag();
    attendance.status = 'submitted';
    attendance.syncStatus = 'pending';
    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);

    await AuditLogService.instance.logAction(
      action: 'attendance_submitted',
      projectId: attendance.projectId,
      details: {
        'attendanceId': attendance.id,
        'attendanceDate': attendance.attendanceDate.toIso8601String(),
        'totalWorkers': attendance.totalWorkers,
        'presentWorkers': attendance.presentWorkers,
        'geoTag': geoTag,
      },
    );

    if (!mounted) return;
    setState(() => _touchedWorkers.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance submitted to Admin.'), backgroundColor: AppTheme.softGreen),
    );

    try {
      final result = await SyncService.instance.syncPendingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppTheme.softGreen : AppTheme.warningOrange,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;
    final allAttendance = user == null
        ? hive.getAllAttendance()
        : hive.getAttendanceByRecorder(user.id);
    final attendanceList = [...allAttendance]
      ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

    final selectedDate = _normalizeDate(_selectedDate);
    AttendanceModel? activeAttendance;
    for (final a in attendanceList) {
      if (_isSameDay(a.attendanceDate, selectedDate)) {
        activeAttendance = a;
        break;
      }
    }

    final projectId = user?.assignedProjects.isNotEmpty == true
        ? user!.assignedProjects.first
        : _projectId;
    if (projectId != null) _projectId = projectId;
    final roster = projectId != null ? _registry.loadRoster(projectId) : <RegisteredWorker>[];

    final records = activeAttendance?.records.isNotEmpty == true
        ? activeAttendance!.records
        : roster.map(_recordFromRegistered).toList();
    final canEdit = _canEditDate(selectedDate);

    final presentCount = records.where((r) => r.isPresent || r.timeIn != null).length;
    final absentCount = records.length - presentCount;
    final rate = records.isEmpty ? 0.0 : (presentCount / records.length) * 100;

    final positions = <String>{
      'All',
      ...records.map((r) => r.position.trim()).where((p) => p.isNotEmpty),
    }.toList()
      ..sort();
    if (!positions.contains(_positionFilter)) _positionFilter = 'All';

    final query = _searchController.text.trim().toLowerCase();
    final filtered = records.where((r) {
      if (_positionFilter != 'All' && r.position.trim() != _positionFilter) return false;
      final present = r.isPresent || r.timeIn != null;
      if (_statusFilter == 'Present' && !present) return false;
      if (_statusFilter == 'Absent' && present) return false;
      if (query.isNotEmpty && !r.workerName.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    final weeklyRows = _weeklyService.buildWeeklyRows(
      allAttendance: attendanceList,
      weekAnchor: _weekAnchor,
      perWorkerRegisteredAt: projectId != null ? _registry.registeredAtMap(projectId) : {},
      roster: roster,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(context),
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _viewTabs,
              labelColor: _headerBlue,
              unselectedLabelColor: AppTheme.mediumGray,
              indicatorColor: _headerBlue,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: const [
                Tab(text: 'Daily Checklist'),
                Tab(text: 'Worker Schedules'),
                Tab(text: 'Weekly Overview'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _viewTabs,
              children: [
                _buildDailyTab(
                  context,
                  activeAttendance: activeAttendance,
                  filtered: filtered,
                  records: records,
                  canEdit: canEdit,
                  presentCount: presentCount,
                  absentCount: absentCount,
                  rate: rate,
                  positions: positions,
                  rosterCount: roster.length,
                ),
                _buildWorkerSchedulesTab(context, weeklyRows: weeklyRows),
                _buildWeeklyTab(context, weeklyRows: weeklyRows, attendanceList: attendanceList),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          widget.showBottomNav ? const SiteManagerBottomNav(currentIndex: 2) : null,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, top + 8, 8, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          if (widget.showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => context.canPop() ? context.pop() : context.go(RouteNames.siteManagerHome),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance Checklist',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  'Manual worker log • Site manager verified',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push(RouteNames.settings),
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTab(
    BuildContext context, {
    required AttendanceModel? activeAttendance,
    required List<AttendanceRecord> filtered,
    required List<AttendanceRecord> records,
    required bool canEdit,
    required int presentCount,
    required int absentCount,
    required double rate,
    required List<String> positions,
    required int rosterCount,
  }) {
    final weekLabel = WeeklyAttendanceService.formatWeekRange(_selectedDate);
    final isMonday = _selectedDate.weekday == DateTime.monday;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 100 + MediaQuery.of(context).padding.bottom),
          children: [
            SiteWeatherConditionsCard(
              projectLocation: _projectLocation,
              margin: EdgeInsets.zero,
              compact: true,
            ),
            const SizedBox(height: 12),
            _DateSelectorCard(
              label: _formatDateLabel(_selectedDate),
              weekLabel: weekLabel,
              rosterCount: rosterCount,
              onTap: _pickAttendanceDate,
            ),
            if (isMonday) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.refresh, size: 18, color: Color(0xFF2563EB)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'New week — checklist reset. Registered workers remain on the roster.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF1E40AF),
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _SummaryStatsRow(
              total: records.length,
              present: presentCount,
              absent: absentCount,
              rate: rate,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _showRegisterWorkerSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: _headerBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Register Worker', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search registered workers…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All roles',
                    selected: _positionFilter == 'All',
                    onTap: () => setState(() => _positionFilter = 'All'),
                  ),
                  ...positions.where((p) => p != 'All').map(
                        (p) => _FilterChip(
                          label: p,
                          selected: _positionFilter == p,
                          onTap: () => setState(() => _positionFilter = p),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: ['All', 'Present', 'Absent'].map((s) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: s,
                    selected: _statusFilter == s,
                    onTap: () => setState(() => _statusFilter = s),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            if (records.isEmpty)
              SiteManagerCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.playlist_add_check_circle_outlined,
                        size: 48, color: _headerBlue.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No registered workers yet.',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Register workers once — they appear on every daily checklist.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _showRegisterWorkerSheet,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Register Worker'),
                    ),
                  ],
                ),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No workers match your filters.', textAlign: TextAlign.center),
              )
            else
              ...filtered.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WorkerChecklistCard(
                    record: r,
                    canEdit: canEdit && activeAttendance != null,
                    timeLabel: _formatTime(context, r.timeIn),
                    rateLabel: r.rate > 0 ? '₱${r.rate.toStringAsFixed(0)}/day' : 'Rate not set',
                    onPresent: activeAttendance == null
                        ? null
                        : () => _markPresent(activeAttendance, r),
                    onLate: activeAttendance == null ? null : () => _markLate(activeAttendance, r),
                    onAbsent: activeAttendance == null
                        ? null
                        : () => _markAbsent(activeAttendance, r),
                    onEditTime: activeAttendance == null
                        ? null
                        : () async {
                            await _pickTimeIn(r);
                            await HiveService.instance.saveAttendance(activeAttendance);
                            if (mounted) setState(() {});
                          },
                    onRemove: activeAttendance == null
                        ? null
                        : () => _removeWorker(activeAttendance, r),
                  ),
                ),
              ),
          ],
        ),
        if (activeAttendance != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: FilledButton.icon(
              onPressed: _touchedWorkers.isEmpty ? null : () => _submitAttendance(activeAttendance),
              style: FilledButton.styleFrom(
                backgroundColor: _headerBlue,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit to Admin', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }

  Widget _buildWorkerSchedulesTab(
    BuildContext context, {
    required List<WeeklyWorkerRow> weeklyRows,
  }) {
    final weekLabel = WeeklyAttendanceService.formatWeekRange(_weekAnchor);
    final canEdit = !_weekAnchor.isAfter(DateTime.now().add(const Duration(days: 1)));

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Mon – Fri schedules',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    weekLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.mediumGray),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                final next = _weekAnchor.add(const Duration(days: 7));
                if (!WeeklyAttendanceService.startOfWeek(next)
                    .isAfter(WeeklyAttendanceService.startOfWeek(DateTime.now()))) {
                  setState(() => _weekAnchor = next);
                }
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Each worker has their own Mon–Fri checklist. Tap a day to mark Present, Late, or Absent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray, height: 1.35),
        ),
        const SizedBox(height: 12),
        if (weeklyRows.isEmpty)
          SiteManagerCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.groups_outlined, size: 48, color: Color(0xFF94A3B8)),
                const SizedBox(height: 12),
                Text(
                  'No workers registered',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _showRegisterWorkerSheet,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Register Worker'),
                ),
              ],
            ),
          )
        else
          ...weeklyRows.map(
            (row) => WorkerMonFriScheduleCard(
              row: row,
              canEdit: canEdit,
              onCellTap: (w, cell) => _handleWeeklyCellTap(w, cell),
            ),
          ),
      ],
    );
  }

  Widget _buildWeeklyTab(
    BuildContext context, {
    required List<WeeklyWorkerRow> weeklyRows,
    required List<AttendanceModel> attendanceList,
  }) {
    final avgRate = weeklyRows.isEmpty
        ? 0.0
        : weeklyRows.map((r) => r.ratePercent).reduce((a, b) => a + b) / weeklyRows.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(0, 14, 0, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        WeeklyAttendanceChecklist(
          weekAnchor: _weekAnchor,
          rows: weeklyRows,
          onPreviousWeek: () => setState(() => _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))),
          onNextWeek: () {
            final next = _weekAnchor.add(const Duration(days: 7));
            if (!WeeklyAttendanceService.startOfWeek(next)
                .isAfter(WeeklyAttendanceService.startOfWeek(DateTime.now()))) {
              setState(() => _weekAnchor = next);
            }
          },
          onCellTap: _handleWeeklyCellTap,
          onAddWorker: _showRegisterWorkerSheet,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SiteManagerCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Week summary',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      Text(
                        '${weeklyRows.length} workers • Tap a day to update',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${avgRate.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7C3AED),
                      ),
                ),
              ],
            ),
          ),
        ),
        if (attendanceList.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Add workers on the Daily Checklist tab first.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _DateSelectorCard extends StatelessWidget {
  const _DateSelectorCard({
    required this.label,
    required this.onTap,
    this.weekLabel,
    this.rosterCount = 0,
  });
  final String label;
  final VoidCallback onTap;
  final String? weekLabel;
  final int rosterCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_today, color: Color(0xFF1E3A8A), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attendance date',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.mediumGray)),
                    Text(label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    if (weekLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Week: $weekLabel • $rosterCount registered',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF2563EB),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryStatsRow extends StatelessWidget {
  const _SummaryStatsRow({
    required this.total,
    required this.present,
    required this.absent,
    required this.rate,
  });

  final int total;
  final int present;
  final int absent;
  final double rate;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.mediumGray)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat('Total', '$total', const Color(0xFF1E3A8A)),
        const SizedBox(width: 8),
        stat('Present', '$present', const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        stat('Absent', '$absent', const Color(0xFFEF4444)),
        const SizedBox(width: 8),
        stat('Rate', '${rate.toStringAsFixed(0)}%', const Color(0xFF7C3AED)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
        checkmarkColor: const Color(0xFF1E3A8A),
      ),
    );
  }
}

class _WorkerChecklistCard extends StatelessWidget {
  const _WorkerChecklistCard({
    required this.record,
    required this.canEdit,
    required this.timeLabel,
    required this.rateLabel,
    this.onPresent,
    this.onLate,
    this.onAbsent,
    this.onEditTime,
    this.onRemove,
  });

  final AttendanceRecord record;
  final bool canEdit;
  final String timeLabel;
  final String rateLabel;
  final VoidCallback? onPresent;
  final VoidCallback? onLate;
  final VoidCallback? onAbsent;
  final VoidCallback? onEditTime;
  final VoidCallback? onRemove;

  bool get _isPresent => record.isPresent || record.timeIn != null;
  bool get _isLate => (record.remarks ?? '').contains('late');

  @override
  Widget build(BuildContext context) {
    final initials = _initials(record.workerName);
    Color statusColor;
    String statusLabel;
    if (!_isPresent) {
      statusColor = const Color(0xFF94A3B8);
      statusLabel = 'Not marked';
    } else if (_isLate) {
      statusColor = const Color(0xFFF97316);
      statusLabel = 'Late';
    } else {
      statusColor = const Color(0xFF16A34A);
      statusLabel = 'Present';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.workerName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    Text(
                      record.position.trim().isEmpty ? 'Worker' : record.position.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rateLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF7C3AED),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                  onPressed: canEdit ? onRemove : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: AppTheme.mediumGray),
              const SizedBox(width: 6),
              Text('Time in: $timeLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              if (onEditTime != null && canEdit) ...[
                const Spacer(),
                TextButton(onPressed: onEditTime, child: const Text('Set time')),
              ],
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatusButton(
                    label: 'Present',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF16A34A),
                    selected: _isPresent && !_isLate,
                    onTap: onPresent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatusButton(
                    label: 'Late',
                    icon: Icons.schedule,
                    color: const Color(0xFFF97316),
                    selected: _isLate,
                    onTap: onLate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatusButton(
                    label: 'Absent',
                    icon: Icons.cancel_outlined,
                    color: const Color(0xFFEF4444),
                    selected: !_isPresent && (record.remarks ?? '').contains('absent'),
                    onTap: onAbsent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.14) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? color : AppTheme.mediumGray),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? color : AppTheme.mediumGray,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterWorkerSheet extends StatefulWidget {
  const _RegisterWorkerSheet();

  @override
  State<_RegisterWorkerSheet> createState() => _RegisterWorkerSheetState();
}

class _RegisterWorkerSheetState extends State<_RegisterWorkerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rateController = TextEditingController(text: '450');
  String _position = 'Laborer';

  static const _positions = [
    'Carpenter',
    'Mason',
    'Electrician',
    'Plumber',
    'Steel Fixer',
    'Foreman',
    'Laborer',
    'Site Engineer',
    'Other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final rate = double.tryParse(_rateController.text.trim()) ?? 0;
    Navigator.pop(
      context,
      ManualWorkerInput(
        workerName: _nameController.text.trim(),
        position: _position,
        rate: rate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.badge_outlined, color: Color(0xFF1E3A8A)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Register Worker',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Saved to site roster • auto-added to checklist',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Full name *',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Worker name is required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _position,
              decoration: InputDecoration(
                labelText: 'Position / trade *',
                prefixIcon: const Icon(Icons.engineering_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: _positions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => _position = v ?? _position),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rateController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Daily rate (₱) *',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              validator: (v) {
                final rate = double.tryParse((v ?? '').trim());
                if (rate == null || rate <= 0) return 'Enter a valid daily rate';
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Workers stay registered across weeks. Each Monday starts a fresh attendance checklist.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.mediumGray,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Register & add to checklist'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
