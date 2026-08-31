import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/weekly_attendance_service.dart';

typedef MonFriCellTap = void Function(WeeklyWorkerRow worker, WeeklyDayCell cell);

/// One worker card with Mon–Fri attendance checklist.
class WorkerMonFriScheduleCard extends StatelessWidget {
  const WorkerMonFriScheduleCard({
    super.key,
    required this.row,
    required this.onCellTap,
    this.canEdit = true,
  });

  final WeeklyWorkerRow row;
  final MonFriCellTap onCellTap;
  final bool canEdit;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  @override
  Widget build(BuildContext context) {
    final days = row.days.length >= 5 ? row.days.take(5).toList() : row.days;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.residentBlue.withValues(alpha: 0.12),
                  child: Text(
                    _initials(row.workerName),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.residentBlue,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.workerName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        row.position.isNotEmpty ? row.position : 'Worker',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${row.ratePercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                    Text(
                      '${row.presentCount}/${row.workDays} days',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.mediumGray),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(days.length, (i) {
                final cell = days[i];
                final label = i < _labels.length ? _labels[i] : WeeklyAttendanceService.formatDayHeader(cell.date).split('\n').first;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                    child: _DayChip(
                      label: label,
                      cell: cell,
                      onTap: canEdit ? () => onCellTap(row, cell) : null,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.cell, this.onTap});
  final String label;
  final WeeklyDayCell cell;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(cell.status);
    return Material(
      color: style.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Icon(style.icon, size: 16, color: style.fg),
              const SizedBox(height: 2),
              Text(
                style.short,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: style.fg),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _StatusStyle _statusStyle(WeeklyDayStatus s) {
    switch (s) {
      case WeeklyDayStatus.present:
        return const _StatusStyle(
          bg: Color(0xFFDCFCE7),
          fg: Color(0xFF166534),
          icon: Icons.check_circle,
          short: 'In',
        );
      case WeeklyDayStatus.late:
        return const _StatusStyle(
          bg: Color(0xFFFEF3C7),
          fg: Color(0xFFB45309),
          icon: Icons.schedule,
          short: 'Late',
        );
      case WeeklyDayStatus.absent:
        return const _StatusStyle(
          bg: Color(0xFFFEE2E2),
          fg: Color(0xFFB91C1C),
          icon: Icons.cancel_outlined,
          short: 'Out',
        );
      case WeeklyDayStatus.dayOff:
        return const _StatusStyle(
          bg: Color(0xFFF1F5F9),
          fg: Color(0xFF64748B),
          icon: Icons.remove_circle_outline,
          short: 'Off',
        );
      case WeeklyDayStatus.pending:
        return const _StatusStyle(
          bg: Color(0xFFF8FAFC),
          fg: Color(0xFF94A3B8),
          icon: Icons.radio_button_unchecked,
          short: '—',
        );
    }
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.short,
  });
  final Color bg;
  final Color fg;
  final IconData icon;
  final String short;
}
