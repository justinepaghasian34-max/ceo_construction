import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/site_manager_bottom_nav.dart';

class MaterialsHubScreen extends StatelessWidget {
  const MaterialsHubScreen({
    super.key,
    this.showBottomNav = false,
    this.showBack = true,
  });

  final bool showBottomNav;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppTheme.residentBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          'Materials',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppTheme.residentHeaderGradient,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Site materials',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Log usage, record deliveries, and request materials from admin.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MaterialHubTile(
            icon: Icons.construction_outlined,
            iconColor: const Color(0xFFEA580C),
            iconBg: const Color(0xFFFFF7ED),
            title: 'Material Usage',
            subtitle: 'Record materials used on site today',
            onTap: () => context.push(RouteNames.materialUsage),
          ),
          const SizedBox(height: 10),
          _MaterialHubTile(
            icon: Icons.local_shipping_outlined,
            iconColor: AppTheme.residentBlue,
            iconBg: const Color(0xFFEFF6FF),
            title: 'Material Delivery',
            subtitle: 'Log supplier deliveries received on site',
            onTap: () => context.push(RouteNames.materialDelivery),
          ),
          const SizedBox(height: 10),
          _MaterialHubTile(
            icon: Icons.assignment_outlined,
            iconColor: const Color(0xFF16A34A),
            iconBg: const Color(0xFFECFDF5),
            title: 'Material Request',
            subtitle: 'Request approval from admin for extra materials',
            onTap: () => context.push(RouteNames.materialRequest),
          ),
        ],
      ),
      bottomNavigationBar: showBottomNav
          ? const SiteManagerBottomNav(currentIndex: 3)
          : null,
    );
  }
}

class _MaterialHubTile extends StatelessWidget {
  const _MaterialHubTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.mediumGray.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}
