import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';

class AdminGlassScaffold extends StatelessWidget {
  const AdminGlassScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.showSidebar = true,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showSidebar;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width >= 1400 ? 1200.0 : 1100.0;
    final isNarrow = MediaQuery.of(context).size.width < 980;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
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
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: child,
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
              children: [
                const SizedBox(width: 16),
                AdminGlassSidebar(
                  onDashboard: () => context.push(RouteNames.adminDashboard),
                  onProjects: () => context.push(RouteNames.adminProjects),
                  onAiReports: () => context.push(RouteNames.adminReports),
                  onPayroll: () => context.push(RouteNames.adminPayroll),
                  onBudget: () => context.push(RouteNames.adminFinancialMonitoring),
                  onMaterials: () => context.push(RouteNames.adminMaterialMonitoring),
                  onHistory: () => context.push(RouteNames.adminHistory),
                  onProfile: () => context.push(RouteNames.profile),
                ),
                const SizedBox(width: 16),
                Expanded(child: page),
                const SizedBox(width: 16),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: isNarrow ? bottomNavigationBar : null,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _AdminGlassHeader extends StatelessWidget {
  const _AdminGlassHeader({
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
    final baseColor = color ?? Colors.white;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AdminGlassSidebar extends StatelessWidget {
  const AdminGlassSidebar({
    super.key,
    required this.onDashboard,
    required this.onProjects,
    required this.onAiReports,
    required this.onPayroll,
    required this.onBudget,
    required this.onMaterials,
    required this.onHistory,
    required this.onProfile,
  });

  final VoidCallback onDashboard;
  final VoidCallback onProjects;
  final VoidCallback onAiReports;
  final VoidCallback onPayroll;
  final VoidCallback onBudget;
  final VoidCallback onMaterials;
  final VoidCallback onHistory;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.construction,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CEO Construction',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SidebarNavItem(
              icon: Icons.grid_view_rounded,
              label: 'Overview',
              onPressed: onDashboard,
            ),
            _SidebarNavItem(
              icon: Icons.folder_open,
              label: 'Projects',
              onPressed: onProjects,
            ),
            _SidebarNavItem(
              icon: Icons.photo_camera_outlined,
              label: 'GovTrack AI',
              onPressed: onAiReports,
            ),
            _SidebarNavItem(
              icon: Icons.payments_outlined,
              label: 'Payroll',
              onPressed: onPayroll,
            ),
            _SidebarNavItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Budget',
              onPressed: onBudget,
            ),
            _SidebarNavItem(
              icon: Icons.inventory_2_outlined,
              label: 'Materials',
              onPressed: onMaterials,
            ),
            _SidebarNavItem(
              icon: Icons.history,
              label: 'History',
              onPressed: onHistory,
            ),
            const Spacer(),
            _SidebarNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              onPressed: onProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black.withValues(alpha: 0.75)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.78),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.black.withValues(alpha: 0.75), size: 20),
      ),
    );
  }
}

class SmartInsightCard extends StatelessWidget {
  const SmartInsightCard({
    super.key,
    required this.title,
    required this.message,
    this.accentColor = const Color(0xFF2DD4BF),
  });

  final String title;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withValues(alpha: 0.70),
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
        ],
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
