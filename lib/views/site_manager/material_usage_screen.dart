import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import 'widgets/site_manager_card.dart';
import '../../widgets/common/status_chip.dart';

class MaterialUsageScreen extends StatefulWidget {
  const MaterialUsageScreen({super.key});

  @override
  State<MaterialUsageScreen> createState() => _MaterialUsageScreenState();
}

class _MaterialUsageScreenState extends State<MaterialUsageScreen> {
  final _quantityController = TextEditingController();
  final _remarksController = TextEditingController();

  String? _selectedInventoryId;
  Map<String, dynamic>? _selectedInventory;

  String? _selectedManualMaterialName;
  String? _selectedManualUnit;

  static const List<String> _fallbackMaterials = [
    'Cement',
    'Sand',
    'Gravel',
    'Concrete',
    'Hollow Blocks',
    'Bricks',
    'Rebar (Steel Bars)',
    'Tie Wire',
    'Nails',
    'Screws',
    'Plywood',
    'Lumber (Wood)',
    'GI Sheet',
    'Roofing Sheet',
    'Paint',
    'Primer',
    'Thinner',
    'PVC Pipe',
    'Electrical Wire',
    'Conduit',
    'Tiles',
    'Adhesive',
    'Waterproofing',
  ];

  static const List<String> _fallbackUnits = [
    'Bags',
    'Sacks',
    'Pcs',
    'Boxes',
    'Bundles',
    'Rolls',
    'Meters',
    'Feet',
    'Kg',
    'Tons',
    'Liters',
    'Gallons',
    'Cubic meters',
  ];

  bool _isSubmitting = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _todayReportId(String projectId) {
    final dayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'material_usage_${projectId}_$dayKey';
  }

