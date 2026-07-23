import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/weekly_attendance_service.dart';

typedef WeeklyCellTap = void Function(
  WeeklyWorkerRow worker,
  WeeklyDayCell cell,
);

/// Academic-style weekly attendance matrix (Mon–Sat) for site managers.
class WeeklyAttendanceChecklist extends StatelessWidget {
  const WeeklyAttendanceChecklist({
    super.key,
    required this.weekAnchor,
    required this.rows,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onCellTap,
    this.onAddWorker,
  });

  final DateTime weekAnchor;
  final List<WeeklyWorkerRow> rows;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final WeeklyCellTap onCellTap;
  final VoidCallback? onAddWorker;

  static const double _workerColWidth = 148;
  static const double _dayColWidth = 72;
  static const double _summaryColWidth = 72;

  @override
  Widget build(BuildContext context) {
    final workDays = WeeklyAttendanceService.workDaysInWeek(weekAnchor);
    final rangeLabel = WeeklyAttendanceService.formatWeekRange(weekAnchor);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Weekly Attendance',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1E3A8A),
                            ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onPreviousWeek,
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous week',
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onNextWeek,
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next week',
                    ),
                  ],
                ),
                Text(
                  rangeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                const _StatusLegend(),
              ],
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.groups_outlined, size: 48, color: AppTheme.mediumGray.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No workers registered for this week.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (onAddWorker != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: onAddWorker,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Register worker'),
                    ),
                  ],
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TableHeader(workDays: workDays),
                  ...rows.map((row) => _TableWorkerRow(
                        row: row,
                        onCellTap: onCellTap,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mediumGray,
                ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(const Color(0xFF22C55E), 'Present'),
        item(const Color(0xFFF97316), 'Late'),
        item(const Color(0xFFEF4444), 'Absent'),
        item(const Color(0xFF94A3B8), 'Day Off'),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.workDays});
  final List<DateTime> workDays;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF475569),
          height: 1.2,
        );

    Widget cell(String text, double width, {TextAlign align = TextAlign.center}) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Text(text, textAlign: align, style: headerStyle),
        ),
      );
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          cell('Worker', WeeklyAttendanceChecklist._workerColWidth, align: TextAlign.left),
          ...workDays.map(
            (d) => cell(
              WeeklyAttendanceService.formatDayHeader(d),
              WeeklyAttendanceChecklist._dayColWidth,
            ),
          ),
          cell('Present\nDays', WeeklyAttendanceChecklist._summaryColWidth),
          cell('Rate', WeeklyAttendanceChecklist._summaryColWidth),
        ],
      ),
    );
  }
}

class _TableWorkerRow extends StatelessWidget {
  const _TableWorkerRow({
    required this.row,
    required this.onCellTap,
  });

  final WeeklyWorkerRow row;
  final WeeklyCellTap onCellTap;

  @override
  Widget build(BuildContext context) {
    final rateColor = _rateColor(row.ratePercent);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: WeeklyAttendanceChecklist._workerColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                    child: Text(
                      _initials(row.workerName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.workerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text(
                          row.position,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.mediumGray,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...row.days.map(
            (cell) => _DayStatusCell(
              cell: cell,
              width: WeeklyAttendanceChecklist._dayColWidth,
              onTap: () => onCellTap(row, cell),
            ),
          ),
          SizedBox(
            width: WeeklyAttendanceChecklist._summaryColWidth,
            child: Text(
              '${row.presentCount}/${row.workDays}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          SizedBox(
            width: WeeklyAttendanceChecklist._summaryColWidth,
            child: Text(
              '${row.ratePercent.toStringAsFixed(row.ratePercent == row.ratePercent.roundToDouble() ? 0 : 2)}%',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: rateColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _rateColor(double rate) {
    if (rate >= 80) return const Color(0xFF16A34A);
    if (rate >= 50) return const Color(0xFF2563EB);
    if (rate > 0) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _DayStatusCell extends StatelessWidget {
  const _DayStatusCell({
    required this.cell,
    required this.width,
    required this.onTap,
  });

  final WeeklyDayCell cell;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual(cell.status);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(visual.icon, size: 20, color: visual.color),
                const SizedBox(height: 4),
                Text(
                  cell.timeLabel ?? visual.placeholder,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.mediumGray,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static ({IconData icon, Color color, String placeholder}) _statusVisual(WeeklyDayStatus s) {
    switch (s) {
      case WeeklyDayStatus.present:
        return (icon: Icons.check_circle, color: const Color(0xFF22C55E), placeholder: '—');
      case WeeklyDayStatus.late:
        return (icon: Icons.schedule, color: const Color(0xFFF97316), placeholder: '—');
      case WeeklyDayStatus.absent:
        return (icon: Icons.cancel, color: const Color(0xFFEF4444), placeholder: '—');
      case WeeklyDayStatus.dayOff:
        return (icon: Icons.remove_circle_outline, color: const Color(0xFF94A3B8), placeholder: '—');
      case WeeklyDayStatus.pending:
        return (icon: Icons.radio_button_unchecked, color: const Color(0xFFCBD5E1), placeholder: '—');
    }
  }
}

/// Bottom sheet to update a single day status (writes via parent callback).
Future<WeeklyDayStatus?> showWeeklyStatusPickerSheet(
  BuildContext context, {
  required String workerName,
  required DateTime day,
  required WeeklyDayStatus current,
}) {
  return showModalBottomSheet<WeeklyDayStatus>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final dayLabel = WeeklyAttendanceService.formatDayHeader(day).replaceAll('\n', ' ');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                workerName,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                dayLabel,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
              ),
              const SizedBox(height: 14),
              _pickerTile(ctx, WeeklyDayStatus.present, 'Present', Icons.check_circle, const Color(0xFF22C55E), current),
              _pickerTile(ctx, WeeklyDayStatus.late, 'Late', Icons.schedule, const Color(0xFFF97316), current),
              _pickerTile(ctx, WeeklyDayStatus.absent, 'Absent', Icons.cancel, const Color(0xFFEF4444), current),
              _pickerTile(ctx, WeeklyDayStatus.dayOff, 'Day Off', Icons.event_busy, const Color(0xFF94A3B8), current),
            ],
          ),
        ),
      );
    },
  );
}

Widget _pickerTile(
  BuildContext ctx,
  WeeklyDayStatus status,
  String label,
  IconData icon,
  Color color,
  WeeklyDayStatus current,
) {
  final selected = status == current;
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    trailing: selected ? Icon(Icons.check, color: color) : null,
    onTap: () => Navigator.of(ctx).pop(status),
  );
}
