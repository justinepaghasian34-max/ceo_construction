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
import '../../services/weekly_attendance_service.dart';
import '../../utils/dialog_utils.dart';
import 'widgets/site_manager_bottom_nav.dart';

// ── Input model ──────────────────────────────────────────────────────────────
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

// ── Screen ───────────────────────────────────────────────────────────────────
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

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  static const Color _blue = AppTheme.residentBlue;

  DateTime _selectedDate = DateTime.now();
  String? _projectId;
  bool _syncing = false;
  bool _submitting = false;

  final _registry = AttendanceWorkerRegistryService.instance;
  String? _historyWorkerId;   // which worker's history is expanded
  String? _expandedWorkerId; // expanded worker card for weekly day details

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDate());
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _workerKeyFromRecord(AttendanceRecord r) {
    return (r.workerId.isNotEmpty ? r.workerId : r.workerName)
        .trim()
        .toLowerCase();
  }

  String _workerKeyFromName(String workerName) {
    return workerName.trim().toLowerCase();
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month-1]} ${d.day}, ${d.year}';
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '--:--';
    return TimeOfDay.fromDateTime(t).format(context);
  }

  static double _slotHours(DateTime? s, DateTime? e) {
    if (s == null || e == null) return 0;
    final diff = e.difference(s).inMinutes;
    return diff > 0 ? diff / 60.0 : 0;
  }

  static double _calcHours(AttendanceRecord r) {
    double h = 0;
    h += _slotHours(r.amTimeIn, r.amTimeOut);
    h += _slotHours(r.pmTimeIn, r.pmTimeOut);
    return double.parse(h.toStringAsFixed(1));
  }

  static String _calcStatus(AttendanceRecord r) {
    final hours = _calcHours(r);
    if (hours == 0 && !r.isPresent && r.timeIn == null) return 'Absent';
    final checkTime = r.amTimeIn ?? r.timeIn;
    if (checkTime != null) {
      final t = TimeOfDay.fromDateTime(checkTime);
      if (t.hour > 8 || (t.hour == 8 && t.minute > 15)) return 'Late';
    }
    if (hours > 0 && hours < 6) return 'Half day';
    if (r.isPresent || r.timeIn != null) return 'Present';
    return 'Absent';
  }

  // ── Data ────────────────────────────────────────────────────────────────
  Future<void> _syncDate() async {
    if (_syncing) return;
    _syncing = true;
    await _getOrCreate(_selectedDate);
    _syncing = false;
    if (mounted) setState(() {});
  }

  AttendanceRecord _fromRegistered(RegisteredWorker w) => AttendanceRecord(
        workerId: w.workerId,
        workerName: w.workerName,
        position: w.position,
        rate: w.rate,
        workerType: w.position.toLowerCase(),
        isPresent: false,
      );

  Future<AttendanceModel?> _getOrCreate(DateTime date) async {
    final target = _norm(date);
    var user = ref.read(currentUserProvider);
    if (user == null || user.assignedProjects.isEmpty) {
      await AuthService.instance.refreshUserData();
      ref.invalidate(currentUserProvider);
      user = ref.read(currentUserProvider);
    }
    if (user == null || user.assignedProjects.isEmpty) return null;

    final projectId = user.assignedProjects.first;
    _projectId = projectId;
    final hive = HiveService.instance;
    final roster = _registry.loadRoster(projectId);

    final existing = hive.getAttendanceByRecorder(user.id)
        .where((a) => _sameDay(a.attendanceDate, target))
        .firstOrNull;

    if (existing != null) {
      // Sync any new roster workers into existing record
      bool changed = false;
      for (final w in roster) {
        final key = w.workerId.toLowerCase();
        final has = existing.records.any((r) =>
            (r.workerId.isNotEmpty ? r.workerId : r.workerName)
                .toLowerCase() == key);
        if (!has) {
          existing.records.add(_fromRegistered(w));
          changed = true;
        }
      }
      if (changed) {
        existing.updatedAt = DateTime.now();
        await hive.saveAttendance(existing);
      }
      return existing;
    }

    final model = AttendanceModel(
      id: const Uuid().v4(),
      projectId: projectId,
      recorderId: user.id,
      attendanceDate: target,
      records: roster.map(_fromRegistered).toList(),
      status: 'draft',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );
    await hive.saveAttendance(model);
    return model;
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
    );
    if (p == null || !mounted) return;
    setState(() => _selectedDate = _norm(p));
    await _syncDate();
  }

  Future<void> _pickAmPm(
      AttendanceModel att, AttendanceRecord rec, String slot) async {
    final defaults = {
      'amIn': const TimeOfDay(hour: 8, minute: 0),
      'amOut': const TimeOfDay(hour: 12, minute: 0),
      'pmIn': const TimeOfDay(hour: 13, minute: 0),
      'pmOut': const TimeOfDay(hour: 17, minute: 0),
    };
    final cur = switch (slot) {
      'amIn'  => rec.amTimeIn,
      'amOut' => rec.amTimeOut,
      'pmIn'  => rec.pmTimeIn,
      _       => rec.pmTimeOut,
    };
    final picked = await showTimePicker(
      context: context,
      initialTime: cur != null
          ? TimeOfDay.fromDateTime(cur)
          : defaults[slot]!,
    );
    if (picked == null || !mounted) return;
    final d = _norm(_selectedDate);
    final dt = DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
      setState(() {
      switch (slot) {
        case 'amIn':
          rec.amTimeIn = dt; rec.timeIn = dt; rec.isPresent = true;
        case 'amOut':
          rec.amTimeOut = dt;
        case 'pmIn':
          rec.pmTimeIn = dt;
        case 'pmOut':
          rec.pmTimeOut = dt; rec.timeOut = dt; rec.isPresent = true;
      }
      rec.hoursWorked = _calcHours(rec);
    });
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
  }

  Future<void> _markPresent(AttendanceModel att, AttendanceRecord rec) async {
    final now = DateTime.now();
    final d = _norm(_selectedDate);
    rec.isPresent = true;
    rec.timeIn ??= _sameDay(_selectedDate, now)
        ? now
        : DateTime(d.year, d.month, d.day, 8, 0);
    rec.remarks = 'manual_present';
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
    if (mounted) setState(() {});
  }

  Future<void> _markLate(AttendanceModel att, AttendanceRecord rec) async {
    final d = _norm(_selectedDate);
    rec.isPresent = true;
    rec.timeIn = DateTime(d.year, d.month, d.day, 8, 30);
    rec.remarks = 'late_marked';
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
    if (mounted) setState(() {});
  }

  Future<void> _markAbsent(AttendanceModel att, AttendanceRecord rec) async {
    rec.isPresent = false;
    rec.timeIn = null; rec.timeOut = null;
    rec.amTimeIn = null; rec.amTimeOut = null;
    rec.pmTimeIn = null; rec.pmTimeOut = null;
    rec.hoursWorked = 0;
    rec.remarks = 'absent_marked';
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
    if (mounted) setState(() {});
  }

  Future<void> _removeWorker(AttendanceModel att, AttendanceRecord rec) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Remove worker?',
      message: 'Remove ${rec.workerName} from the roster?',
      confirmText: 'Remove', cancelText: 'Cancel', isDangerous: true,
    );
    if (ok != true) return;
    if (_projectId != null) await _registry.removeWorker(_projectId!, rec.workerId);
    att.records.remove(rec);
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
    if (mounted) setState(() {});
  }

  Future<AttendanceModel?> _getOrCreateForDate(DateTime date) async {
    final target = _norm(date);
    var user = ref.read(currentUserProvider);
    if (user == null || user.assignedProjects.isEmpty) {
      await AuthService.instance.refreshUserData();
        ref.invalidate(currentUserProvider);
        user = ref.read(currentUserProvider);
      }
    if (user == null || user.assignedProjects.isEmpty) return null;

    final projectId = user.assignedProjects.first;
    final hive = HiveService.instance;
    final roster = _registry.loadRoster(projectId);

    var existing = hive.getAttendanceByRecorder(user.id)
        .where((a) => _sameDay(a.attendanceDate, target))
        .firstOrNull;

    if (existing != null) {
      bool changed = false;
      for (final w in roster) {
        final key = _workerKeyFromName(w.workerName);
        final has = existing.records.any((r) => _workerKeyFromRecord(r) == key);
        if (!has) {
          existing.records.add(_fromRegistered(w));
          changed = true;
        }
      }
      if (changed) {
        existing.updatedAt = DateTime.now();
        await hive.saveAttendance(existing);
      }
      return existing;
    }

    final model = AttendanceModel(
          id: const Uuid().v4(),
      projectId: projectId,
      recorderId: user.id,
      attendanceDate: target,
      records: roster.map(_fromRegistered).toList(),
          status: 'draft',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        );
    await hive.saveAttendance(model);
    return model;
  }

  Future<void> _pickDayTime(
      AttendanceModel att,
      AttendanceRecord rec,
      String slot,
      DateTime date,
      ) async {
    final defaults = {
      'amIn': const TimeOfDay(hour: 8, minute: 0),
      'amOut': const TimeOfDay(hour: 12, minute: 0),
      'pmIn': const TimeOfDay(hour: 13, minute: 0),
      'pmOut': const TimeOfDay(hour: 17, minute: 0),
    };
    final cur = switch (slot) {
      'amIn'  => rec.amTimeIn,
      'amOut' => rec.amTimeOut,
      'pmIn'  => rec.pmTimeIn,
      _       => rec.pmTimeOut,
    };
    final picked = await showTimePicker(
      context: context,
      initialTime: cur != null
          ? TimeOfDay.fromDateTime(cur)
          : defaults[slot]!,
    );
    if (picked == null || !mounted) return;
    final d = DateTime(date.year, date.month, date.day);
    final dt = DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
    setState(() {
      switch (slot) {
        case 'amIn':
          rec.amTimeIn = dt;
          rec.timeIn ??= dt;
          rec.isPresent = true;
        case 'amOut':
          rec.amTimeOut = dt;
        case 'pmIn':
          rec.pmTimeIn = dt;
        case 'pmOut':
          rec.pmTimeOut = dt;
          rec.timeOut = dt;
          rec.isPresent = true;
      }
      rec.hoursWorked = _calcHours(rec);
    });
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
  }

  Future<void> _markDayStatus(
    AttendanceRecord rec,
    AttendanceModel att,
    DateTime day,
    String status,
  ) async {
    switch (status) {
      case 'present':
        rec.isPresent = true;
        rec.remarks = 'manual_present';
        rec.timeIn ??= DateTime(day.year, day.month, day.day, 8, 0);
        rec.timeOut ??= DateTime(day.year, day.month, day.day, 17, 0);
        break;
      case 'late':
        rec.isPresent = true;
        rec.remarks = 'late_marked';
        rec.timeIn = DateTime(day.year, day.month, day.day, 8, 30);
        rec.timeOut = DateTime(day.year, day.month, day.day, 17, 0);
        break;
      case 'halfDayAm':
        rec.isPresent = true;
        rec.remarks = 'half_day_am';
        rec.amTimeIn = DateTime(day.year, day.month, day.day, 8, 0);
        rec.amTimeOut = DateTime(day.year, day.month, day.day, 12, 0);
        rec.pmTimeIn = null;
        rec.pmTimeOut = null;
        rec.timeIn = rec.amTimeIn;
        rec.timeOut = rec.amTimeOut;
        break;
      case 'halfDayPm':
        rec.isPresent = true;
        rec.remarks = 'half_day_pm';
        rec.amTimeIn = null;
        rec.amTimeOut = null;
        rec.pmTimeIn = DateTime(day.year, day.month, day.day, 13, 0);
        rec.pmTimeOut = DateTime(day.year, day.month, day.day, 17, 0);
        rec.timeIn = rec.pmTimeIn;
        rec.timeOut = rec.pmTimeOut;
        break;
      case 'absent':
        default:
        rec.isPresent = false;
        rec.timeIn = null;
        rec.timeOut = null;
        rec.amTimeIn = null;
        rec.amTimeOut = null;
        rec.pmTimeIn = null;
        rec.pmTimeOut = null;
        rec.hoursWorked = 0;
        rec.remarks = 'absent_marked';
        break;
    }
    rec.hoursWorked = _calcHours(rec);
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);
    if (mounted) setState(() {});
  }

  Future<void> _showDayActionSheet(
    WeeklyWorkerRow row,
    WeeklyDayCell cell,
  ) async {
    final date = cell.date;
    final user = ref.read(currentUserProvider);
    if (user == null || _projectId == null) return;
    final att = await _getOrCreateForDate(date);
    if (att == null) return;
    final rec = att.records.firstWhere(
      (r) => _workerKeyFromRecord(r) == _workerKeyFromName(row.workerName),
      orElse: () => AttendanceRecord(
        workerId: row.workerId,
        workerName: row.workerName,
        position: row.position,
        rate: row.templateRecord?.rate ?? 0.0,
        workerType: row.position.toLowerCase(),
      ),
    );
    if (!att.records.contains(rec)) att.records.add(rec);
    await HiveService.instance.saveAttendance(att);

    if (!mounted) return;
    final action = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                      '${row.workerName} • ${WeeklyAttendanceService.formatDayHeader(date).replaceAll('\n', ' ')}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                        Text(
                      'Set attendance status for this day and adjust times.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Present'),
                onTap: () => Navigator.of(context).pop('present'),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Late'),
                onTap: () => Navigator.of(context).pop('late'),
              ),
              ListTile(
                leading: const Icon(Icons.sunny),
                title: const Text('Half day AM'),
                onTap: () => Navigator.of(context).pop('halfDayAm'),
              ),
              ListTile(
                leading: const Icon(Icons.sunny),
                title: const Text('Half day PM'),
                onTap: () => Navigator.of(context).pop('halfDayPm'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Absent'),
                onTap: () => Navigator.of(context).pop('absent'),
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Edit time slots'),
                onTap: () => Navigator.of(context).pop('editTime'),
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) return;
    if (action == 'editTime') {
      await _pickDayTime(att, rec, 'amIn', date);
      await _pickDayTime(att, rec, 'amOut', date);
      await _pickDayTime(att, rec, 'pmIn', date);
      await _pickDayTime(att, rec, 'pmOut', date);
      return;
    }

    await _markDayStatus(rec, att, date, action);
  }

  // ── Worker detail sheet (opens on worker name tap) ──────────────────────
  Future<void> _showWorkerDetailSheet(
    AttendanceRecord record,
    AttendanceModel? today,
    WeeklyWorkerRow? weeklyRow,
    List<({DateTime date, AttendanceRecord rec})> history,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _WorkerDetailSheet(
        record: record,
        weeklyRow: weeklyRow,
        history: history,
        calcHours: _calcHours,
        calcStatus: _calcStatus,
        fmtTime: _fmtTime,
        onDayTap: weeklyRow == null
            ? null
            : (cell) {
                Navigator.of(context).pop(); // close sheet first
                _showDayActionSheet(weeklyRow, cell);
              },
      ),
    );
  }

  Future<void> _registerWorker() async {
    final result = await showModalBottomSheet<ManualWorkerInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _RegisterWorkerSheet(),
    );
    if (!mounted || result == null) return;

    final att = await _getOrCreate(_selectedDate);
    if (att == null || _projectId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No project assigned.')));
      }
      return;
    }
    final name = result.workerName.trim();
    if (name.isEmpty) return;

    final roster = _registry.loadRoster(_projectId!);
    if (roster.any((w) => w.workerName.toLowerCase() == name.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name is already registered.')));
      }
      return;
    }

    await _registry.registerWorker(
      projectId: _projectId!,
      workerName: name,
      position: result.position,
      rate: result.rate,
    );

    final newRoster = _registry.loadRoster(_projectId!);
    for (final w in newRoster) {
      final key = w.workerId.toLowerCase();
      final has = att.records.any((r) =>
          (r.workerId.isNotEmpty ? r.workerId : r.workerName).toLowerCase() == key);
      if (!has) att.records.add(_fromRegistered(w));
    }
    att.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(att);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name added to checklist.'),
        backgroundColor: AppTheme.softGreen,
      ));
    }
  }

  Future<void> _submitToAdmin(AttendanceModel att) async {
    setState(() => _submitting = true);
    try {
      final geoTag = await GeoTagService.instance.captureGeoTag();
      att.status = 'submitted';
      att.syncStatus = 'pending';
      att.updatedAt = DateTime.now();
      await HiveService.instance.saveAttendance(att);

      await AuditLogService.instance.logAction(
        action: 'attendance_submitted',
        projectId: att.projectId,
        details: {
          'attendanceId': att.id,
          'attendanceDate': att.attendanceDate.toIso8601String(),
          'totalWorkers': att.totalWorkers,
          'presentWorkers': att.presentWorkers,
          'geoTag': geoTag,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Attendance submitted to Admin.'),
        backgroundColor: AppTheme.softGreen,
      ));

      final sync = await SyncService.instance.syncPendingData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sync.message),
          backgroundColor:
              sync.success ? AppTheme.softGreen : AppTheme.warningOrange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Submit failed: $e'),
            backgroundColor: AppTheme.errorRed));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;
    final projectId = user?.assignedProjects.isNotEmpty == true
        ? user!.assignedProjects.first : _projectId;
    if (projectId != null) _projectId = projectId;

    final roster = projectId != null
        ? _registry.loadRoster(projectId) : <RegisteredWorker>[];

    final allAtt = (user == null
        ? hive.getAllAttendance()
        : hive.getAttendanceByRecorder(user.id))
      ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

    AttendanceModel? today;
    for (final a in allAtt) {
      if (_sameDay(a.attendanceDate, _norm(_selectedDate))) { today = a; break; }
    }

    final records = today?.records.isNotEmpty == true
        ? today!.records
        : roster.map(_fromRegistered).toList();

    final presentCount = records.where((r) => r.isPresent || r.timeIn != null).length;
    final absentCount = records.length - presentCount;

    final weeklyRows = WeeklyAttendanceService().buildWeeklyRows(
      allAttendance: allAtt,
      weekAnchor: _selectedDate,
      roster: roster,
    );

    final weeklyRowByKey = {
      for (final row in weeklyRows)
        _workerKeyFromName(row.workerName): row,
    };

    // History: group all past records per worker
    final Map<String, List<({DateTime date, AttendanceRecord rec})>> workerHistory = {};
    for (final a in allAtt) {
      for (final r in a.records) {
        final key = r.workerId.isNotEmpty ? r.workerId : r.workerName;
        workerHistory.putIfAbsent(key, () => []).add((date: a.attendanceDate, rec: r));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Site attendance',
            style: TextStyle(fontWeight: FontWeight.w900)),
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(RouteNames.siteManagerHome))
            : null,
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 16, color: Colors.white),
            label: Text(
              '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 110 + MediaQuery.of(context).padding.bottom),
                                    children: [
          // ── Register worker card ────────────────────────────────────────
          _RegisterCard(onTap: _registerWorker),
          const SizedBox(height: 20),

          // ── Summary chips ───────────────────────────────────────────────
          _SummaryRow(
            total: records.length,
            present: presentCount,
            absent: absentCount,
          ),
          const SizedBox(height: 16),

          // ── Section header ──────────────────────────────────────────────
          _SectionHeader(title: "Today's checklist",
              subtitle: _fmtDate(_selectedDate)),
          const SizedBox(height: 8),

          if (records.isEmpty)
            _EmptyChecklist(onAdd: _registerWorker)
          else
            ...records.map((r) {
              final recordKey = _workerKeyFromRecord(r);
              final weeklyRow = weeklyRowByKey[recordKey];
              final isExpanded = _expandedWorkerId == recordKey;
              final hist = (workerHistory[
                    r.workerId.isNotEmpty ? r.workerId : r.workerName
                  ] ?? [])
                ..sort((a, b) => b.date.compareTo(a.date));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WorkerCard(
                  record: r,
                  attendance: today,
                  fmtTime: _fmtTime,
                  calcHours: _calcHours,
                  calcStatus: _calcStatus,
                  weeklyRow: weeklyRow,
                  isExpanded: isExpanded,
                  onToggleExpanded: weeklyRow == null
                      ? null
                      : () => setState(() =>
                          _expandedWorkerId = isExpanded ? null : recordKey),
                  onWorkerTap: () => _showWorkerDetailSheet(
                      r, today, weeklyRow, hist),
                  onDayTap: weeklyRow == null
                      ? null
                      : (cell) => _showDayActionSheet(weeklyRow, cell),
                  onAmIn: today == null ? null : () => _pickAmPm(today!, r, 'amIn'),
                  onAmOut: today == null ? null : () => _pickAmPm(today!, r, 'amOut'),
                  onPmIn: today == null ? null : () => _pickAmPm(today!, r, 'pmIn'),
                  onPmOut: today == null ? null : () => _pickAmPm(today!, r, 'pmOut'),
                  onPresent: today == null ? null : () => _markPresent(today!, r),
                  onLate: today == null ? null : () => _markLate(today!, r),
                  onAbsent: today == null ? null : () => _markAbsent(today!, r),
                  onRemove: today == null ? null : () => _removeWorker(today!, r),
                ),
              );
            }),

          const SizedBox(height: 24),

          // ── Attendance history ──────────────────────────────────────────
          _SectionHeader(title: 'Attendance history'),
          const SizedBox(height: 8),

          if (roster.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No workers registered yet.',
                  style: TextStyle(color: AppTheme.mediumGray)),
            )
          else
            ...roster.map((w) {
              final key = w.workerId;
              final hist = (workerHistory[key] ?? [])
                ..sort((a, b) => b.date.compareTo(a.date));
              final isOpen = _historyWorkerId == key;
              return _HistorySection(
                worker: w,
                history: hist,
                isOpen: isOpen,
                onToggle: () => setState(() =>
                    _historyWorkerId = isOpen ? null : key),
                fmtDate: (d) =>
                    '${d.month.toString().padLeft(2,'0')}/'
                    '${d.day.toString().padLeft(2,'0')}/'
                    '${d.year}',
                calcHours: _calcHours,
                calcStatus: _calcStatus,
              );
            }),
        ],
      ),

      // ── Submit to Admin button ──────────────────────────────────────────
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
                          color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: (today == null || _submitting)
                    ? null
                    : () => _submitToAdmin(today!),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _submitting ? 'Submitting…' : 'Submit to Admin',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ),
            ),
          if (widget.showBottomNav)
            const SiteManagerBottomNav(currentIndex: 2),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _RegisterCard extends StatelessWidget {
  const _RegisterCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
        children: [
              Container(
                padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.residentBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_alt,
                    color: AppTheme.residentBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text('Register worker',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    Text('Tap to add a new worker to the roster',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppTheme.mediumGray)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.mediumGray),
                ],
              ),
            ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.total, required this.present,
      required this.absent});
  final int total; final int present; final int absent;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String val, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
            Text(val, style: TextStyle(fontWeight: FontWeight.w900,
                fontSize: 20, color: color)),
            Text(label, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: AppTheme.mediumGray)),
                        ],
                      ),
                    ),
    );
    return Row(
                        children: [
        chip('Total', '$total', AppTheme.residentBlue),
        const SizedBox(width: 8),
        chip('Present', '$present', const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        chip('Absent', '$absent', const Color(0xFFEF4444)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title; final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
            children: [
      Expanded(child: Text(title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900))),
      if (subtitle != null)
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppTheme.mediumGray)),
    ],
  );
}

