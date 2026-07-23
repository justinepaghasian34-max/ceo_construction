import 'package:flutter/material.dart';

import '../admin/admin_payroll.dart';
import '../admin/widgets/admin_glass_layout.dart';

class PayrollMonitoringScreen extends StatelessWidget {
  const PayrollMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPayroll(
      showSidebar: true,
      showBottomNav: false,
      sidebarMode: AdminSidebarMode.payroll,
    );
  }
}
