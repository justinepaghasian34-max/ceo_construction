import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class SiteManagerBottomNav extends StatelessWidget {
  final int currentIndex;

  const SiteManagerBottomNav({super.key, required this.currentIndex});

  void _go(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(RouteNames.siteManagerHome);
        return;
      case 1:
        context.go(RouteNames.siteManagerTasks);
        return;
      case 2:
        context.go(RouteNames.attendance);
        return;
      case 3:
        context.go(RouteNames.siteManagerMaterials);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => _go(context, i),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.deepBlue,
          unselectedItemColor: AppTheme.mediumGray,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.checklist_outlined),
              activeIcon: Icon(Icons.checklist),
              label: 'Tasks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Attendance',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Materials',
            ),
          ],
        ),
      ),
    );
  }
}
