import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class SiteManagerBottomNav extends StatelessWidget {
  final int currentIndex;
  final bool dark;

  const SiteManagerBottomNav({
    super.key,
    required this.currentIndex,
    this.dark = false,
  });

  void _go(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(RouteNames.siteManagerHome);
        return;
      case 1:
        context.go(RouteNames.govTrackAi);
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
    final bg = dark ? const Color(0xFF1E1F20) : Colors.white;
    final selected = dark ? const Color(0xFFA8C7FA) : AppTheme.residentBlue;
    final unselected = dark ? const Color(0xFFC4C7C5) : AppTheme.mediumGray;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: dark
              ? const Border(top: BorderSide(color: Color(0xFF2F3031)))
              : null,
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => _go(context, i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: bg,
          elevation: 0,
          selectedItemColor: selected,
          unselectedItemColor: unselected,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: 'BuildIQ',
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