  Future<void> _addMaterialEntry({
    required String projectId,
    required String reportId,
    required String projectName,
  }) async {
    final inventory = _selectedInventory;
    final inventoryItemId = _selectedInventoryId;

    final qtyText = _quantityController.text.trim().replaceAll(',', '');
    final qty = double.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid quantity used.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final materialName = inventoryItemId != null && inventory != null
        ? (inventory['materialName'] ?? '').toString().trim()
        : (_selectedManualMaterialName ?? '').toString().trim();
    final unit = (_selectedManualUnit ?? '').toString().trim();
    if (materialName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected inventory item has no material name.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    if (unit.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a unit.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final id = const Uuid().v4();
    final nowIso = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'id': id,
      'projectId': projectId,
      'projectName': projectName,
      'reportId': reportId,
      'materialName': materialName,
      'quantity': qty,
      'unit': unit,
      'remarks': _remarksController.text.trim(),
      if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
      'status': 'used',
      'syncStatus': AppConstants.syncStatusPending,
      'date': nowIso,
    };

    await HiveService.instance.saveMaterialUsage(id, data);

    if (!mounted) return;
    setState(() {
      _quantityController.clear();
      _remarksController.clear();
      _selectedManualMaterialName = null;
      _selectedManualUnit = null;
    });
  }

  Future<void> _submitMaterialUsageReport() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = AuthService.instance.currentUser;
      final projectId = user?.assignedProjects.isNotEmpty == true
          ? user!.assignedProjects.first
          : null;
      if (projectId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No assigned project found for this user'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        return;
      }

      final result = await SyncService.instance.syncPendingData();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Material usage submitted successfully'
                : 'Material usage queued for sync when online',
          ),
          backgroundColor:
              result.success ? AppTheme.softGreen : AppTheme.warningOrange,
        ),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final projectId = user?.assignedProjects.isNotEmpty == true
        ? user!.assignedProjects.first
        : null;

    if (projectId == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Material Usage'),
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

    final reportId = _todayReportId(projectId);
    final inventoryStream = FirebaseService.instance
        .materialInventoryCollection(projectId)
        .orderBy('materialName')
        .snapshots();

    final todayUsages = HiveService.instance
        .getAllMaterialUsage()
        .where((u) => (u['reportId'] ?? '').toString() == reportId)
        .toList();
    todayUsages.sort((a, b) {
      final aDate = DateTime.tryParse((a['date'] ?? '').toString());
      final bDate = DateTime.tryParse((b['date'] ?? '').toString());
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return -1;
      if (bDate == null) return 1;
      return aDate.compareTo(bDate);
    });

    final projectName = projectId;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Material Usage',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SiteManagerCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today - $projectName',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(DateTime.now()),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SiteManagerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Material Usage',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: inventoryStream,
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? const [];
                      final items = docs
                          .map((d) => ((d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{})..['id'] = d.id)
                          .toList();

                      final isLoading =
                          snapshot.connectionState == ConnectionState.waiting;

                      final List<_MaterialOption> options = [
                        for (final item in items)
                          _MaterialOption(
                            key: 'inv:${(item['id'] ?? '').toString()}',
                            label:
                                (item['materialName'] ?? 'Material').toString(),
                            inventoryId: (item['id'] ?? '').toString(),
                            unit: (item['unit'] ?? '').toString(),
                            inventory: item,
                          ),
                        for (final name in _fallbackMaterials)
                          _MaterialOption(
                            key: 'man:$name',
                            label: name,
                          ),
                      ];

                      final currentKey = _selectedInventoryId != null
                          ? 'inv:$_selectedInventoryId'
                          : (_selectedManualMaterialName != null
                              ? 'man:$_selectedManualMaterialName'
                              : null);

                      final bool currentKeyExists = currentKey != null &&
                          options.any((o) => o.key == currentKey);

                      final initialKey = currentKeyExists ? currentKey : null;

                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: initialKey,
                            decoration: const InputDecoration(
                              labelText: 'Material Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final opt in options)
                                DropdownMenuItem<String>(
                                  value: opt.key,
                                  child: Text(
                                    opt.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: options.isEmpty
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    final selected = options.firstWhere(
                                      (o) => o.key == v,
                                      orElse: () => const _MaterialOption(
                                        key: '',
                                        label: '',
                                      ),
                                    );
                                    setState(() {
                                      if (selected.inventoryId != null) {
                                        _selectedInventoryId = selected.inventoryId;
                                        _selectedInventory = selected.inventory;
                                        _selectedManualMaterialName = null;
                                        final unit = (selected.unit ?? '').toString().trim();
                                        _selectedManualUnit = unit.isEmpty ? null : unit;
                                      } else {
                                        _selectedInventoryId = null;
                                        _selectedInventory = null;
                                        _selectedManualMaterialName = selected.label;
                                      }
                                    });
                                  },
                          ),
                          if (isLoading) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(minHeight: 2),
                          ],
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 420;

                              final qtyField = TextField(
                                controller: _quantityController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity Used',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              );

                              final unitField = DropdownButtonFormField<String>(
                                initialValue: _selectedManualUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  for (final u in _fallbackUnits)
                                    DropdownMenuItem<String>(
                                      value: u,
                                      child: Text(u, overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    _selectedManualUnit = v;
                                  });
                                },
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    qtyField,
                                    const SizedBox(height: 12),
                                    unitField,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: qtyField),
                                  const SizedBox(width: 12),
                                  Expanded(child: unitField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _remarksController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Remarks',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.warningOrange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _addMaterialEntry(
                                projectId: projectId,
                                reportId: reportId,
                                projectName: projectName,
                              ),
                              child: const Text('Add Material Entry'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SiteManagerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Usage",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (todayUsages.isEmpty)
                    Text(
                      'No entries yet.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.mediumGray),
                    )
                  else
                    ...todayUsages.map((usage) {
                      final materialName =
                          (usage['materialName'] ?? 'Material').toString();
                      final quantity = (usage['quantity'] ?? 0).toString();
                      final unit = (usage['unit'] ?? '').toString();
                      final syncStatus = (usage['syncStatus'] ??
                              AppConstants.syncStatusPending)
                          .toString();
                      final date = DateTime.tryParse((usage['date'] ?? '').toString());
                      final timeLabel = date == null
                          ? ''
                          : TimeOfDay.fromDateTime(date).format(context);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    materialName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$quantity $unit',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppTheme.mediumGray),
                                  ),
                                ],
                              ),
                            ),
                            if (timeLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  timeLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              ),
                            SyncStatusChip(syncStatus: syncStatus, isSmall: true),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.warningOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: todayUsages.isEmpty || _isSubmitting
                    ? null
                    : _submitMaterialUsageReport,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Material Usage Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialOption {
  final String key;
  final String label;
  final String? inventoryId;
  final String? unit;
  final Map<String, dynamic>? inventory;

  const _MaterialOption({
    required this.key,
    required this.label,
    this.inventoryId,
    this.unit,
    this.inventory,
  });
}
