import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../models/attendance_model.dart';
import 'widgets/site_manager_bottom_nav.dart';
import 'widgets/site_manager_card.dart';

class WorkerFingerprintArgs {
  final String workerName;
  final String position;
  final double rate;

  const WorkerFingerprintArgs({
    required this.workerName,
    required this.position,
    required this.rate,
  });
}

class FingerprintAttendanceScreen extends ConsumerStatefulWidget {
  final bool showBottomNav;
  final bool showBack;
  final WorkerFingerprintArgs? worker;

  const FingerprintAttendanceScreen({
    super.key,
    this.showBottomNav = true,
    this.showBack = true,
    this.worker,
  });

  @override
  ConsumerState<FingerprintAttendanceScreen> createState() =>
      _FingerprintAttendanceScreenState();
}

enum _FingerprintState {
  idle,
  scanning,
  success,
  failure,
}

class _FingerprintAttendanceScreenState
    extends ConsumerState<FingerprintAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glow;

  _FingerprintState _state = _FingerprintState.idle;
  DateTime? _recordedAt;
  Timer? _mockTimer;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _glow = CurvedAnimation(parent: _glowController, curve: Curves.easeInOut);
    _glowController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  String _formatTime(BuildContext context, DateTime time) {
    final t = TimeOfDay.fromDateTime(time);
    return t.format(context);
  }

  Future<void> _startMockScan() async {
    if (_state == _FingerprintState.scanning) return;

    if (widget.worker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register a worker first.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    _mockTimer?.cancel();
    setState(() {
      _state = _FingerprintState.scanning;
      _recordedAt = null;
    });

    _mockTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() {
        _state = _FingerprintState.success;
        _recordedAt = DateTime.now();
      });

      if (_state == _FingerprintState.success && _recordedAt != null) {
        _markPresentForSelectedWorker(_recordedAt!);

        final timeText = _formatTime(context, _recordedAt!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attendance Recorded – $timeText'),
            backgroundColor: AppTheme.softGreen,
          ),
        );
      }

      _mockTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _state = _FingerprintState.idle;
          _recordedAt = null;
        });
      });
    });
  }

  void _setWeekdayPresence(AttendanceRecord record, DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        record.monPresent = true;
        break;
      case DateTime.tuesday:
        record.tuePresent = true;
        break;
      case DateTime.wednesday:
        record.wedPresent = true;
        break;
      case DateTime.thursday:
        record.thuPresent = true;
        break;
      case DateTime.friday:
        record.friPresent = true;
        break;
      case DateTime.saturday:
        record.satPresent = true;
        break;
      case DateTime.sunday:
        break;
    }
  }

  Future<void> _markPresentForSelectedWorker(DateTime timeIn) async {
    final selectedName = widget.worker?.workerName.trim();
    if (selectedName == null || selectedName.isEmpty) return;

    final hive = HiveService.instance;
    final user = ref.read(currentUserProvider);
    final allAttendance = user == null
        ? hive.getAllAttendance()
        : hive.getAttendanceByRecorder(user.id);

    if (allAttendance.isEmpty) return;

    bool isSameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    final today = DateTime.now();
    final todayAttendance = allAttendance.firstWhere(
      (a) => isSameDay(a.attendanceDate, today),
      orElse: () {
        allAttendance.sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));
        return allAttendance.first;
      },
    );

    final activeAttendance = todayAttendance;

    final record = activeAttendance.records.firstWhere(
      (r) => r.workerName.trim().toLowerCase() == selectedName.toLowerCase(),
      orElse: () => AttendanceRecord(
        workerId: selectedName.toLowerCase(),
        workerName: selectedName,
        position: widget.worker?.position ?? '',
        rate: widget.worker?.rate ?? 0.0,
      ),
    );

    if (!activeAttendance.records.contains(record)) {
      activeAttendance.records.add(record);
    }

    record.isPresent = true;
    record.timeIn = timeIn;
    _setWeekdayPresence(record, DateTime.now());
    activeAttendance.updatedAt = DateTime.now();

    await hive.saveAttendance(activeAttendance);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final projectName =
        (user != null && user.assignedProjects.isNotEmpty)
            ? user.assignedProjects.first
            : 'No Project Assigned';

    final now = DateTime.now();
    final dateText = '${now.month}/${now.day}/${now.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.deepBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              )
            : null,
        title: const Text(
          'Fingerprint Attendance',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Notifications',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.warningOrange.withValues(alpha: 0.25),
              child: Text(
                (user?.displayName ?? 'U').trim().isEmpty
                    ? 'U'
                    : (user!.displayName.trim()[0].toUpperCase()),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.warningOrange,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$dateText  •  $projectName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _buildFingerprintSection(context),
        ],
      ),
      bottomNavigationBar:
          widget.showBottomNav ? const SiteManagerBottomNav(currentIndex: 2) : null,
    );
  }

  Widget _buildFingerprintSection(BuildContext context) {
    final isScanning = _state == _FingerprintState.scanning;
    final isSuccess = _state == _FingerprintState.success;
    final isFailure = _state == _FingerprintState.failure;

    return SiteManagerCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        children: [
          Text(
            'Scan Your Finger Print',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkGray,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _glow,
            builder: (context, _) {
              final glowStrength = isScanning ? 1.0 : 0.55;
              final t = _glow.value;
              final radius = 44.0 + (t * 10.0);
              final alpha = (0.18 + (t * 0.18)) * glowStrength;

              return GestureDetector(
                onTap: _startMockScan,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.deepBlue.withValues(alpha: 0.06),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.warningOrange.withValues(alpha: alpha),
                        blurRadius: radius,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    size: 72,
                    color: isSuccess
                        ? AppTheme.softGreen
                        : isFailure
                            ? AppTheme.errorRed
                            : AppTheme.deepBlue,
                  ),
                ),
              );
            },
          ),
          if (isScanning || isSuccess || isFailure)
            const SizedBox.shrink()
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
