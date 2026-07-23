import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Stage row for construction progress breakdown (GovTrack ML + dashboard).
class ProgressStageItem {
  const ProgressStageItem({
    required this.title,
    required this.subtitle,
    required this.percent,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final double percent;
  final IconData icon;
  final Color color;
}

/// Two-column progress panel: donut overall % + per-stage bars (mockup-aligned).
class ConstructionProgressPanel extends StatelessWidget {
  const ConstructionProgressPanel({
    super.key,
    required this.title,
    required this.overallPercent,
    required this.stages,
    this.statusLabel,
    this.statusColor,
  });

  final String title;
  final double overallPercent;
  final List<ProgressStageItem> stages;
  final String? statusLabel;
  final Color? statusColor;

  static List<ProgressStageItem> mlStagesFromMap(Map<String, double>? stageProgress) {
    const defaults = <String, ({String title, String subtitle, IconData icon, Color color})>{
      'foundation': (
        title: 'Foundation',
        subtitle: 'Footings, columns, and base structures',
        icon: Icons.foundation,
        color: Color(0xFF7C3AED),
      ),
      'structural': (
        title: 'Structural',
        subtitle: 'Beams, columns, slabs, and framework',
        icon: Icons.account_tree_outlined,
        color: Color(0xFF2563EB),
      ),
      'roofing': (
        title: 'Roofing',
        subtitle: 'Roof structure and covering',
        icon: Icons.roofing_outlined,
        color: Color(0xFFF97316),
      ),
      'walls': (
        title: 'Walls',
        subtitle: 'Wall construction and partitions',
        icon: Icons.grid_view_rounded,
        color: Color(0xFF22C55E),
      ),
    };

    if (stageProgress == null || stageProgress.isEmpty) {
      return defaults.entries
          .map(
            (e) => ProgressStageItem(
              title: e.value.title,
              subtitle: e.value.subtitle,
              percent: 0,
              icon: e.value.icon,
              color: e.value.color,
            ),
          )
          .toList();
    }

    return stageProgress.entries.map((e) {
      final key = e.key.toLowerCase();
      final meta = defaults[key];
      final pct = e.value.toDouble().clamp(0.0, 100.0);
      if (meta != null) {
        return ProgressStageItem(
          title: meta.title,
          subtitle: meta.subtitle,
          percent: pct,
          icon: meta.icon,
          color: meta.color,
        );
      }
      final label = key.isEmpty ? 'Stage' : '${key[0].toUpperCase()}${key.substring(1)}';
      return ProgressStageItem(
        title: label,
        subtitle: 'Construction phase progress',
        percent: pct,
        icon: Icons.construction_outlined,
        color: const Color(0xFF64748B),
      );
    }).toList();
  }

  static List<ProgressStageItem> dashboardStages({
    required double foundation,
    required double structural,
    required double electrical,
    required double finishing,
  }) {
    return [
      ProgressStageItem(
        title: 'Foundation',
        subtitle: 'Footings, columns, and base structures',
        percent: foundation,
        icon: Icons.foundation,
        color: const Color(0xFF7C3AED),
      ),
      ProgressStageItem(
        title: 'Structure',
        subtitle: 'Beams, columns, slabs, and framework',
        percent: structural,
        icon: Icons.account_tree_outlined,
        color: const Color(0xFF2563EB),
      ),
      ProgressStageItem(
        title: 'Electrical',
        subtitle: 'Wiring, panels, and site power',
        percent: electrical,
        icon: Icons.electrical_services_outlined,
        color: const Color(0xFFF59E0B),
      ),
      ProgressStageItem(
        title: 'Finishing',
        subtitle: 'Paint, fixtures, and final touches',
        percent: finishing,
        icon: Icons.home_work_outlined,
        color: const Color(0xFF22C55E),
      ),
    ];
  }

  static ({String label, Color color}) defaultStatus(double overall) {
    if (overall >= 60) {
      return (label: 'On Track', color: const Color(0xFF16A34A));
    }
    if (overall >= 25) {
      return (label: 'In Progress', color: const Color(0xFF2563EB));
    }
    if (overall > 0) {
      return (label: 'Getting Started', color: const Color(0xFFF59E0B));
    }
    return (label: 'Not Started', color: const Color(0xFF94A3B8));
  }

  @override
  Widget build(BuildContext context) {
    final overall = overallPercent.clamp(0.0, 100.0);
    final status = statusLabel ?? defaultStatus(overall).label;
    final statusClr = statusColor ?? defaultStatus(overall).color;
    const accent = Color(0xFF7C3AED);

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
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkGray,
                ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < 560;
              final donut = _OverallDonut(
                percent: overall,
                accent: accent,
                statusLabel: status,
                statusColor: statusClr,
              );
              final breakdown = Column(
                children: [
                  for (var i = 0; i < stages.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _StageRow(stage: stages[i]),
                  ],
                ],
              );

              if (stacked) {
                return Column(
                  children: [
                    donut,
                    const SizedBox(height: 20),
                    breakdown,
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 168, child: donut),
                    const SizedBox(width: 16),
                    Container(width: 1, color: const Color(0xFFE5E7EB)),
                    const SizedBox(width: 16),
                    Expanded(child: breakdown),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverallDonut extends StatelessWidget {
  const _OverallDonut({
    required this.percent,
    required this.accent,
    required this.statusLabel,
    required this.statusColor,
  });

  final double percent;
  final Color accent;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  strokeWidth: 9,
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: accent,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Overall Progress',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                percent >= 25 ? Icons.trending_up_rounded : Icons.schedule,
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage});
  final ProgressStageItem stage;

  @override
  Widget build(BuildContext context) {
    final pct = stage.percent.clamp(0.0, 100.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: stage.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(stage.icon, color: stage.color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stage.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: stage.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                stage.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: stage.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
