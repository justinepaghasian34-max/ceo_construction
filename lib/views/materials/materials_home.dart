import 'package:flutter/material.dart';

import '../admin/admin_material_monitoring.dart';
import '../admin/widgets/admin_glass_layout.dart';

/// Material Monitoring role home — same UI as admin Material & Inventory Monitoring.
class MaterialsHome extends StatelessWidget {
  const MaterialsHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminMaterialMonitoring(
      showSidebar: true,
      showBottomNav: false,
      sidebarMode: AdminSidebarMode.materials,
    );
  }
}