class _EmptyChecklist extends StatelessWidget {
  const _EmptyChecklist({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 48,
              color: AppTheme.mediumGray.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('No workers yet', style: Theme.of(context)
              .textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Register workers to start the checklist.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.mediumGray)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onAdd,
              icon: const Icon(Icons.person_add),
              label: const Text('Register Worker')),
        ],
      ),
      ),
    );
  }


// ── Worker checklist card ─────────────────────────────────────────────────────
class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.record,
    required this.attendance,
    required this.fmtTime,
    required this.calcHours,
    required this.calcStatus,
    this.weeklyRow,
    this.isExpanded = false,
    this.onToggleExpanded,
    this.onWorkerTap,
    this.onDayTap,
    this.onAmIn, this.onAmOut, this.onPmIn, this.onPmOut,
    this.onPresent, this.onLate, this.onAbsent, this.onRemove,
  });

  final AttendanceRecord record;
  final AttendanceModel? attendance;
  final WeeklyWorkerRow? weeklyRow;
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onWorkerTap;
  final void Function(WeeklyDayCell cell)? onDayTap;
  final String Function(DateTime?) fmtTime;
  final double Function(AttendanceRecord) calcHours;
  final String Function(AttendanceRecord) calcStatus;
  final VoidCallback? onAmIn, onAmOut, onPmIn, onPmOut;
  final VoidCallback? onPresent, onLate, onAbsent, onRemove;

  static String _initials(String name) {
    final p = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    if (p.length == 1) return p[0][0].toUpperCase();
    return '${p[0][0]}${p[1][0]}'.toUpperCase();
  }

  Color _statusColor(String s) => switch (s) {
    'Present'  => const Color(0xFF16A34A),
    'Late'     => const Color(0xFFF97316),
    'Half day' => const Color(0xFFF59E0B),
    'Absent'   => const Color(0xFFEF4444),
    _          => const Color(0xFF94A3B8),
  };

  IconData _statusIcon(String s) => switch (s) {
    'Present'  => Icons.check_circle_outline,
    'Late'     => Icons.schedule,
    'Half day' => Icons.timelapse,
    'Absent'   => Icons.cancel_outlined,
    _          => Icons.radio_button_unchecked,
  };

  @override
  Widget build(BuildContext context) {
    final status = calcStatus(record);
    final color = _statusColor(status);
    final hours = calcHours(record);
    final canEdit = attendance != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            // Header row
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.residentBlue.withValues(alpha: 0.1),
                child: Text(_initials(record.workerName),
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        color: AppTheme.residentBlue, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
                child: InkWell(
                  onTap: onWorkerTap ?? onToggleExpanded,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                        Row(children: [
                              Expanded(
                            child: Text(record.workerName,
                                  style: Theme.of(context)
                                    .textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900)),
                          ),
                          if (onWorkerTap != null)
                            const Icon(Icons.open_in_new,
                                size: 14, color: AppTheme.mediumGray),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          record.position.trim().isEmpty ? 'Worker' : record.position,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                        if (record.rate > 0)
                          Text('₱${record.rate.toStringAsFixed(0)}/day',
                              style: const TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7C3AED))),
                            ],
                          ),
                        ),
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_statusIcon(status), size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(status, style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                ]),
              ),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 20),
                  onPressed: onRemove,
                ),
            ]),
            const SizedBox(height: 12),

            if (weeklyRow != null) ...[
              InkWell(
                onTap: onToggleExpanded,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                  children: [
                      Expanded(
                        child: Text(
                          'Weekly details',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppTheme.mediumGray,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 12),
                _WeeklyDayRow(
                  row: weeklyRow!,
                  onDayTap: onDayTap,
                ),
                const SizedBox(height: 12),
              ],
            ],

            // AM / PM time chips
            Row(children: [
              Expanded(child: _TimeChip(label: 'AM In',
                  time: record.amTimeIn, fmtTime: fmtTime,
                  color: AppTheme.residentBlue, onTap: onAmIn)),
              const SizedBox(width: 6),
              Expanded(child: _TimeChip(label: 'AM Out',
                  time: record.amTimeOut, fmtTime: fmtTime,
                  color: const Color(0xFF7C3AED), onTap: onAmOut)),
              const SizedBox(width: 6),
              Expanded(child: _TimeChip(label: 'PM In',
                  time: record.pmTimeIn, fmtTime: fmtTime,
                  color: const Color(0xFF059669), onTap: onPmIn)),
              const SizedBox(width: 6),
              Expanded(child: _TimeChip(label: 'PM Out',
                  time: record.pmTimeOut, fmtTime: fmtTime,
                  color: const Color(0xFFD97706), onTap: onPmOut)),
            ]),
            const SizedBox(height: 8),

            // Hours + pay estimate
            Row(children: [
              const Icon(Icons.access_time, size: 14, color: AppTheme.mediumGray),
              const SizedBox(width: 5),
              Text('$hours hrs today',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, color: AppTheme.mediumGray)),
              if (hours > 0 && record.rate > 0) ...[
                          const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '≈ ₱${(record.rate * (hours / 8)).round()}',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                  ),
                ),
              ],
            ]),

            // Quick-mark buttons
            if (canEdit) ...[
              const SizedBox(height: 10),
              Row(children: [
                _QuickBtn(label: 'Present', icon: Icons.check_circle_outline,
                    color: const Color(0xFF16A34A),
                    selected: (record.isPresent || record.timeIn != null) &&
                        !(record.remarks ?? '').contains('late'),
                    onTap: onPresent),
                const SizedBox(width: 8),
                _QuickBtn(label: 'Late', icon: Icons.schedule,
                    color: const Color(0xFFF97316),
                    selected: (record.remarks ?? '').contains('late'),
                    onTap: onLate),
                const SizedBox(width: 8),
                _QuickBtn(label: 'Absent', icon: Icons.cancel_outlined,
                    color: const Color(0xFFEF4444),
                    selected: !(record.isPresent || record.timeIn != null) &&
                        (record.remarks ?? '').contains('absent'),
                    onTap: onAbsent),
              ]),
            ],
                  ],
                ),
              ),
            );
  }
}

