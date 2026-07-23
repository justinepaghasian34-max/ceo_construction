import 'attendance_worker_registry_service.dart';
import '../models/attendance_model.dart';

/// Daily attendance status for weekly checklist grid.
enum WeeklyDayStatus {
  present,
  late,
  absent,
  dayOff,
  pending,
}

class WeeklyDayCell {
  const WeeklyDayCell({
    required this.date,
    required this.status,
    this.timeLabel,
    this.record,
  });

  final DateTime date;
  final WeeklyDayStatus status;
  final String? timeLabel;
  final AttendanceRecord? record;
}

class WeeklyWorkerRow {
  const WeeklyWorkerRow({
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.days,
    required this.presentCount,
    required this.workDays,
    required this.ratePercent,
    this.templateRecord,
  });

  final String workerId;
  final String workerName;
  final String position;
  final List<WeeklyDayCell> days;
  final int presentCount;
  final int workDays;
  final double ratePercent;
  final AttendanceRecord? templateRecord;
}

class WeeklyAttendanceService {
  WeeklyAttendanceService({
    this.lateAfterHour = 8,
    this.lateAfterMinute = 15,
  });

  final int lateAfterHour;
  final int lateAfterMinute;

  static DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime startOfWeek(DateTime d) {
    final date = normalizeDate(d);
    final delta = date.weekday - DateTime.monday;
    return date.subtract(Duration(days: delta < 0 ? 6 : delta));
  }

  /// Mon–Sat (6 work days) for the week containing [anchor].
  static List<DateTime> workDaysInWeek(DateTime anchor) {
    final start = startOfWeek(anchor);
    return List.generate(6, (i) => start.add(Duration(days: i)));
  }

  static String formatWeekRange(DateTime anchor) {
    final days = workDaysInWeek(anchor);
    final start = days.first;
    final end = days.last;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String part(DateTime d) => '${months[d.month - 1]} ${d.day}';
    return '${part(start)} – ${part(end)}, ${start.year}';
  }

