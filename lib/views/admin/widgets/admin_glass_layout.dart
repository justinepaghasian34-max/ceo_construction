import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_constants.dart';

/// Shared timing for admin hover, parallax, and page motion.
/// [intensity] 0–1 scale; user preference ≈ 0.7 (7/10 — smooth, not snappy).
abstract final class _AdminMotion {
  static const double intensity = 0.7;

  static Duration get hover =>
      Duration(milliseconds: (220 + intensity * 680).round());
  static Duration get shine =>
      Duration(milliseconds: (1400 + intensity * 1800).round());
  static Duration get entry =>
      Duration(milliseconds: (520 + intensity * 480).round());
  static const Curve hoverCurve = Curves.easeInOutCubic;
  static double get parallaxLerp => 0.12 - (intensity * 0.075);
  static double get tiltLerp => 0.18 - (intensity * 0.11);
  static double get hoverScale => 1.0 + (0.018 * (1 - intensity));
}

/// Soft elevation tokens — keep UI lifted without heavy client-facing shadows.
abstract final class _AdminElevation {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: const Color(0xFF64748B).withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> hoverLift({required bool hovered}) {
    if (!hovered) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> get navHover => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
}

/// Sidebar contents vary by signed-in role.
enum AdminSidebarMode {
  /// Full admin navigation.
  full,

  /// Material Monitoring user — materials tools only.
  materials,

  /// Payroll Monitoring user — payroll tools only.
  payroll,
}

/// Centered floating dialog used across admin monitoring screens.
Future<T?> showCenteredAdminDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
  double maxWidth = 820,
  double maxHeightFactor = 0.78,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final size = MediaQuery.of(dialogContext).size;
      final width =
          size.width < maxWidth + 48 ? size.width * 0.94 : maxWidth;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height * maxHeightFactor,
          ),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