class _WeeklyDayRow extends StatelessWidget {
  const _WeeklyDayRow({
    required this.row,
    required this.onDayTap,
  });

  final WeeklyWorkerRow row;
  final void Function(WeeklyDayCell cell)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final days = row.days;
    return Container(
      width: double.infinity,
              decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
                    children: [
                      Expanded(
                  child: Text('Mon–Sat attendance',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                            Text(
                  '${row.presentCount}/${row.workDays}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                        color: AppTheme.mediumGray,
                                      ),
                            ),
                          ],
                        ),
                      ),
          const Divider(height: 1, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
              children: days.map((cell) {
                final status = cell.status;
                final style = _dayStatusStyle(status);
                return Material(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onDayTap != null ? () => onDayTap!(cell) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 96,
                      height: 76,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text(
                              WeeklyAttendanceService.formatDayHeader(cell.date).split('\n').first,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              style.label,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                    color: style.fg,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cell.timeLabel ?? style.label,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: style.fg.withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                                          ),
                                ),
                              ),
                        ),
                );
              }).toList(),
                      ),
                  ),
                ],
      ),
    );
  }

  _DayStyle _dayStatusStyle(WeeklyDayStatus status) {
    switch (status) {
      case WeeklyDayStatus.present:
        return const _DayStyle(
          bg: Color(0xFFDCFCE7),
          fg: Color(0xFF166534),
          label: 'Present',
        );
      case WeeklyDayStatus.late:
        return const _DayStyle(
          bg: Color(0xFFFEF3C7),
          fg: Color(0xFFB45309),
          label: 'Late',
        );
      case WeeklyDayStatus.absent:
        return const _DayStyle(
          bg: Color(0xFFFEE2E2),
          fg: Color(0xFFB91C1C),
          label: 'Absent',
        );
      case WeeklyDayStatus.dayOff:
        return const _DayStyle(
          bg: Color(0xFFF1F5F9),
          fg: Color(0xFF334155),
          label: 'Day Off',
        );
      case WeeklyDayStatus.pending:
        return const _DayStyle(
          bg: Color(0xFFF8FAFC),
          fg: Color(0xFF64748B),
          label: 'Pending',
        );
    }
  }
}