  static String formatDayHeader(DateTime d) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label = labels[d.weekday - 1];
    return '$label\n${d.month}/${d.day}';
  }

  static String formatTime12(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final hour12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final ap = h >= 12 ? 'PM' : 'AM';
    return '$hour12:$m $ap';
  }

  bool _isLate(DateTime timeIn) {
    final threshold = DateTime(
      timeIn.year,
      timeIn.month,
      timeIn.day,
      lateAfterHour,
      lateAfterMinute,
    );
    return timeIn.isAfter(threshold);
  }

  AttendanceRecord? _recordForWorkerOnDay(
    List<AttendanceModel> allAttendance,
    String workerKey,
    DateTime day,
  ) {
    final normalized = workerKey.trim().toLowerCase();
    for (final model in allAttendance) {
      if (!isSameDay(model.attendanceDate, day)) continue;
      for (final r in model.records) {
        final key = (r.workerId.trim().isNotEmpty
                ? r.workerId
                : r.workerName)
            .trim()
            .toLowerCase();
        if (key == normalized) return r;
      }
    }
    return null;
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  WeeklyDayStatus resolveStatus({
    required AttendanceRecord? record,
    required DateTime day,
    required DateTime today,
    DateTime? registeredAt,
  }) {
    final d = normalizeDate(day);
    final now = normalizeDate(today);

    if (registeredAt != null && d.isBefore(normalizeDate(registeredAt))) {
      return WeeklyDayStatus.dayOff;
    }
    if (d.isAfter(now)) {
      return WeeklyDayStatus.dayOff;
    }

    if (record == null) {
      if (d.isBefore(now)) return WeeklyDayStatus.absent;
      return WeeklyDayStatus.pending;
    }

    final remarks = (record.remarks ?? '').toLowerCase();
    if (remarks.contains('day_off') || remarks.contains('day off')) {
      return WeeklyDayStatus.dayOff;
    }

    final hasTime = record.timeIn != null;
    final present = record.isPresent || hasTime;

    if (!present) {
      if (remarks.contains('absent')) return WeeklyDayStatus.absent;
      if (d.isBefore(now)) return WeeklyDayStatus.absent;
      return WeeklyDayStatus.pending;
    }

    if (hasTime && _isLate(record.timeIn!)) {
      return WeeklyDayStatus.late;
    }
    return WeeklyDayStatus.present;
  }

  String? timeLabelFor(AttendanceRecord? record, WeeklyDayStatus status) {
    if (record?.timeIn == null) return null;
    if (status == WeeklyDayStatus.present || status == WeeklyDayStatus.late) {
      return formatTime12(record!.timeIn!);
    }
    return null;
  }

  List<WeeklyWorkerRow> buildWeeklyRows({
    required List<AttendanceModel> allAttendance,
    required DateTime weekAnchor,
    DateTime? registeredAtForWorker,
    Map<String, DateTime>? perWorkerRegisteredAt,
    List<RegisteredWorker>? roster,
  }) {
    final workDays = workDaysInWeek(weekAnchor);
    final today = DateTime.now();
    final weekStart = workDays.first;
    final weekEnd = workDays.last.add(const Duration(days: 1));

    final inWeek = allAttendance.where((a) {
      final d = normalizeDate(a.attendanceDate);
      return !d.isBefore(weekStart) && d.isBefore(weekEnd);
    }).toList();

    final workerKeys = <String, ({String id, String name, String position, AttendanceRecord? sample})>{};

    if (roster != null) {
      for (final w in roster) {
        final key = w.workerId.toLowerCase();
        workerKeys[key] = (
          id: w.workerId,
          name: w.workerName,
          position: w.position,
          sample: AttendanceRecord(
            workerId: w.workerId,
            workerName: w.workerName,
            position: w.position,
            rate: w.rate,
            workerType: w.position.toLowerCase(),
          ),
        );
      }
    }

    for (final model in inWeek) {
      for (final r in model.records) {
        final id = r.workerId.trim().isNotEmpty ? r.workerId.trim() : r.workerName.trim();
        final key = id.toLowerCase();
        if (key.isEmpty) continue;
        final existing = workerKeys[key];
        workerKeys[key] = (
          id: id,
          name: r.workerName.trim().isNotEmpty ? r.workerName.trim() : id,
          position: r.position.trim().isNotEmpty
              ? r.position.trim()
              : (existing?.position ?? 'Worker'),
          sample: existing?.sample ?? r,
        );
      }
    }

    if (workerKeys.isEmpty) {
      for (final model in allAttendance) {
        for (final r in model.records) {
          final id = r.workerId.trim().isNotEmpty ? r.workerId.trim() : r.workerName.trim();
          final key = id.toLowerCase();
          if (key.isEmpty) continue;
          workerKeys.putIfAbsent(
            key,
            () => (
              id: id,
              name: r.workerName.trim(),
              position: r.position.trim().isNotEmpty ? r.position.trim() : 'Worker',
              sample: r,
            ),
          );
        }
      }
    }

    final rows = <WeeklyWorkerRow>[];

    for (final entry in workerKeys.entries) {
      final key = entry.key;
      final meta = entry.value;
      final regAt = perWorkerRegisteredAt?[key] ?? registeredAtForWorker;

      final dayCells = <WeeklyDayCell>[];
      var presentCount = 0;

      for (final day in workDays) {
        final rec = _recordForWorkerOnDay(allAttendance, key, day);
        final status = resolveStatus(
          record: rec,
          day: day,
          today: today,
          registeredAt: regAt,
        );
        if (status == WeeklyDayStatus.present || status == WeeklyDayStatus.late) {
          presentCount++;
        }
        dayCells.add(
          WeeklyDayCell(
            date: day,
            status: status,
            timeLabel: timeLabelFor(rec, status),
            record: rec,
          ),
        );
      }

      const workDaysCount = 6;
      final rate = workDaysCount > 0 ? (presentCount / workDaysCount) * 100 : 0.0;

      rows.add(
        WeeklyWorkerRow(
          workerId: meta.id,
          workerName: meta.name,
          position: meta.position,
          days: dayCells,
          presentCount: presentCount,
          workDays: workDaysCount,
          ratePercent: rate,
          templateRecord: meta.sample,
        ),
      );
    }

    rows.sort((a, b) => a.workerName.toLowerCase().compareTo(b.workerName.toLowerCase()));
    return rows;
  }
}
