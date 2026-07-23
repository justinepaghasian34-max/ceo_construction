import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/admin_glass_layout.dart';

/// Presenter guide for capstone / stakeholder demos (web admin + site manager flow).
class AdminDemoScriptScreen extends StatefulWidget {
  const AdminDemoScriptScreen({super.key});

  @override
  State<AdminDemoScriptScreen> createState() => _AdminDemoScriptScreenState();
}

class _AdminDemoScriptScreenState extends State<AdminDemoScriptScreen> {
  final Set<int> _done = {};
  final Set<int> _expanded = {0, 1, 8};
  String? _phaseFilter;

  static const _accent = Color(0xFF1E3A8A);
  static const _purple = Color(0xFF7C3AED);
  static const _teal = Color(0xFF0D9488);
  static const _green = Color(0xFF22C55E);
  static const _amber = Color(0xFFF59E0B);

  static const _steps = <_DemoStep>[
    _DemoStep(
      id: 0,
      phase: 'Setup',
      icon: Icons.checklist_rtl_outlined,
      title: 'Pre-demo checklist',
      minutes: 2,
      narration:
          'Before the audience arrives, confirm Firebase is live, Cloud Functions are deployed (especially govtrackChatGemini), and the demo project has a location set in Firestore for live weather.',
      bullets: [
        'Project: justine Building (or your assigned demo project)',
        'Firestore project.location → e.g. Manila,PH or Quezon City,PH',
        'Site manager account assigned to that project',
        'Admin web open on laptop; site manager on phone/emulator',
      ],
    ),
    _DemoStep(
      id: 1,
      phase: 'Admin Web',
      icon: Icons.dashboard_outlined,
      title: 'Executive dashboard',
      minutes: 3,
      narration:
          'This is the command center for LGU construction oversight. KPI cards show financial health, schedule performance, and live weather risk — all grounded in project data, not estimates.',
      bullets: [
        'Point out Net Margin, CPI, and SPI cards',
        'Tap Weather Risk → opens forecast module',
        'Mention Smart Insight as AI-assisted decision support',
      ],
      route: RouteNames.adminHome,
      routeLabel: 'Open Dashboard',
    ),
    _DemoStep(
      id: 2,
      phase: 'Admin Web',
      icon: Icons.folder_open_outlined,
      title: 'Projects & site assignment',
      minutes: 3,
      narration:
          'Every site manager sees only their assigned project. Admins create projects here and set the location field — that location powers Open-Meteo live weather for GovTrack AI.',
      bullets: [
        'Show project list and status',
        'Highlight location field on project record',
        'Explain role-based access: admin vs site_manager',
      ],
      route: RouteNames.adminProjects,
      routeLabel: 'Open Projects',
    ),
    _DemoStep(
      id: 3,
      phase: 'Admin Web',
      icon: Icons.inventory_2_outlined,
      title: 'Material monitoring',
      subtitle: 'Layer 2 — Inventory',
      minutes: 4,
      narration:
          'Layer 2 of GovTrack AI: live materials tracking. Admins and material monitors see stock levels, allocations, deliveries, and low-inventory signals — the same data GovTrack uses when answering stock questions.',
      bullets: [
        'Select demo project',
        'Show inventory quantities and allocations',
        'Explain: AI answers stock questions ONLY from this data',
      ],
      route: RouteNames.adminMaterialMonitoring,
      routeLabel: 'Open Materials',
    ),
    _DemoStep(
      id: 4,
      phase: 'Admin Web',
      icon: Icons.cloud_outlined,
      title: 'Weather & site conditions',
      minutes: 3,
      narration:
          'Weather is operational project data. Open-Meteo feeds current temperature, humidity, daylight/night visibility, and rain-in-next-3-hours alerts into GovTrack AI and the site manager dashboard.',
      bullets: [
        'Show 7-day forecast and hourly view',
        'Explain rain alert → cover cement, drywall, electrical',
        'Night visibility → Class 3 PPE reminder',
      ],
      route: RouteNames.adminWeatherForecast,
      routeLabel: 'Open Weather',
    ),
    _DemoStep(
      id: 5,
      phase: 'Admin Web',
      icon: Icons.query_stats_outlined,
      title: 'Progress reports & audit trail',
      subtitle: 'Layer 3 — Timeline',
      minutes: 4,
      narration:
          'Layer 3 — Timeline: daily logs, milestones, and AI progress analysis. The audit trail proves who changed what — critical for LGU accountability.',
      bullets: [
        'Open AI Progress Reports — photo-based milestone estimate',
        'Show audit trail entries for transparency',
        'Tie progress % back to daily reports in Firestore',
      ],
      route: RouteNames.adminProgressReports,
      routeLabel: 'Progress Reports',
      secondaryRoute: RouteNames.adminAuditTrail,
      secondaryRouteLabel: 'Audit Trail',
    ),
    _DemoStep(
      id: 6,
      phase: 'Site Manager',
      icon: Icons.phone_android_outlined,
      title: 'Mobile dashboard & attendance',
      minutes: 4,
      narration:
          'Switch to the site manager phone. The dashboard shows live weather, weekly attendance checklist, and quick actions. Attendance is logged per worker Mon–Fri.',
      bullets: [
        'Log in as site manager (OTP if enabled)',
        'Show Weather & Site Conditions card',
        'Open Attendance → Worker Schedules tab',
        'Mark present/absent for demo workers',
      ],
      isMobileOnly: true,
    ),
    _DemoStep(
      id: 7,
      phase: 'Site Manager',
      icon: Icons.local_shipping_outlined,
      title: 'Materials hub',
      minutes: 3,
      narration:
          'Site managers record material usage, confirm deliveries, and submit requests — data flows to admin Material Monitoring and into GovTrack AI Layer 2 answers.',
      bullets: [
        'Materials Hub → Usage log entry',
        'Show delivery confirmation flow',
        'Submit a sample material request',
      ],
      isMobileOnly: true,
    ),
    _DemoStep(
      id: 8,
      phase: 'GovTrack AI',
      icon: Icons.psychology_outlined,
      title: '3-layer AI live demo',
      minutes: 6,
      narration:
          'GovTrack AI has three scopes: Brain (construction/safety), Inventory (materials), Timeline (progress/logs). It refuses off-topic questions and never guesses missing metrics.',
      bullets: [
        'Open GovTrack AI tab on site manager app',
        'Live weather strip refreshes before each message',
        'Ask sample questions below (tap to copy)',
      ],
      sampleQuestions: [
        _SampleQuestion(
          layer: 'Layer 1 — Brain',
          layerColor: _accent,
          icon: Icons.engineering_outlined,
          question: 'What PPE is required when working at height on this site?',
          note: 'Uses SOP/safety docs + industry best practice',
        ),
        _SampleQuestion(
          layer: 'Layer 2 — Inventory',
          layerColor: _teal,
          icon: Icons.inventory_outlined,
          question: 'How many bags of cement do we have in stock right now?',
          note: 'Answers from Firestore inventory only',
        ),
        _SampleQuestion(
          layer: 'Layer 3 — Timeline',
          layerColor: _purple,
          icon: Icons.timeline_outlined,
          question: 'What was recorded in the latest daily work log?',
          note: 'Uses dailyReports + milestones',
        ),
        _SampleQuestion(
          layer: 'Weather',
          layerColor: Color(0xFF0284C7),
          icon: Icons.wb_sunny_outlined,
          question: 'What is the weather right now? Should we cover materials?',
          note: 'Open-Meteo live data — rain alert if probability > 40%',
        ),
        _SampleQuestion(
          layer: 'Guardrail',
          layerColor: _amber,
          icon: Icons.block_outlined,
          question: 'Who won the basketball game last night?',
          note: 'Must reply: off-topic refusal message',
        ),
      ],
      isMobileOnly: true,
    ),
    _DemoStep(
      id: 9,
      phase: 'Close',
      icon: Icons.flag_outlined,
      title: 'Wrap-up talking points',
      minutes: 2,
      narration:
          'Summarize: one platform for admin oversight, mobile site operations, and grounded AI — weather from Open-Meteo, materials and progress from Firestore, construction guidance from uploaded SOPs. No hallucinated inventory or weather.',
      bullets: [
        'Data-grounded AI with 3-layer scope',
        'Role-based access across admin, site manager, payroll, materials',
        'Audit trail + offline sync for field reliability',
        'Q&A — invite questions',
      ],
    ),
  ];