class _DayStyle {
  const _DayStyle({
    required this.bg,
    required this.fg,
    required this.label,
  });
  final Color bg;
  final Color fg;
  final String label;
}

// ── Time chip ─────────────────────────────────────────────────────────────────
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label, required this.time,
    required this.fmtTime, required this.color, this.onTap,
  });
  final String label;
  final DateTime? time;
  final String Function(DateTime?) fmtTime;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = time != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: has ? color.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: has ? color.withValues(alpha: 0.45) : const Color(0xFFE2E8F0)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: has ? color : AppTheme.mediumGray)),
          const SizedBox(height: 3),
          Text(fmtTime(time),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: has ? color : AppTheme.mediumGray)),
        ]),
      ),
    );
  }
}

// ── Quick mark button ─────────────────────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  const _QuickBtn({required this.label, required this.icon,
      required this.color, required this.selected, this.onTap});
  final String label; final IconData icon;
  final Color color; final bool selected; final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: selected ? color.withValues(alpha: 0.14) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : const Color(0xFFE2E8F0)),
          ),
          child: Column(children: [
            Icon(icon, size: 17,
                color: selected ? color : AppTheme.mediumGray),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? color : AppTheme.mediumGray)),
          ]),
        ),
      ),
    ),
  );
}

// ── History section ───────────────────────────────────────────────────────────
class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.worker, required this.history,
    required this.isOpen, required this.onToggle,
    required this.fmtDate, required this.calcHours, required this.calcStatus,
  });
  final RegisteredWorker worker;
  final List<({DateTime date, AttendanceRecord rec})> history;
  final bool isOpen;
  final VoidCallback onToggle;
  final String Function(DateTime) fmtDate;
  final double Function(AttendanceRecord) calcHours;
  final String Function(AttendanceRecord) calcStatus;

  Color _statusColor(String s) => switch (s) {
    'Present'  => const Color(0xFF16A34A),
    'Late'     => const Color(0xFFF97316),
    'Half day' => const Color(0xFFF59E0B),
    'Absent'   => const Color(0xFFEF4444),
    _          => const Color(0xFF94A3B8),
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // Toggle header
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                    backgroundColor:
                      AppTheme.residentBlue.withValues(alpha: 0.1),
                  child: Text(
                    worker.workerName.isNotEmpty
                        ? worker.workerName[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        color: AppTheme.residentBlue, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.workerName,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${history.length} records · '
                        '₱${worker.rate.toStringAsFixed(0)}/day',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.mediumGray)),
                  ],
                )),
                Icon(isOpen ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.mediumGray),
              ]),
            ),
          ),
          // History rows
          if (isOpen) ...[
            const Divider(height: 1, thickness: 0.5,
                indent: 14, endIndent: 14),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No past records yet.',
                    style: TextStyle(color: AppTheme.mediumGray)),
              )
            else
              ...history.take(15).map((h) {
                final hrs = calcHours(h.rec);
                final pay = hrs > 0 && worker.rate > 0
                    ? (worker.rate * (hrs / 8)).round() : 0;
                final st = calcStatus(h.rec);
                final sc = _statusColor(st);
                return ListTile(
                  dense: true,
                  title: Text(fmtDate(h.date),
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  subtitle: Text('$hrs hrs${pay > 0 ? " · ₱$pay" : ""}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(st, style: TextStyle(
                        color: sc, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}

// ── Register worker bottom sheet ──────────────────────────────────────────────
class _RegisterWorkerSheet extends StatefulWidget {
  const _RegisterWorkerSheet();
  @override
  State<_RegisterWorkerSheet> createState() => _RegisterWorkerSheetState();
}

class _RegisterWorkerSheetState extends State<_RegisterWorkerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '450');
  String _position = 'Laborer';

  static const _positions = [
    'Laborer', 'Mason', 'Carpenter', 'Electrician', 'Plumber',
    'Steelman', 'Foreman', 'Heavy equipment operator', 'Site Engineer', 'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose(); _rateCtrl.dispose(); super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
    Navigator.pop(context, ManualWorkerInput(
      workerName: _nameCtrl.text.trim(),
      position: _position,
      rate: rate,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.residentBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_alt,
                      color: AppTheme.residentBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Text('Register worker',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 16),
              // Full name
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  hintText: 'Juan dela Cruz',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              // Position
              DropdownButtonFormField<String>(
                initialValue: _position,
                decoration: InputDecoration(
                  labelText: 'Position',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                items: _positions.map((p) =>
                    DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) =>
                    setState(() => _position = v ?? 'Laborer'),
              ),
              const SizedBox(height: 12),
              // Daily rate
              TextFormField(
                controller: _rateCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Daily rate',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                validator: (v) {
                  final r = double.tryParse((v ?? '').trim());
                  if (r == null || r <= 0) {
                    return 'Enter a valid rate';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.residentBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Add worker',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Worker detail sheet ───────────────────────────────────────────────────────
class _WorkerDetailSheet extends StatelessWidget {
  const _WorkerDetailSheet({
    required this.record,
    required this.weeklyRow,
    required this.history,
    required this.calcHours,
    required this.calcStatus,
    required this.fmtTime,
    this.onDayTap,
  });

  final AttendanceRecord record;
  final WeeklyWorkerRow? weeklyRow;
  final List<({DateTime date, AttendanceRecord rec})> history;
  final double Function(AttendanceRecord) calcHours;
  final String Function(AttendanceRecord) calcStatus;
  final String Function(DateTime?) fmtTime;
  final void Function(WeeklyDayCell cell)? onDayTap;

  static String _initials(String name) {
    final p = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    if (p.length == 1) return p[0][0].toUpperCase();
    return '${p[0][0]}${p[1][0]}'.toUpperCase();
  }

  Color _statusColor(String s) => switch (s) {
        'Present' => const Color(0xFF16A34A),
        'Late' => const Color(0xFFF97316),
        'Half day' => const Color(0xFFF59E0B),
        'Absent' => const Color(0xFFEF4444),
        _ => const Color(0xFF94A3B8),
      };

  _DayStyle _dayStyle(WeeklyDayStatus s) {
    switch (s) {
      case WeeklyDayStatus.present:
        return const _DayStyle(bg: Color(0xFFDCFCE7), fg: Color(0xFF166534), label: 'P');
      case WeeklyDayStatus.late:
        return const _DayStyle(bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309), label: 'L');
      case WeeklyDayStatus.absent:
        return const _DayStyle(bg: Color(0xFFFEE2E2), fg: Color(0xFFB91C1C), label: 'A');
      case WeeklyDayStatus.dayOff:
        return const _DayStyle(bg: Color(0xFFF1F5F9), fg: Color(0xFF94A3B8), label: '-');
      case WeeklyDayStatus.pending:
        return const _DayStyle(bg: Color(0xFFF8FAFC), fg: Color(0xFF94A3B8), label: '?');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = record.rate;

    // Weekly salary calculation
    double weeklyHours = 0;
    double weeklySalary = 0;
    if (weeklyRow != null) {
      for (final day in weeklyRow!.days) {
        if (day.record != null &&
            (day.status == WeeklyDayStatus.present ||
                day.status == WeeklyDayStatus.late)) {
          final h = calcHours(day.record!);
          weeklyHours += h;
          if (rate > 0) weeklySalary += rate * (h / 8);
        } else if (day.status == WeeklyDayStatus.present ||
            day.status == WeeklyDayStatus.late) {
          // No record but marked present — count as full day
          weeklyHours += 8;
          if (rate > 0) weeklySalary += rate;
        }
      }
    }

    // All-time totals from history
    double totalHoursAllTime = 0;
    double totalSalaryAllTime = 0;
    int presentDays = 0;
    int absentDays = 0;
    for (final h in history) {
      final hrs = calcHours(h.rec);
      final st = calcStatus(h.rec);
      if (st != 'Absent') {
        totalHoursAllTime += hrs;
        if (rate > 0) totalSalaryAllTime += rate * (hrs / 8);
        presentDays++;
      } else {
        absentDays++;
      }
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // ── Worker header ───────────────────────────────────────────────
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.residentBlue.withValues(alpha: 0.10),
              child: Text(_initials(record.workerName),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.residentBlue,
                      fontSize: 18)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.workerName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(
                    record.position.isEmpty ? 'Worker' : record.position,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.mediumGray),
                  ),
                  if (rate > 0)
                    Text('₱${rate.toStringAsFixed(0)} / day',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF7C3AED))),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // ── All-time summary ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.residentBlue.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppTheme.residentBlue.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              _StatCell(label: 'Days worked', value: '$presentDays',
                  color: const Color(0xFF16A34A)),
              _StatCell(label: 'Days absent', value: '$absentDays',
                  color: const Color(0xFFEF4444)),
              _StatCell(
                  label: 'Total hours',
                  value: totalHoursAllTime.toStringAsFixed(1),
                  color: AppTheme.residentBlue),
              if (rate > 0)
                _StatCell(
                    label: 'Earned (est.)',
                    value: '₱${totalSalaryAllTime.round()}',
                    color: const Color(0xFF7C3AED)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Weekly Mon–Sat grid ─────────────────────────────────────────
          if (weeklyRow != null) ...[
            Row(children: [
              Expanded(
                child: Text('This week',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ),
              Text(
                '${weeklyRow!.presentCount} / ${weeklyRow!.workDays} days  ·  '
                '${weeklyHours.toStringAsFixed(1)} hrs'
                '${rate > 0 ? "  ·  ₱${weeklySalary.round()}" : ""}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mediumGray),
              ),
            ]),
            const SizedBox(height: 10),
            // Day cells
            Row(
              children: weeklyRow!.days.map((cell) {
                final style = _dayStyle(cell.status);
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                final dayLabel = days[cell.date.weekday - 1];
                final dateLabel =
                    '${cell.date.month}/${cell.date.day}';
                final hrs = cell.record != null
                    ? calcHours(cell.record!)
                    : (cell.status == WeeklyDayStatus.present ||
                            cell.status == WeeklyDayStatus.late
                        ? 8.0
                        : 0.0);
                final pay = rate > 0 && hrs > 0
                    ? '₱${(rate * hrs / 8).round()}'
                    : '';
                return Expanded(
                  child: GestureDetector(
                    onTap: onDayTap != null ? () => onDayTap!(cell) : null,
                    child: Container(
                      margin: const EdgeInsets.only(right: 5),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: style.bg,
                      borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: style.fg.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(dayLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: style.fg)),
                          Text(dateLabel,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: style.fg.withValues(alpha: 0.7))),
                          const SizedBox(height: 6),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: style.fg.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(style.label,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: style.fg)),
                            ),
                          ),
                          if (hrs > 0) ...[
                            const SizedBox(height: 4),
                            Text('${hrs.toStringAsFixed(0)}h',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: style.fg)),
                          ],
                          if (pay.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(pay,
                                style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C3AED))),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text('Tap a day to update attendance',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppTheme.mediumGray)),
            const SizedBox(height: 20),
          ],

          // ── History ─────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text('Attendance history',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ),
            Text('${history.length} records',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w600)),
          ]),
              const SizedBox(height: 8),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No records yet.',
                  style: TextStyle(color: AppTheme.mediumGray)),
            )
          else
            ...history.take(30).map((h) {
              final hrs = calcHours(h.rec);
              final st = calcStatus(h.rec);
              final sc = _statusColor(st);
              final pay = hrs > 0 && rate > 0
                  ? (rate * hrs / 8).round()
                  : 0;
              final d = h.date;
              final dateStr =
                  '${d.month.toString().padLeft(2, '0')}/'
                  '${d.day.toString().padLeft(2, '0')}/'
                  '${d.year}';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateStr,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        Text(
                          '$hrs hrs'
                          '${pay > 0 ? " · ₱$pay estimated" : ""}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.mediumGray),
                        ),
            ],
          ),
        ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(st,
                        style: TextStyle(
                            color: sc,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: color)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.mediumGray)),
        ]),
      );
}