/// Standard title row for [showCenteredAdminDialog] content.
Widget adminDialogTitleRow({
  required BuildContext context,
  required String title,
}) {
  return Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

class AdminGlassScaffold extends StatelessWidget {
  const AdminGlassScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.showSidebar = true,
    this.sidebarMode = AdminSidebarMode.full,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showSidebar;
  final AdminSidebarMode sidebarMode;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width >= 1400 ? 1200.0 : 1100.0;
    final isNarrow = MediaQuery.of(context).size.width < 980;

    final hasDrawer = showSidebar && isNarrow;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: hasDrawer ? _AdminDrawer(mode: sidebarMode) : null,
      body: _AdminParallaxShell(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 980;

            final page = Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 12 : 20,
                    vertical: isNarrow ? 12 : 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AdminGlassHeader(
                        title: title,
                        actions: actions,
                        showMenu: showSidebar && isNarrow,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _AdminEntryTransition(
                            key: ValueKey<String>(title),
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

              if (!showSidebar || isNarrow) {
                return page;
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                    child: AdminGlassSidebar(
                    mode: sidebarMode,
                    onDashboard: () => context.push(RouteNames.adminHome),
                    onProjects: () => context.push(RouteNames.adminProjects),
                    onAiProgressReports: () =>
                        context.push(RouteNames.adminProgressReports),
                    onPayroll: () => context.push(
                      sidebarMode == AdminSidebarMode.payroll
                          ? RouteNames.payrollHome
                          : RouteNames.adminPayroll,
                    ),
                    onBudget: () =>
                        context.push(RouteNames.adminFinancialMonitoring),
                    onMaterials: () => context.push(
                      sidebarMode == AdminSidebarMode.materials
                          ? RouteNames.materialsHome
                          : RouteNames.adminMaterialMonitoring,
                    ),
                    onHistory: () => context.push(RouteNames.adminHistory),
                    onProfile: () => context.push(RouteNames.profile),
                  ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: page),
                  const SizedBox(width: 12),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: isNarrow ? bottomNavigationBar : null,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _AdminParallaxShell extends StatefulWidget {
  const _AdminParallaxShell({
    required this.child,
  });

  final Widget child;

  @override
  State<_AdminParallaxShell> createState() => _AdminParallaxShellState();
}

class _AdminParallaxShellState extends State<_AdminParallaxShell>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<Offset> _parallax = ValueNotifier<Offset>(Offset.zero);
  Offset _current = Offset.zero;
  Offset _target = Offset.zero;

  bool get _enableParallax {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_enableParallax) return;
      final next = Offset.lerp(_current, _target, _AdminMotion.parallaxLerp) ?? _target;
      _current = next;
      _parallax.value = next;
    });
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enableParallax) return widget.child;

    return LayoutBuilder(
      builder: (context, c) {
        return MouseRegion(
          onHover: (e) {
            final size = Size(c.maxWidth, c.maxHeight);
            if (size.width <= 0 || size.height <= 0) return;
            final dx = (e.localPosition.dx / size.width) - 0.5;
            final dy = (e.localPosition.dy / size.height) - 0.5;
            _target = Offset(dx.clamp(-0.5, 0.5), dy.clamp(-0.5, 0.5));
          },
          child: ValueListenableBuilder<Offset>(
            valueListenable: _parallax,
            builder: (context, v, child) {
              final bg1 = Offset(v.dx * 44, v.dy * 44);
              final bg2 = Offset(v.dx * -72, v.dy * -72);
              return Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        children: [
                          Transform.translate(
                            offset: bg1,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment(-0.7, -0.8),
                                  radius: 1.15,
                                  colors: [
                                    Color(0x66A5B4FC),
                                    Color(0x00F3F4F6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: bg2,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment(0.9, 0.8),
                                  radius: 1.25,
                                  colors: [
                                    Color(0x66BFF7E8),
                                    Color(0x00F3F4F6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(child: child!),
                ],
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _parallax.dispose();
    super.dispose();
  }
}

class _AdminEntryTransition extends StatefulWidget {
  const _AdminEntryTransition({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<_AdminEntryTransition> createState() => _AdminEntryTransitionState();
}

class _AdminEntryTransitionState extends State<_AdminEntryTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _AdminMotion.entry,
    );
    _fade = CurvedAnimation(parent: _controller, curve: _AdminMotion.hoverCurve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.028),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: _AdminMotion.hoverCurve),
    );
    _scale = Tween<double>(begin: 0.985, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: _AdminMotion.hoverCurve),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

class _AdminGlassHeader extends StatelessWidget {
  const _AdminGlassHeader({
    required this.title,
    this.actions,
    required this.showMenu,
  });

  final String title;
  final List<Widget>? actions;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 720;

    return GlassCard(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 10 : 18,
        vertical: isNarrow ? 10 : 14,
      ),
      borderRadius: 18,
      child: Row(
        children: [
          if (showMenu) ...[
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: 'Menu',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (isNarrow)
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                      fontSize: 16,
                    ),
              ),
            )
          else
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
            ),
          if (!isNarrow) ...[
            const SizedBox(width: 20),
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search projects, reports…',
                    hintStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.38),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          ...(actions ?? const <Widget>[]),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      borderRadius: borderRadius,
      child: Builder(
        builder: (context) {
          final baseColor = color ?? Colors.white;
          return Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: _AdminElevation.card,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final double borderRadius;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift>
    with TickerProviderStateMixin {
  bool _hovered = false;
  late final Ticker _ticker;
  final ValueNotifier<Offset> _tilt = ValueNotifier<Offset>(Offset.zero);
  Offset _tiltCurrent = Offset.zero;
  Offset _tiltTarget = Offset.zero;

  late final AnimationController _shineController;

  bool get _enableHoverMotion {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_enableHoverMotion) return;
      final next = Offset.lerp(_tiltCurrent, _tiltTarget, _AdminMotion.tiltLerp) ?? _tiltTarget;
      _tiltCurrent = next;
      _tilt.value = next;
    });
    _ticker.start();

    _shineController = AnimationController(
      vsync: this,
      duration: _AdminMotion.shine,
    );
  }

  @override
  Widget build(BuildContext context) {

    final scale = _hovered ? _AdminMotion.hoverScale : 1.0;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        if (_enableHoverMotion && !_shineController.isAnimating) {
          _shineController.repeat();
        }
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _tiltTarget = Offset.zero;
        _shineController.stop();
        _shineController.value = 0;
      }),
      onHover: null,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _tilt,
        builder: (context, v, child) {
          final maxTilt = 0.0;
          final tiltX = (-v.dy) * maxTilt;
          final tiltY = (v.dx) * maxTilt;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(tiltX)
            ..rotateY(tiltY);

          return AnimatedContainer(
            duration: _AdminMotion.hover,
            curve: _AdminMotion.hoverCurve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: _AdminElevation.hoverLift(hovered: _hovered),
            ),
            child: AnimatedScale(
              duration: _AdminMotion.hover,
              curve: _AdminMotion.hoverCurve,
              scale: scale,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: Stack(
                  children: [
                    Transform(
                      alignment: Alignment.center,
                      transform: _hovered ? m : Matrix4.identity(),
                      child: child,
                    ),
                    IgnorePointer(
                      child: AnimatedOpacity(
                        duration: _AdminMotion.hover,
                        curve: _AdminMotion.hoverCurve,
                        opacity: _hovered ? 1 : 0,
                        child: AnimatedBuilder(
                          animation: _shineController,
                          builder: (context, _) {
                            final t = _shineController.value;
                            final x = (-1.0 + 2.0 * t);
                            return Transform.translate(
                              offset: Offset(x * 180, 0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.00),
                                      Colors.white.withValues(alpha: 0.14),
                                      Colors.white.withValues(alpha: 0.00),
                                    ],
                                    stops: const [0.35, 0.5, 0.65],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tilt.dispose();
    _shineController.dispose();
    super.dispose();
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({this.mode = AdminSidebarMode.full});

  final AdminSidebarMode mode;

  @override
  Widget build(BuildContext context) {
    final payrollRoute = mode == AdminSidebarMode.payroll
        ? RouteNames.payrollHome
        : RouteNames.adminPayroll;
    final materialsRoute = mode == AdminSidebarMode.materials
        ? RouteNames.materialsHome
        : RouteNames.adminMaterialMonitoring;

    return Drawer(
      backgroundColor: const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AdminGlassSidebar(
            mode: mode,
            onDashboard: () {
              Navigator.of(context).pop();
              context.push(RouteNames.adminHome);
            },
            onProjects: () {
              Navigator.of(context).pop();
              context.push(RouteNames.adminProjects);
            },
            onAiProgressReports: () {
              Navigator.of(context).pop();
              context.push(RouteNames.adminProgressReports);
            },
            onPayroll: () {
              Navigator.of(context).pop();
              context.push(payrollRoute);
            },
            onBudget: () {
              Navigator.of(context).pop();
              context.push(RouteNames.adminFinancialMonitoring);
            },
            onMaterials: () {
              Navigator.of(context).pop();
              context.push(materialsRoute);
            },
            onHistory: () {
              Navigator.of(context).pop();
              context.push(RouteNames.adminHistory);
            },
            onProfile: () {
              Navigator.of(context).pop();
              context.push(RouteNames.profile);
            },
          ),
        ),
      ),
    );
  }
}

class AdminGlassSidebar extends StatelessWidget {
  const AdminGlassSidebar({
    super.key,
    required this.onDashboard,
    required this.onProjects,
    required this.onAiProgressReports,
    required this.onPayroll,
    required this.onBudget,
    required this.onMaterials,
    required this.onHistory,
    required this.onProfile,
    this.mode = AdminSidebarMode.full,
  });

  final AdminSidebarMode mode;
  final VoidCallback onDashboard;
  final VoidCallback onProjects;
  final VoidCallback onAiProgressReports;
  final VoidCallback onPayroll;
  final VoidCallback onBudget;
  final VoidCallback onMaterials;
  final VoidCallback onHistory;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 228,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: _AdminElevation.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: _AdminSidebarBody(
            mode: mode,
            onDashboard: onDashboard,
            onProjects: onProjects,
            onAiProgressReports: onAiProgressReports,
            onPayroll: onPayroll,
            onBudget: onBudget,
            onMaterials: onMaterials,
            onHistory: onHistory,
            onProfile: onProfile,
          ),
        ),
      ),
    );
  }
}

class _AdminSidebarBody extends StatefulWidget {
  const _AdminSidebarBody({
    required this.onDashboard,
    required this.onProjects,
    required this.onAiProgressReports,
    required this.onPayroll,
    required this.onBudget,
    required this.onMaterials,
    required this.onHistory,
    required this.onProfile,
    this.mode = AdminSidebarMode.full,
  });

  final AdminSidebarMode mode;
  final VoidCallback onDashboard;
  final VoidCallback onProjects;
  final VoidCallback onAiProgressReports;
  final VoidCallback onPayroll;
  final VoidCallback onBudget;
  final VoidCallback onMaterials;
  final VoidCallback onHistory;
  final VoidCallback onProfile;

  @override
  State<_AdminSidebarBody> createState() => _AdminSidebarBodyState();
}

class _AdminSidebarBodyState extends State<_AdminSidebarBody> {
  String get _path {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return '';
    }
  }

  bool _isActive(String route, {List<String> aliases = const []}) {
    final path = _path;
    bool matches(String r) => path == r || path.startsWith('$r/');
    if (route == RouteNames.adminHome) {
      return path == RouteNames.adminHome ||
          path == RouteNames.adminDashboard ||
          path == '${RouteNames.adminHome}/';
    }
    return matches(route) || aliases.any(matches);
  }

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Color(0xFF94A3B8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final showFull = mode == AdminSidebarMode.full;
    final showMaterials = showFull || mode == AdminSidebarMode.materials;
    final showPayroll = showFull || mode == AdminSidebarMode.payroll;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.construction,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CEO Construction',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
        _groupLabel('MENU'),
        if (showFull) ...[
          _SidebarNavItem(
            icon: Icons.grid_view_rounded,
            label: 'Overview',
            selected: _isActive(RouteNames.adminHome),
            onPressed: widget.onDashboard,
          ),
          _SidebarNavItem(
            icon: Icons.folder_open,
            label: 'Projects',
            selected: _isActive(RouteNames.adminProjects),
            onPressed: widget.onProjects,
          ),
          _SidebarNavItem(
            icon: Icons.query_stats_outlined,
            label: 'AI Progress',
            selected: _isActive(RouteNames.adminProgressReports),
            onPressed: widget.onAiProgressReports,
          ),
        ],
        if (showPayroll)
          _SidebarNavItem(
            icon: Icons.payments_outlined,
            label: 'Payroll',
            selected: _isActive(
              RouteNames.adminPayroll,
              aliases: [RouteNames.payrollHome],
            ),
            onPressed: widget.onPayroll,
          ),
        if (showFull)
          _SidebarNavItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Budget',
            selected: _isActive(RouteNames.adminFinancialMonitoring),
            onPressed: widget.onBudget,
          ),
        if (showMaterials)
          _SidebarNavItem(
            icon: Icons.inventory_2_outlined,
            label: 'Materials',
            selected: _isActive(
              RouteNames.adminMaterialMonitoring,
              aliases: [RouteNames.materialsHome],
            ),
            onPressed: widget.onMaterials,
          ),
        if (showFull)
          _SidebarNavItem(
            icon: Icons.history,
            label: 'History',
            selected: _isActive(RouteNames.adminHistory),
            onPressed: widget.onHistory,
          ),
        const Spacer(),
        const Divider(height: 16, color: Color(0xFFE2E8F0)),
        _groupLabel('ACCOUNT'),
        _SidebarNavItem(
          icon: Icons.person_outline,
          label: 'Profile',
          selected: _isActive(RouteNames.profile),
          onPressed: widget.onProfile,
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected
        ? const Color(0xFF1E3A8A)
        : const Color(0xFF334155);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEEF2FF)
                  : _hovered
                      ? const Color(0xFFF1F5F9)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF1E3A8A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(widget.icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: color,
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

class SmartInsightCard extends StatelessWidget {
  const SmartInsightCard({
    super.key,
    required this.title,
    required this.message,
    this.accentColor = const Color(0xFF2563EB),
  });

  final String title;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              accentColor.withValues(alpha: 0.06),
              Colors.white,
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome_rounded, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlassDataTableTheme extends StatelessWidget {
  const GlassDataTableTheme({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.black.withValues(alpha: 0.06),
        dataTableTheme: DataTableThemeData(
          headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.70),
              ),
          dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.78),
              ),
          headingRowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.03),
          ),
          dataRowColor: WidgetStateProperty.resolveWith(
            (states) => Colors.transparent,
          ),
          dividerThickness: 0,
        ),
      ),
      child: child,
    );
  }
}