  int get _totalMinutes => _steps.fold(0, (sum, s) => sum + s.minutes);

  List<_DemoStep> get _visibleSteps {
    if (_phaseFilter == null) return _steps;
    return _steps.where((s) => s.phase == _phaseFilter).toList();
  }

  Color _phaseColor(String phase) => switch (phase) {
        'Admin Web' => _accent,
        'Site Manager' => _teal,
        'GovTrack AI' => _purple,
        'Setup' => AppTheme.mediumGray,
        'Close' => _green,
        _ => AppTheme.deepBlue,
      };

  void _toggleDone(int id) {
    setState(() {
      if (_done.contains(id)) {
        _done.remove(id);
      } else {
        _done.add(id);
      }
    });
  }

  void _toggleExpanded(int id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  void _resetProgress() {
    setState(() {
      _done.clear();
      _expanded.addAll([0, 1, 8]);
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Question copied — paste in GovTrack AI'),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _steps.isEmpty ? 0.0 : _done.length / _steps.length;
    final phases = _steps.map((s) => s.phase).toSet().toList();

    return AdminGlassScaffold(
      title: 'Demo Script',
      showSidebar: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroSection(
            totalMinutes: _totalMinutes,
            progress: progress,
            completed: _done.length,
            total: _steps.length,
            onReset: _done.isEmpty ? null : _resetProgress,
          ),
          const SizedBox(height: 20),
          _AiScopeRow(),
          const SizedBox(height: 20),
          _PhaseFilterBar(
            phases: phases,
            selected: _phaseFilter,
            phaseColor: _phaseColor,
            onSelect: (p) => setState(() => _phaseFilter = p),
          ),
          const SizedBox(height: 16),
          ..._buildTimeline(_visibleSteps),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline(List<_DemoStep> steps) {
    if (steps.isEmpty) {
      return [
        GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No steps in this phase.',
              style: TextStyle(color: AppTheme.mediumGray),
            ),
          ),
        ),
      ];
    }

    return List.generate(steps.length, (i) {
      final step = steps[i];
      final isLast = i == steps.length - 1;
      return _TimelineStepCard(
        step: step,
        stepIndex: step.id + 1,
        isLast: isLast,
        done: _done.contains(step.id),
        expanded: _expanded.contains(step.id),
        phaseColor: _phaseColor(step.phase),
        onToggleDone: () => _toggleDone(step.id),
        onToggleExpanded: () => _toggleExpanded(step.id),
        onCopy: _copy,
        onNavigate: (route) => context.push(route),
      );
    });
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.totalMinutes,
    required this.progress,
    required this.completed,
    required this.total,
    this.onReset,
  });

  final int totalMinutes;
  final double progress;
  final int completed;
  final int total;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 640;
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PRESENTER GUIDE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'CEO Construction Demo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Step-by-step script for admin web + site manager mobile',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _StatPill(icon: Icons.schedule, label: '~$totalMinutes min'),
                    _StatPill(icon: Icons.format_list_numbered, label: '$total steps'),
                    _StatPill(icon: Icons.devices, label: 'Web + Mobile'),
                  ],
                ),
              ],
            );

            final ring = SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      color: const Color(0xFF86EFAC),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$completed/$total',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: left),
                  ring,
                  if (onReset != null) ...[
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: onReset,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                      ),
                      tooltip: 'Reset progress',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 20),
                Row(
                  children: [
                    ring,
                    if (onReset != null) ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: onReset,
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reset'),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI scope cards ──────────────────────────────────────────────────────────

class _AiScopeRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const layers = [
      (
        icon: Icons.psychology_outlined,
        color: Color(0xFF1E3A8A),
        title: 'Layer 1 · Brain',
        desc: 'Safety, SOPs, equipment, building codes',
      ),
      (
        icon: Icons.inventory_2_outlined,
        color: Color(0xFF0D9488),
        title: 'Layer 2 · Inventory',
        desc: 'Stock levels, deliveries, low-stock alerts',
      ),
      (
        icon: Icons.timeline_outlined,
        color: Color(0xFF7C3AED),
        title: 'Layer 3 · Timeline',
        desc: 'Daily logs, milestones, weather delays',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        final cards = layers.map((l) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: l.color.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: l.color.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: l.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(l.icon, color: l.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: l.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.desc,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.mediumGray,
                                height: 1.3,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();

        if (narrow) {
          return Column(
            children: cards
                .map((w) => Padding(padding: const EdgeInsets.only(bottom: 10), child: w))
                .toList(),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cards[0],
            const SizedBox(width: 12),
            cards[1],
            const SizedBox(width: 12),
            cards[2],
          ],
        );
      },
    );
  }
}

// ─── Phase filter ────────────────────────────────────────────────────────────

class _PhaseFilterBar extends StatelessWidget {
  const _PhaseFilterBar({
    required this.phases,
    required this.selected,
    required this.phaseColor,
    required this.onSelect,
  });

  final List<String> phases;
  final String? selected;
  final Color Function(String) phaseColor;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter by phase',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.deepBlue,
              ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All steps',
                selected: selected == null,
                color: AppTheme.deepBlue,
                onTap: () => onSelect(null),
              ),
              const SizedBox(width: 8),
              ...phases.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: p,
                    selected: selected == p,
                    color: phaseColor(p),
                    onTap: () => onSelect(p),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: selected ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? Colors.white : AppTheme.darkGray,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Timeline step ───────────────────────────────────────────────────────────

class _TimelineStepCard extends StatelessWidget {
  const _TimelineStepCard({
    required this.step,
    required this.stepIndex,
    required this.isLast,
    required this.done,
    required this.expanded,
    required this.phaseColor,
    required this.onToggleDone,
    required this.onToggleExpanded,
    required this.onCopy,
    required this.onNavigate,
  });

  final _DemoStep step;
  final int stepIndex;
  final bool isLast;
  final bool done;
  final bool expanded;
  final Color phaseColor;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(String) onCopy;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                GestureDetector(
                  onTap: onToggleDone,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: done ? const Color(0xFF22C55E) : phaseColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (done ? const Color(0xFF22C55E) : phaseColor)
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : Text(
                              '$stepIndex',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: done
                          ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: done ? 0.72 : 1,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  shadowColor: Colors.black.withValues(alpha: 0.06),
                  child: InkWell(
                    onTap: onToggleExpanded,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: done
                              ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: phaseColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(step.icon, size: 20, color: phaseColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _Badge(text: step.phase, color: phaseColor),
                                          const SizedBox(width: 6),
                                          _Badge(
                                            text: '${step.minutes} min',
                                            color: AppTheme.mediumGray,
                                            filled: false,
                                          ),
                                          if (step.isMobileOnly) ...[
                                            const SizedBox(width: 6),
                                            _Badge(
                                              text: 'Mobile',
                                              color: const Color(0xFF0D9488),
                                              filled: false,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        step.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: AppTheme.deepBlue,
                                        ),
                                      ),
                                      if (step.subtitle != null)
                                        Text(
                                          step.subtitle!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: phaseColor.withValues(alpha: 0.85),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: AppTheme.mediumGray,
                                ),
                              ],
                            ),
                          ),
                          if (expanded) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SayThisBox(text: step.narration),
                                  if (step.bullets.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      'KEY ACTIONS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                        color: AppTheme.mediumGray,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...step.bullets.map(
                                      (b) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.arrow_right_alt,
                                              size: 20,
                                              color: phaseColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                b,
                                                style: const TextStyle(
                                                  height: 1.4,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (step.route != null ||
                                      step.secondaryRoute != null) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (step.route != null)
                                          FilledButton.icon(
                                            onPressed: () => onNavigate(step.route!),
                                            icon: const Icon(Icons.launch, size: 16),
                                            label: Text(step.routeLabel ?? 'Open'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: phaseColor,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 10,
                                              ),
                                            ),
                                          ),
                                        if (step.secondaryRoute != null)
                                          OutlinedButton.icon(
                                            onPressed: () =>
                                                onNavigate(step.secondaryRoute!),
                                            icon: const Icon(Icons.launch, size: 16),
                                            label: Text(
                                              step.secondaryRouteLabel ?? 'Open',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: phaseColor,
                                              side: BorderSide(color: phaseColor),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (step.sampleQuestions != null) ...[
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline,
                                            size: 18, color: phaseColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Sample GovTrack questions',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: phaseColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'tap to copy',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.mediumGray,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ...step.sampleQuestions!.map(
                                      (q) => _QuestionCard(
                                        sample: q,
                                        onCopy: () => onCopy(q.question),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    this.filled = true,
  });

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SayThisBox extends StatelessWidget {
  const _SayThisBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_outlined, size: 16, color: Color(0xFF0284C7)),
              SizedBox(width: 6),
              Text(
                'WHAT TO SAY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF0284C7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF0C4A6E),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.sample, required this.onCopy});

  final _SampleQuestion sample;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: sample.layerColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: sample.layerColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(sample.icon, size: 16, color: sample.layerColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sample.layer,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: sample.layerColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '"${sample.question}"',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                              if (sample.note.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  sample.note,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.content_copy_outlined,
                          size: 18,
                          color: sample.layerColor.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
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

// ─── Data models ─────────────────────────────────────────────────────────────

class _DemoStep {
  const _DemoStep({
    required this.id,
    required this.phase,
    required this.icon,
    required this.title,
    required this.minutes,
    required this.narration,
    this.subtitle,
    this.bullets = const [],
    this.route,
    this.routeLabel,
    this.secondaryRoute,
    this.secondaryRouteLabel,
    this.sampleQuestions,
    this.isMobileOnly = false,
  });

  final int id;
  final String phase;
  final IconData icon;
  final String title;
  final String? subtitle;
  final int minutes;
  final String narration;
  final List<String> bullets;
  final String? route;
  final String? routeLabel;
  final String? secondaryRoute;
  final String? secondaryRouteLabel;
  final List<_SampleQuestion>? sampleQuestions;
  final bool isMobileOnly;
}

class _SampleQuestion {
  const _SampleQuestion({
    required this.layer,
    required this.layerColor,
    required this.icon,
    required this.question,
    this.note = '',
  });

  final String layer;
  final Color layerColor;
  final IconData icon;
  final String question;
  final String note;
}
