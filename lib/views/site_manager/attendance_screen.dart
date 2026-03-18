import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/hive_service.dart';
import '../../services/auth_service.dart';
import 'fingerprint_attendance_screen.dart';
import 'widgets/site_manager_bottom_nav.dart';
import 'widgets/site_manager_card.dart';
import '../../models/attendance_model.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  final bool showBottomNav;
  final bool showBack;

  const AttendanceScreen({
    super.key,
    this.showBottomNav = false,
    this.showBack = true,
  });

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  final _searchController = TextEditingController();
  String _positionFilter = 'All';
  DateTime _selectedDate = DateTime.now();

  static const String _kLastFingerprintWorkerKey = 'fingerprint_last_worker';
  static const String _kFingerprintRegisteredWorkersKey =
      'fingerprint_registered_workers';

  DateTime _startOfWeek(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    final delta = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: delta < 0 ? 6 : delta));
  }

  WorkerFingerprintArgs? _lastWorkerArgs() {
    final raw = HiveService.instance.getSetting<Map>(_kLastFingerprintWorkerKey);
    if (raw == null) return null;

    final name = (raw['workerName'] ?? '').toString().trim();
    final position = (raw['position'] ?? '').toString().trim();
    final rateRaw = raw['rate'];

    final rate = rateRaw is num
        ? rateRaw.toDouble()
        : double.tryParse(rateRaw?.toString() ?? '');

    if (name.isEmpty || position.isEmpty || rate == null) return null;
    return WorkerFingerprintArgs(workerName: name, position: position, rate: rate);
  }

  Future<WorkerFingerprintArgs?> _inferWorkerArgsFromTodayAttendance() async {
    final attendance = await _getOrCreateTodayAttendance();
    if (attendance == null) return null;
    if (attendance.records.isEmpty) return null;

    final r = attendance.records.first;
    final name = r.workerName.trim();
    final position = r.position.trim();
    final rate = r.rate;
    if (name.isEmpty || position.isEmpty) return null;
    return WorkerFingerprintArgs(workerName: name, position: position, rate: rate);
  }

  Future<void> _openFingerprintDailyAttendance(BuildContext context) async {
    final router = GoRouter.of(context);
    var args = _lastWorkerArgs();
    args ??= await _inferWorkerArgsFromTodayAttendance();
    if (!context.mounted) return;
    if (args == null) {
      await _showRegisterWorkerFingerprintSheet(context);
      return;
    }

    await HiveService.instance.saveSetting(_kLastFingerprintWorkerKey, {
      'workerName': args.workerName,
      'position': args.position,
      'rate': args.rate,
    });

    if (!context.mounted) return;
    await router.push(RouteNames.fingerprintAttendance, extra: args);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showRegisterWorkerFingerprintSheet(BuildContext context) async {
    final result = await showModalBottomSheet<WorkerFingerprintArgs>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _RegisterWorkerFingerprintSheet(),
    );

    if (!context.mounted || result == null) return;

    final normalizedName = result.workerName.trim().toLowerCase();
    if (normalizedName.isEmpty) return;

    final hive = HiveService.instance;
    final rawRegistered =
        hive.getSetting<List>(_kFingerprintRegisteredWorkersKey) ?? const [];
    final registered = rawRegistered.map((e) => e.toString().toLowerCase()).toSet();

    if (!registered.contains(normalizedName)) {
      final allAttendance = hive.getAllAttendance();
      final hasExisting = allAttendance.any(
        (a) => a.records.any(
          (r) => r.workerName.trim().toLowerCase() == normalizedName,
        ),
      );
      if (hasExisting) {
        registered.add(normalizedName);
        await hive.saveSetting(
          _kFingerprintRegisteredWorkersKey,
          registered.toList()..sort(),
        );
      }
    }

    if (registered.contains(normalizedName)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worker fingerprint already registered.'),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    final upserted = await _upsertWorkerIntoTodayAttendance(result);
    if (!upserted) return;

    registered.add(normalizedName);
    await hive.saveSetting(
      _kFingerprintRegisteredWorkersKey,
      registered.toList()..sort(),
    );

    await HiveService.instance.saveSetting(_kLastFingerprintWorkerKey, {
      'workerName': result.workerName,
      'position': result.position,
      'rate': result.rate,
    });

    if (!context.mounted) return;

    context.push(RouteNames.fingerprintAttendance, extra: result);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickAttendanceDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = _normalizeDate(picked);
      });
    }
  }

  Future<AttendanceModel?> _getOrCreateTodayAttendance() async {
    var user = ref.read(currentUserProvider);
    final initialProjects = user?.assignedProjects;
    if (user == null || initialProjects == null || initialProjects.isEmpty) {
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
    final today = DateTime.now();

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
        remarks: r.remarks,
        amTimeIn: null,
        amTimeOut: null,
        pmTimeIn: null,
        pmTimeOut: null,
        workerType: r.workerType,
        rate: r.rate,
        monPresent: r.monPresent,
        tuePresent: r.tuePresent,
        wedPresent: r.wedPresent,
        thuPresent: r.thuPresent,
        friPresent: r.friPresent,
        satPresent: r.satPresent,
      );
    }

    final todayAttendance = existing.firstWhere(
      (a) => _isSameDay(a.attendanceDate, today),
      orElse: () {
        final startOfWeek = _startOfWeek(today);
        final previousInWeek = existing
            .where(
              (a) =>
                  a.projectId == projects.first &&
                  !a.attendanceDate.isAfter(
                    DateTime(today.year, today.month, today.day)
                        .subtract(const Duration(days: 1)),
                  ) &&
                  !a.attendanceDate.isBefore(startOfWeek),
            )
            .toList()
          ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

        final carriedRecords = previousInWeek.isEmpty
            ? <AttendanceRecord>[]
            : previousInWeek.first.records.map(cloneForNewDay).toList();

        return AttendanceModel(
          id: const Uuid().v4(),
          projectId: projects.first,
          recorderId: userId,
          attendanceDate: DateTime(today.year, today.month, today.day),
          records: carriedRecords,
          status: 'draft',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        );
      },
    );

    final isNew = hive.getAttendance(todayAttendance.id) == null;
    if (isNew) {
      await hive.saveAttendance(todayAttendance);
    }

    return todayAttendance;
  }

  Future<bool> _upsertWorkerIntoTodayAttendance(WorkerFingerprintArgs args) async {
    final attendance = await _getOrCreateTodayAttendance();
    if (attendance == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load project/user data.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return false;
    }

    final normalizedName = args.workerName.trim();
    if (normalizedName.isEmpty) return false;

    final existingIndex = attendance.records.indexWhere(
      (r) => r.workerName.trim().toLowerCase() == normalizedName.toLowerCase(),
    );

    if (existingIndex >= 0) {
      final r = attendance.records[existingIndex];
      r.position = args.position;
      r.rate = args.rate;
    } else {
      attendance.records.add(
        AttendanceRecord(
          workerId: normalizedName.toLowerCase(),
          workerName: normalizedName,
          position: args.position,
          rate: args.rate,
          workerType: args.position.toLowerCase(),
        ),
      );
    }

    attendance.updatedAt = DateTime.now();
    await HiveService.instance.saveAttendance(attendance);

    if (mounted) {
      setState(() {});
    }

    return true;
  }

  Future<void> _showWeeklyStatusSheet(
    BuildContext context,
    AttendanceRecord record,
  ) async {
    String labelFor(int weekday) {
      switch (weekday) {
        case DateTime.monday:
          return 'Monday';
        case DateTime.tuesday:
          return 'Tuesday';
        case DateTime.wednesday:
          return 'Wednesday';
        case DateTime.thursday:
          return 'Thursday';
        case DateTime.friday:
          return 'Friday';
        case DateTime.saturday:
          return 'Saturday';
        default:
          return '—';
      }
    }

    bool presentFor(int weekday) {
      switch (weekday) {
        case DateTime.monday:
          return record.monPresent;
        case DateTime.tuesday:
          return record.tuePresent;
        case DateTime.wednesday:
          return record.wedPresent;
        case DateTime.thursday:
          return record.thuPresent;
        case DateTime.friday:
          return record.friPresent;
        case DateTime.saturday:
          return record.satPresent;
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
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              18 + media.viewInsets.bottom,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 0,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.workerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppTheme.darkGray,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Monday to Saturday',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.mediumGray,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(6, (i) {
                          final weekday = DateTime.monday + i;
                          final isPresent = presentFor(weekday);
                          final color = isPresent
                              ? AppTheme.softGreen
                              : AppTheme.errorRed;
                          final icon =
                              isPresent ? Icons.check_circle : Icons.cancel;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.deepBlue
                                      .withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      labelFor(weekday),
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: AppTheme.darkGray,
                                          ),
                                    ),
                                  ),
                                  Icon(icon, color: color, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    isPresent ? 'Present' : 'Absent',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: color,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hive = HiveService.instance;

    final allAttendance = user == null
        ? hive.getAllAttendance()
        : hive.getAttendanceByRecorder(user.id);

    final attendanceList = allAttendance
      ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));

    final selectedDate = _normalizeDate(_selectedDate);
    final dayAttendance = attendanceList.where(
      (a) => _isSameDay(a.attendanceDate, selectedDate),
    );
    final activeAttendance = dayAttendance.isEmpty ? null : dayAttendance.first;

    final dateText = '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}';

    final records = activeAttendance?.records ?? const <AttendanceRecord>[];

    final uniquePositions = <String>{};
    for (final r in records) {
      final p = r.position.trim();
      if (p.isNotEmpty) uniquePositions.add(p);
    }
    final positions = ['All', ...uniquePositions.toList()..sort()];
    if (!positions.contains(_positionFilter)) {
      _positionFilter = 'All';
    }

    final rawQuery = _searchController.text.trim().toLowerCase();
    final filteredRecords = records.where((r) {
      if (_positionFilter != 'All' && r.position.trim() != _positionFilter) {
        return false;
      }
      if (rawQuery.isEmpty) return true;
      return r.workerName.toLowerCase().contains(rawQuery);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: 110 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              _buildHeader(
                context,
                dateText: dateText,
                showBack: widget.showBack,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: attendanceList.isEmpty
                    ? _buildEmptyState(context)
                    : Column(
                        children: [
                          _buildDatePickerRow(context, dateText: dateText),
                          const SizedBox(height: 12),
                          _buildFiltersRow(
                            context,
                            positions: positions,
                          ),
                          const SizedBox(height: 12),
                          ...filteredRecords.map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildWorkerRow(context, r),
                              )),
                          if (filteredRecords.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No workers match your filters.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.mediumGray),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: _buildSubmitAttendanceButton(context, attendance: activeAttendance),
          ),
        ],
      ),
      bottomNavigationBar:
          widget.showBottomNav ? const SiteManagerBottomNav(currentIndex: 2) : null,
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String dateText,
    required bool showBack,
  }) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16 + topInset, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.deepBlueDark,
            AppTheme.deepBlue,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBack)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.white),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'DAILY SITE ATTENDANCE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Menu',
                position: PopupMenuPosition.under,
                color: AppTheme.white,
                icon: const Icon(Icons.settings_outlined, color: AppTheme.white),
                onSelected: (value) {
                  switch (value) {
                    case 'register_fingerprint':
                      _showRegisterWorkerFingerprintSheet(context);
                      break;
                    case 'fingerprint_attendance':
                      _openFingerprintDailyAttendance(context);
                      break;
                    case 'settings':
                      context.push(RouteNames.settings);
                      break;
                  }
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem<String>(
                      value: 'register_fingerprint',
                      child: Row(
                        children: [
                          Icon(Icons.app_registration_outlined),
                          SizedBox(width: 10),
                          Text('Register Worker Fingerprint'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'fingerprint_attendance',
                      child: Row(
                        children: [
                          Icon(Icons.fingerprint),
                          SizedBox(width: 10),
                          Text('Fingerprint Daily Attendance'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings_outlined),
                          SizedBox(width: 10),
                          Text('Settings'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerRow(
    BuildContext context, {
    required String dateText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: AppTheme.deepBlue.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        onTap: () => _pickAttendanceDate(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.darkGray,
                      ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Text(
        'No attendance records yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.mediumGray,
              fontWeight: FontWeight.w700,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildFiltersRow(
    BuildContext context, {
    required List<String> positions,
  }) {
    Widget inputContainer({required Widget child}) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: AppTheme.deepBlue.withValues(alpha: 0.08),
          ),
        ),
        child: child,
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: inputContainer(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search Worker Name...',
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: inputContainer(
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: _positionFilter,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: positions
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p,
                          child: Row(
                            children: [
                              const Icon(Icons.badge_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _positionFilter = value;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkerRow(BuildContext context, AttendanceRecord record) {
    final initials = _initialsFor(record.workerName);
    final isPresent = record.isPresent;

    final statusColor = isPresent ? AppTheme.softGreen : AppTheme.errorRed;
    final statusIcon = isPresent ? Icons.check_circle : Icons.cancel;

    String statusText = isPresent ? 'Present' : 'Absent';
    if (isPresent && record.timeIn != null) {
      final t = TimeOfDay.fromDateTime(record.timeIn!);
      statusText = t.format(context);
    }

    final rateText = '₱${record.rate.toStringAsFixed(2)} / day';

    return InkWell(
      onTap: () => _showWeeklyStatusSheet(context, record),
      borderRadius: BorderRadius.circular(18),
      child: SiteManagerCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.deepBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.deepBlue,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.workerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkGray,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.position.trim().isEmpty ? '—' : record.position.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 82),
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                rateText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.warningOrange,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '—';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _buildSubmitAttendanceButton(
    BuildContext context, {
    required AttendanceModel? attendance,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: attendance == null
            ? null
            : () {
              final today = DateTime.now();
              if (today.weekday != DateTime.saturday) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Attendance submission is available on Saturday.'),
                    backgroundColor: AppTheme.warningOrange,
                  ),
                );
                return;
              }

              attendance.status = 'submitted';
              attendance.syncStatus = 'pending';
              attendance.updatedAt = DateTime.now();
              HiveService.instance.saveAttendance(attendance);

              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Attendance submitted to Admin.'),
                  backgroundColor: AppTheme.softGreen,
                ),
              );
            },
        icon: const Icon(Icons.send, size: 22),
        label: const Text('Submit Attendance to Admin'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.deepBlue,
          foregroundColor: AppTheme.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _RegisterWorkerFingerprintSheet extends StatefulWidget {
  const _RegisterWorkerFingerprintSheet();

  @override
  State<_RegisterWorkerFingerprintSheet> createState() =>
      _RegisterWorkerFingerprintSheetState();
}

class _RegisterWorkerFingerprintSheetState
    extends State<_RegisterWorkerFingerprintSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rateController = TextEditingController(text: '450');
  String _position = 'Foreman';

  static const _positionOptions = <String>[
    'Engineer',
    'Foreman',
    'Skilled',
    'Labor',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final rate = double.parse(_rateController.text.trim());
    final args = WorkerFingerprintArgs(
      workerName: _nameController.text.trim(),
      position: _position,
      rate: rate,
    );

    Navigator.of(context).pop(args);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 6,
          bottom: 16 + bottomInset,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Register Worker Fingerprint',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkGray,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Worker name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _position,
                items: _positionOptions
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(p),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _position = v;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Position',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                icon: const Icon(Icons.arrow_drop_down),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _rateController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Daily rate',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final rate = double.tryParse((v ?? '').trim());
                  if (rate == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text(
                    'Continue to fingerprint',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warningOrange,
                    foregroundColor: AppTheme.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
