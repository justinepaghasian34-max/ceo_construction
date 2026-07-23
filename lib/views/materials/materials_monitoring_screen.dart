import 'package:flutter/material.dart';

import '../admin/admin_material_monitoring.dart';
import '../admin/widgets/admin_glass_layout.dart';

class MaterialsMonitoringScreen extends StatelessWidget {
  const MaterialsMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminMaterialMonitoring(
      showSidebar: true,
      showBottomNav: false,
      sidebarMode: AdminSidebarMode.materials,
    );
  }
}
