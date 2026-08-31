import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import 'widgets/site_manager_card.dart';

class MaterialInventoryScreen extends StatelessWidget {
  const MaterialInventoryScreen({super.key});

  String? get _projectId {
    final user = AuthService.instance.currentUser;
    if (user == null) return null;
    if (user.assignedProjects.isEmpty) return null;
    return user.assignedProjects.first;
  }

  double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().replaceAll(',', '')) ?? 0.0;
  }

  String _readString(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final projectId = _projectId;

    if (projectId == null || projectId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Material Inventory',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Text(
            'No assigned project found for this user',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.mediumGray),
          ),
        ),
      );
    }

    final allocationsStream = FirebaseService.instance
        .materialAllocationsCollection(projectId)
        .snapshots();

    final inventoryStream = FirebaseService.instance
        .materialInventoryCollection(projectId)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Material Inventory',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: allocationsStream,
          builder: (context, allocSnap) {
            if (allocSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (allocSnap.hasError) {
              return Center(
                child: Text(
                  'Failed to load assigned materials: ${allocSnap.error}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.errorRed),
                ),
              );
            }

            final allocDocs = allocSnap.data?.docs ?? const [];
            final allocations = allocDocs
                .map(
                  (d) => <String, dynamic>{
                    'id': d.id,
                    ...(d.data() as Map?)?.cast<String, dynamic>() ??
                        <String, dynamic>{},
                  },
                )
                .toList();

            allocations.sort((a, b) {
              final an = _readString(a['materialName']);
              final bn = _readString(b['materialName']);
              return an.compareTo(bn);
            });

            return StreamBuilder<QuerySnapshot>(
              stream: inventoryStream,
              builder: (context, invSnap) {
                if (invSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (invSnap.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load inventory: ${invSnap.error}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.errorRed),
                    ),
                  );
                }

                final invDocs = invSnap.data?.docs ?? const [];
                final inventory = invDocs
                    .map(
                      (d) => <String, dynamic>{
                        'id': d.id,
                        ...(d.data() as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{},
                      },
                    )
                    .toList();

                final Map<String, Map<String, dynamic>> invByKey = {};
                for (final inv in inventory) {
                  final key =
                      '${_readString(inv['materialName']).toLowerCase()}|${_readString(inv['unit']).toLowerCase()}';
                  if (key == '|') continue;
                  invByKey[key] = inv;
                }

                final List<Map<String, dynamic>> rows = [];

                for (final a in allocations) {
                  final name = _readString(a['materialName']);
                  final unit = _readString(a['unit']);
                  final required =
                      _readNum(a['requiredQuantity'] ?? a['budgetQuantity']);
                  final used = _readNum(a['usedQuantity']);
                  final remaining =
                      (required - used).clamp(0.0, double.infinity);

                  final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
                  final inv = invByKey[key];

                  final stock = inv == null ? remaining : _readNum(inv['stock']);

                  rows.add({
                    'materialName': name,
                    'unit': unit,
                    'budget': required,
                    'used': used,
                    'remaining': remaining,
                    'stock': stock,
                    'hasInventoryDoc': inv != null,
                  });
                }

                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'No assigned materials for this project yet',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.mediumGray),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    final name = _readString(r['materialName']);
                    final unit = _readString(r['unit']);
                    final budget = _readNum(r['budget']);
                    final used = _readNum(r['used']);
                    final remaining = _readNum(r['remaining']);
                    final stock = _readNum(r['stock']);

                    final low = remaining <= 0.0001;

                    return SiteManagerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: (low
                                          ? AppTheme.errorRed
                                          : AppTheme.softGreen)
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: (low
                                            ? AppTheme.errorRed
                                            : AppTheme.softGreen)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  low ? 'Out' : 'Available',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: low
                                            ? AppTheme.errorRed
                                            : AppTheme.softGreen,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: 'Budget',
                                  value:
                                      '${budget.toStringAsFixed(1)} $unit',
                                  color: AppTheme.residentBlue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Metric(
                                  label: 'Used',
                                  value: '${used.toStringAsFixed(1)} $unit',
                                  color: AppTheme.warningOrange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: 'Remaining',
                                  value:
                                      '${remaining.toStringAsFixed(1)} $unit',
                                  color: low
                                      ? AppTheme.errorRed
                                      : AppTheme.softGreen,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Metric(
                                  label: 'Stock',
                                  value:
                                      '${stock.toStringAsFixed(1)} $unit',
                                  color: AppTheme.mediumGray,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.mediumGray,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
