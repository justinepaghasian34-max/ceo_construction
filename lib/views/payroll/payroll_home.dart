import 'package:flutter/material.dart';

import '../admin/admin_payroll.dart';
import '../admin/widgets/admin_glass_layout.dart';

/// Payroll Monitoring role home — same UI as admin Payroll Monitoring.
class PayrollHome extends StatelessWidget {
  const PayrollHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPayroll(
      showSidebar: true,
      showBottomNav: false,
      sidebarMode: AdminSidebarMode.payroll,
    );
  }
}
