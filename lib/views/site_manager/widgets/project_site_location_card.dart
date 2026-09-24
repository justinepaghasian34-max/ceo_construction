import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/firebase_service.dart';

/// Project site pin for the Resident Engineer dashboard.
class ProjectSiteLocationCard extends StatelessWidget {
  const ProjectSiteLocationCard({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseService.instance.projectsCollection.doc(projectId).snapshots(),
      builder: (context, snapshot) {
        final raw = snapshot.data?.data();
        final data = raw is Map<String, dynamic>
            ? raw
            : (raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{});
        final name = (data['name'] ?? 'Assigned project').toString().trim();
        final location = (data['location'] ?? '').toString().trim();
        final geoAddress = (data['geoAddress'] ?? '').toString().trim();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        final label = geoAddress.isNotEmpty
            ? geoAddress
            : (location.isNotEmpty ? location : name);
        final hasPin =
            lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.residentBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.residentBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Project site location',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            name,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasPin
                                ? label
                                : 'No pin yet. Ask admin to set the project location when creating the project.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                  color: hasPin
                                      ? const Color(0xFF0F172A)
                                      : AppTheme.mediumGray,
                                ),
                          ),
                          if (hasPin) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _MetaChip(
                                  icon: Icons.my_location_outlined,
                                  text:
                                      '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
                                ),
                                if (location.isNotEmpty && location != label)
                                  _MetaChip(
                                    icon: Icons.place_outlined,
                                    text: location,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasPin)
                SizedBox(
                  height: 200,
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(lat, lon),
                          initialZoom: 14.2,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.pinchZoom |
                                InteractiveFlag.drag |
                                InteractiveFlag.doubleTapZoom,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            tileProvider: CancellableNetworkTileProvider(),
                            userAgentPackageName:
                                'com.ceoconstruction.monitoring',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(lat, lon),
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: AppTheme.residentBlue,
                                  size: 44,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Text(
                            'Pinned project area',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: AppTheme.mediumGray.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Map appears here once the project has a saved pin.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.residentBlue),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
