import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/site_weather_provider.dart';
import 'widgets/admin_glass_layout.dart';
import 'widgets/admin_bottom_nav.dart';

class AdminSiteWeatherMapScreen extends ConsumerStatefulWidget {
  const AdminSiteWeatherMapScreen({super.key});

  @override
  ConsumerState<AdminSiteWeatherMapScreen> createState() =>
      _AdminSiteWeatherMapScreenState();
}

class _AdminSiteWeatherMapScreenState
    extends ConsumerState<AdminSiteWeatherMapScreen> {
  final MapController _mapController = MapController();

  /// The site the user tapped — shows the detail panel.
  SiteWeatherSnapshot? _selected;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Color _pinColor(SiteWeatherSnapshot snap) {
    final c = snap.condition.toLowerCase();
    if (c.contains('rain') ||
        c.contains('drizzle') ||
        c.contains('thunderstorm')) {
      return const Color(0xFF3B82F6); // blue
    }
    if (c.contains('cloud')) { return AppTheme.mediumGray; }
    return AppTheme.warningOrange; // sunny
  }

  IconData _pinIcon(SiteWeatherSnapshot snap) {
    final c = snap.condition.toLowerCase();
    if (c.contains('rain') ||
        c.contains('drizzle') ||
        c.contains('thunderstorm')) { return Icons.grain; }
    if (c.contains('cloud')) { return Icons.cloud_outlined; }
    return Icons.wb_sunny_outlined;
  }

  String _conditionLabel(SiteWeatherSnapshot snap) {
    final c = snap.condition.toLowerCase();
    if (c.contains('rain') ||
        c.contains('drizzle') ||
        c.contains('thunderstorm')) { return 'Raining'; }
    if (c.contains('cloud')) { return 'Cloudy'; }
    return 'Sunny';
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<SiteWeatherSnapshot>>>(
      adminProjectMapSitesProvider,
      (previous, next) {
        final sites = next.valueOrNull;
        if (sites == null || sites.isEmpty) return;
        final previousCount = previous?.valueOrNull?.length ?? 0;
        if (sites.length <= previousCount) return;
        final newest = sites.last;
        try {
          _mapController.move(LatLng(newest.lat, newest.lon), 11);
        } catch (_) {}
      },
    );

    final sitesAsync = ref.watch(adminProjectMapSitesProvider);

    return AdminGlassScaffold(
      title: 'Site Weather Map',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(adminProjectMapSitesProvider);
            ref.invalidate(adminSiteWeatherSnapshotsProvider);
            ref.invalidate(allSitesWeatherProvider);
          },
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.dashboard,
      ),
      child: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load project locations.\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (sites) {
          final mappable = sites
              .where((s) => s.lat.isFinite && s.lon.isFinite)
              .where((s) => s.lat.abs() <= 90 && s.lon.abs() <= 180)
              .toList();
          if (mappable.isEmpty) {
            return _EmptyState(
              onRefresh: () {
                ref.invalidate(adminProjectMapSitesProvider);
              },
            );
          }

          final avgLat = mappable.map((s) => s.lat).reduce((a, b) => a + b) /
              mappable.length;
          final avgLon = mappable.map((s) => s.lon).reduce((a, b) => a + b) /
              mappable.length;
          final center = (avgLat.isFinite && avgLon.isFinite)
              ? LatLng(avgLat, avgLon)
              : LatLng(mappable.first.lat, mappable.first.lon);

          final mapHeight =
              (MediaQuery.sizeOf(context).height * 0.72).clamp(440.0, 820.0);

          return SizedBox(
            height: mapHeight,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  if (!w.isFinite ||
                      !h.isFinite ||
                      w < 8 ||
                      h < 8) {
                    return const ColoredBox(
                      color: Color(0xFFE2E8F0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: mappable.length == 1 ? 13 : 8,
                          backgroundColor: const Color(0xFFE2E8F0),
                          onTap: (_, __) =>
                              setState(() => _selected = null),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.ceoconstruction.monitoring',
                          ),
                          MarkerLayer(
                            markers: mappable.map(_buildMarker).toList(),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _Legend(),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _SiteListPanel(
                          sites: mappable,
                          selected: _selected,
                          conditionLabel: _conditionLabel,
                          pinColor: _pinColor,
                          pinIcon: _pinIcon,
                          onSelect: (snap) {
                            setState(() => _selected = snap);
                            try {
                              _mapController.move(
                                LatLng(snap.lat, snap.lon),
                                13,
                              );
                            } catch (_) {}
                          },
                        ),
                      ),
                      if (_selected != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _DetailPanel(
                            snap: _selected!,
                            conditionLabel: _conditionLabel(_selected!),
                            pinColor: _pinColor(_selected!),
                            pinIcon: _pinIcon(_selected!),
                            onClose: () =>
                                setState(() => _selected = null),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Marker _buildMarker(SiteWeatherSnapshot snap) {
    final color = _pinColor(snap);
    final isSelected = _selected?.projectId == snap.projectId;
    final place =
        snap.location.trim().isNotEmpty ? snap.location.trim() : snap.projectName;

    return Marker(
      point: LatLng(snap.lat, snap.lon),
      width: isSelected ? 168 : 148,
      height: isSelected ? 102 : 90,
      child: GestureDetector(
        onTap: () {
          setState(() => _selected = snap);
          _mapController.move(LatLng(snap.lat, snap.lon), 13);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on,
                color: isSelected ? color : const Color(0xFFE11D48),
                size: isSelected ? 40 : 34,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  place,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSelected ? 10 : 9,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkGray,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Legend ─────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          _LegendRow(color: AppTheme.warningOrange, label: 'Sunny'),
          SizedBox(height: 6),
          _LegendRow(color: AppTheme.mediumGray, label: 'Cloudy'),
          SizedBox(height: 6),
          _LegendRow(color: Color(0xFF3B82F6), label: 'Raining'),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.darkGray,
          ),
        ),
      ],
    );
  }
}

// ── Site list panel ─────────────────────────────────────────────────────────

class _SiteListPanel extends StatelessWidget {
  const _SiteListPanel({
    required this.sites,
    required this.selected,
    required this.conditionLabel,
    required this.pinColor,
    required this.pinIcon,
    required this.onSelect,
  });

  final List<SiteWeatherSnapshot> sites;
  final SiteWeatherSnapshot? selected;
  final String Function(SiteWeatherSnapshot) conditionLabel;
  final Color Function(SiteWeatherSnapshot) pinColor;
  final IconData Function(SiteWeatherSnapshot) pinIcon;
  final ValueChanged<SiteWeatherSnapshot> onSelect;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 340),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'Project Sites (${sites.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkGray,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sites.length,
                itemBuilder: (context, i) {
                  final snap = sites[i];
                  final isSelected =
                      selected?.projectId == snap.projectId;
                  final color = pinColor(snap);
                  final icon = pinIcon(snap);
                  return InkWell(
                    onTap: () => onSelect(snap),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      color: isSelected
                          ? color.withValues(alpha: 0.10)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.14),
                            ),
                            child: Icon(icon, size: 14, color: color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  snap.projectName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? color
                                        : AppTheme.darkGray,
                                  ),
                                ),
                                Text(
                                  snap.location.isNotEmpty
                                      ? snap.location
                                      : '${conditionLabel(snap)} · ${snap.tempC.toStringAsFixed(0)}°C',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.mediumGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail panel (bottom sheet style) ──────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.snap,
    required this.conditionLabel,
    required this.pinColor,
    required this.pinIcon,
    required this.onClose,
  });

  final SiteWeatherSnapshot snap;
  final String conditionLabel;
  final Color pinColor;
  final IconData pinIcon;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isRaining = snap.isRaining;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.mediumGray.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ─────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pinColor.withValues(alpha: 0.14),
                      ),
                      child: Icon(pinIcon, color: pinColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snap.projectName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (snap.location.isNotEmpty)
                            Text(
                              snap.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.mediumGray),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: onClose,
                      color: AppTheme.mediumGray,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Rain alert banner ──────────────────────────────────────
                if (isRaining)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            const Color(0xFF3B82F6).withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFF3B82F6), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Rain detected at this site. '
                            'Admin has been notified. '
                            'Consider pausing outdoor work.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF1D4ED8),
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Metrics grid ───────────────────────────────────────────
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Metric(
                      label: 'Condition',
                      value: conditionLabel,
                      icon: pinIcon,
                      color: pinColor,
                    ),
                    _Metric(
                      label: 'Temperature',
                      value: '${snap.tempC.toStringAsFixed(1)}°C',
                      icon: Icons.thermostat_outlined,
                      color: pinColor,
                    ),
                    if (snap.description.isNotEmpty)
                      _Metric(
                        label: 'Description',
                        value: snap.description,
                        icon: Icons.info_outline_rounded,
                        color: AppTheme.mediumGray,
                      ),
                    _Metric(
                      label: 'Coordinates',
                      value:
                          '${snap.lat.toStringAsFixed(4)}, '
                          '${snap.lon.toStringAsFixed(4)}',
                      icon: Icons.location_on_outlined,
                      color: AppTheme.mediumGray,
                    ),
                    _Metric(
                      label: 'Last Updated',
                      value: _formatTime(snap.fetchedAt),
                      icon: Icons.schedule_rounded,
                      color: AppTheme.mediumGray,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $suffix';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.mediumGray,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkGray,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: AppTheme.mediumGray.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No mappable project locations yet.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Each project needs a location name or map pin. '
              'Open a project and save its site location so it appears here.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mediumGray),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
