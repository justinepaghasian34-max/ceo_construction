import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';

enum AdminNavItem {
  dashboard,
  constructionProjects,
  budgetFinancial,
  payroll,
  materialInventory,
  aiReports,
}

class AdminBottomNavBar extends StatelessWidget {
  final AdminNavItem current;

  const AdminBottomNavBar({
    super.key,
    required this.current,
  });

  void _onTap(BuildContext context, AdminNavItem target) {
    if (target == current) return;

    switch (target) {
      case AdminNavItem.dashboard:
        context.push(RouteNames.adminHome);
        break;
      case AdminNavItem.constructionProjects:
        context.push(RouteNames.adminProjects);
        break;
      case AdminNavItem.budgetFinancial:
        context.push(RouteNames.adminFinancialMonitoring);
        break;
      case AdminNavItem.payroll:
        context.push(RouteNames.adminPayroll);
        break;
      case AdminNavItem.materialInventory:
        context.push(RouteNames.adminMaterialMonitoring);
        break;
      case AdminNavItem.aiReports:
        context.push(RouteNames.adminReports);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.white,
          border: Border(
            top: BorderSide(
              color: AppTheme.deepBlue.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.mediumGray.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildItem(
              context,
              item: AdminNavItem.dashboard,
              icon: Icons.bar_chart,
            ),
            _buildItem(
              context,
              item: AdminNavItem.constructionProjects,
              icon: Icons.dataset,
            ),
            _buildItem(
              context,
              item: AdminNavItem.budgetFinancial,
              icon: Icons.account_balance_wallet,
            ),
            _buildItem(
              context,
              item: AdminNavItem.payroll,
              icon: Icons.payments,
            ),
            _buildItem(
              context,
              item: AdminNavItem.materialInventory,
              icon: Icons.inventory_2,
            ),
            _buildItem(
              context,
              item: AdminNavItem.aiReports,
              icon: Icons.auto_awesome,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required AdminNavItem item,
    required IconData icon,
  }) {
    final isActive = item == current;
    final color = isActive ? AppTheme.deepBlue : AppTheme.mediumGray;

    return Expanded(
      child: InkWell(
        onTap: () => _onTap(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
