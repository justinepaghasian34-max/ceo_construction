import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/firebase_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/sync_service.dart';
import '../../services/hive_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

class AdminMaterialMonitoring extends StatefulWidget {
  const AdminMaterialMonitoring({
    super.key,
    this.initialProjectId,
    this.initialProjectName,
    this.showSidebar = true,
    this.showBottomNav = true,
    this.sidebarMode = AdminSidebarMode.full,
  });

  final String? initialProjectId;
  final String? initialProjectName;
  final bool showSidebar;
  final bool showBottomNav;
  final AdminSidebarMode sidebarMode;

  @override
  State<AdminMaterialMonitoring> createState() => _AdminMaterialMonitoringState();
}

class _AdminMaterialMonitoringState extends State<AdminMaterialMonitoring> with SingleTickerProviderStateMixin {
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
  String? _selectedProjectId;
  String? _selectedProjectName;

  List<Map<String, String>> _projectOptions = const [];
  List<Map<String, String>> _allProjectOptions = const [];

  String? _projectsWithInventoryCacheKey;
  Set<String>? _projectsWithInventoryCache;

  @override
  void initState() {
    super.initState();
    final pid = widget.initialProjectId;
    if (pid != null && pid.trim().isNotEmpty) {
      _selectedProjectId = pid.trim();
      final pn = widget.initialProjectName;
      if (pn != null && pn.trim().isNotEmpty) {
        _selectedProjectName = pn.trim();
      }
    }
  }

  bool _isFirestoreUnreachableError(Object e) {
    final errorText = e.toString().toLowerCase();
    final looksLikeDns = errorText.contains('unknownhostexception') ||
        errorText.contains('unable to resolve host') ||
        errorText.contains('eai_nodata') ||
        errorText.contains('firestore.googleapis.com');
    final looksUnavailable = errorText.contains('status{code=unavailable') ||
        errorText.contains('code=unavailable') ||
        errorText.contains('unavailable');
    return looksLikeDns || looksUnavailable;
  }

  Future<Set<String>> _getProjectsWithInventory(
    List<QueryDocumentSnapshot> projectDocs,
  ) async {
    final ids = projectDocs.map((d) => d.id).toList()..sort();
    final key = ids.join('|');
    final cached = _projectsWithInventoryCache;
    if (_projectsWithInventoryCacheKey == key && cached != null) {
      return cached;
    }

    final result = <String>{};
    for (final doc in projectDocs) {
      final projectId = doc.id;
      try {
        final snap = await FirebaseService.instance
            .materialInventoryCollection(projectId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          result.add(projectId);
        }
      } catch (_) {
        // Ignore per-project errors and just don't include it in the list.
      }
    }

    _projectsWithInventoryCacheKey = key;
    _projectsWithInventoryCache = result;
    return result;
  }

  Future<void> _showSyncInventoryToBudgetDialog() async {
    final projectId = _selectedProjectId;
    if (projectId == null || projectId.isEmpty) return;

    final rootMessenger = ScaffoldMessenger.of(context);

    try {
      final invSnap = await FirebaseService.instance
          .materialInventoryCollection(projectId)
          .orderBy('materialName')
          .get();
      final allocSnap = await FirebaseService.instance
          .materialAllocationsCollection(projectId)
          .orderBy('materialName')
          .get();

      String norm(String s) => s.trim().toLowerCase();

      final existingAllocNames = <String>{
        for (final d in allocSnap.docs)
          norm(((d.data() as Map?)?.cast<String, dynamic>() ?? const {})['materialName']?.toString() ?? ''),
      }..remove('');

      final inventoryItems = <Map<String, dynamic>>[];
      for (final d in invSnap.docs) {
        final data = (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final name = (data['materialName'] ?? '').toString();
        final unit = (data['unit'] ?? '').toString();
        final unitPrice = data['unitPrice'] ?? data['price'];
        if (norm(name).isEmpty) continue;
        if (existingAllocNames.contains(norm(name))) continue;
        inventoryItems.add(<String, dynamic>{
          'materialName': name,
          'unit': unit,
          if (unitPrice != null) 'unitPrice': unitPrice,
        });
      }

      if (!mounted) return;

      if (inventoryItems.isEmpty) {
        rootMessenger.showSnackBar(
          const SnackBar(
            content: Text('All inventory materials are already assigned/budgeted for this project.'),
            backgroundColor: AppTheme.softGreen,
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setStateDialog) {
              bool isSaving = false;

              final controllers = <String, TextEditingController>{
                for (final it in inventoryItems)
                  norm((it['materialName'] ?? '').toString()): TextEditingController(),
              };

              Future<void> save() async {
                if (isSaving) return;
                setStateDialog(() => isSaving = true);

                final navigator = Navigator.of(dialogContext);
                try {
                  final nowIso = DateTime.now().toIso8601String();
                  final batch = FirebaseService.instance.firestore.batch();
                  final queued = <Map<String, dynamic>>[];
                  int added = 0;

                  for (final it in inventoryItems) {
                    final name = (it['materialName'] ?? '').toString().trim();
                    final unit = (it['unit'] ?? '').toString().trim();
                    final unitPrice = it['unitPrice'];
                    final key = norm(name);
                    final text = controllers[key]?.text.trim() ?? '';
                    final budget = double.tryParse(text.replaceAll(',', ''));
                    if (budget == null || budget <= 0) continue;

                    final ref = FirebaseService.instance
                        .materialAllocationsCollection(projectId)
                        .doc();
                    final payload = <String, dynamic>{
                      'id': ref.id,
                      'materialName': name,
                      'unit': unit,
                      'budgetQuantity': budget,
                      'requiredQuantity': budget,
                      'usedQuantity': 0,
                      if (unitPrice != null) 'unitPrice': unitPrice,
                      'projectId': projectId,
                      'projectName': _selectedProjectName,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    batch.set(ref, payload);
                    queued.add(<String, dynamic>{
                      ...payload,
                      'createdAt': nowIso,
                      'updatedAt': nowIso,
                    });
                    added++;
                  }

                  if (added == 0) {
                    setStateDialog(() => isSaving = false);
                    rootMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Enter a valid budget quantity for at least one material.'),
                        backgroundColor: AppTheme.errorRed,
                      ),
                    );
                    return;
                  }

                  try {
                    await batch.commit();
                    navigator.pop();
                    rootMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Added $added materials to site budget (assigned materials).'),
                        backgroundColor: AppTheme.softGreen,
                      ),
                    );
                  } catch (e) {
                    if (!_isFirestoreUnreachableError(e)) rethrow;
                    for (final p in queued) {
                      final docId = (p['id'] ?? '').toString();
                      if (docId.isEmpty) continue;
                      await SyncService.instance.addToSyncQueue(
                        'material_allocation_upsert',
                        <String, dynamic>{
                          'projectId': projectId,
                          'docId': docId,
                          'payload': p,
                        },
                      );
                    }
                    navigator.pop();
                    rootMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Saved offline ($added). Will sync to Firestore when online.'),
                        backgroundColor: AppTheme.warningOrange,
                      ),
                    );
                  }
                } catch (e) {
                  setStateDialog(() => isSaving = false);
                  rootMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Sync failed: $e'),
                      backgroundColor: AppTheme.errorRed,
                    ),
                  );
                }
              }

              return AlertDialog(
                title: const Text('Sync Inventory → Site Budget'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'These inventory materials are not yet assigned/budgeted for this project. Enter the budget quantity to add them to Assigned materials.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 340),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: inventoryItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final it = inventoryItems[i];
                            final name = (it['materialName'] ?? '').toString();
                            final unit = (it['unit'] ?? '').toString();
                            final key = norm(name);
                            return Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    unit.isEmpty ? '-' : unit,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppTheme.mediumGray),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: controllers[key],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    enabled: !isSaving,
                                    decoration: const InputDecoration(
                                      labelText: 'Budget qty',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isSaving ? null : save,
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      rootMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to load inventory/assigned materials: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  Future<void> _showAddInventoryItemDialog() async {
    final projectId = _selectedProjectId;
    if (projectId == null || projectId.isEmpty) return;

    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final stockController = TextEditingController();
    final unitPriceController = TextEditingController();
    final budgetController = TextEditingController();

    final rootMessenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            bool saveToInventory = true;
            bool saveToBudget = false;
            bool isSaving = false;

            Future<void> save() async {
              if (isSaving) return;
              setStateDialog(() => isSaving = true);

              final navigator = Navigator.of(dialogContext);
              final name = nameController.text.trim();
              final unit = unitController.text.trim();
              final stock = double.tryParse(
                stockController.text.trim().replaceAll(',', ''),
              );
              final unitPrice = double.tryParse(
                unitPriceController.text.trim().replaceAll(',', ''),
              );
              final budget = double.tryParse(
                budgetController.text.trim().replaceAll(',', ''),
              );

              if (!saveToInventory && !saveToBudget) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please select where to save: Inventory and/or Site budget.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              if (name.isEmpty || unit.isEmpty) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter material name and unit.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              if (saveToInventory && (stock == null || stock < 0)) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter material name, unit, and a valid stock.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              if (saveToBudget && (budget == null || budget <= 0)) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid budget quantity.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              try {
                if (saveToInventory) {
                  final nowIso = DateTime.now().toIso8601String();
                  final docRef = FirebaseService.instance
                      .materialInventoryCollection(projectId)
                      .doc();
                  final payload = <String, dynamic>{
                    'id': docRef.id,
                    'materialName': name,
                    'unit': unit,
                    'stock': stock,
                    if (unitPrice != null && unitPrice >= 0) 'unitPrice': unitPrice,
                    'projectId': projectId,
                    'projectName': _selectedProjectName,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  try {
                    await docRef.set(payload);
                  } catch (e) {
                    if (_isFirestoreUnreachableError(e)) {
                      final queuedPayload = <String, dynamic>{
                        ...payload,
                        'createdAt': nowIso,
                        'updatedAt': nowIso,
                      };
                      await HiveService.instance.saveMaterialInventory(docRef.id, queuedPayload);
                      await SyncService.instance.addToSyncQueue(
                        'material_inventory_upsert',
                        <String, dynamic>{
                          'projectId': projectId,
                          'docId': docRef.id,
                          'payload': queuedPayload,
                        },
                      );
                    } else {
                      rethrow;
                    }
                  }
                }

                if (saveToBudget) {
                  final nowIso = DateTime.now().toIso8601String();
                  final docRef = FirebaseService.instance
                      .materialAllocationsCollection(projectId)
                      .doc();
                  final payload = <String, dynamic>{
                    'id': docRef.id,
                    'materialName': name,
                    'unit': unit,
                    'budgetQuantity': budget,
                    'requiredQuantity': budget,
                    'usedQuantity': 0,
                    if (unitPrice != null && unitPrice >= 0) 'unitPrice': unitPrice,
                    'projectId': projectId,
                    'projectName': _selectedProjectName,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  try {
                    await docRef.set(payload);
                  } catch (e) {
                    if (_isFirestoreUnreachableError(e)) {
                      final queuedPayload = <String, dynamic>{
                        ...payload,
                        'createdAt': nowIso,
                        'updatedAt': nowIso,
                      };
                      await SyncService.instance.addToSyncQueue(
                        'material_allocation_upsert',
                        <String, dynamic>{
                          'projectId': projectId,
                          'docId': docRef.id,
                          'payload': queuedPayload,
                        },
                      );
                    } else {
                      rethrow;
                    }
                  }
                }

                navigator.pop();
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      saveToInventory && saveToBudget
                          ? 'Saved to inventory and site budget.'
                          : (saveToBudget
                              ? 'Saved to site budget.'
                              : 'Saved to inventory. Assign/budget this material to allow site requests.'),
                    ),
                    backgroundColor: AppTheme.softGreen,
                  ),
                );
              } catch (e) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to add item: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Add Inventory Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: saveToInventory,
                      onChanged: isSaving
                          ? null
                          : (v) => setStateDialog(() => saveToInventory = v ?? false),
                      title: const Text('Save to inventory'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: saveToBudget,
                      onChanged: isSaving
                          ? null
                          : (v) => setStateDialog(() => saveToBudget = v ?? false),
                      title: const Text('Save to site budget (Assigned materials)'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Material name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Unit (e.g. bag, pcs)'),
                    ),
                    const SizedBox(height: 8),
                    if (saveToInventory) ...[
                      TextField(
                        controller: stockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Initial stock'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Unit price (₱)'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (saveToBudget) ...[
                      TextField(
                        controller: budgetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                        decoration: const InputDecoration(labelText: 'Budget quantity'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectStream = FirebaseService.instance.projectsCollection
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: projectStream,
      builder: (context, projectSnap) {
        final projectDocs = projectSnap.data?.docs ?? const [];
        _allProjectOptions = [
          for (final d in projectDocs)
            () {
              final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final name = (data['name'] ?? d.id).toString();
              return <String, String>{
                'id': d.id,
                'name': name,
              };
            }(),
        ];
        _allProjectOptions.sort(
          (a, b) => (a['name'] ?? '').compareTo((b['name'] ?? '')),
        );

        final Map<String, String> siteManagerNameByProject = {};
        for (final doc in projectDocs) {
          final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final name = (data['siteManagerName'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            siteManagerNameByProject[doc.id] = name;
          }
        }

        String siteLabel(String projectId) {
          final name = siteManagerNameByProject[projectId];
          if (name != null && name.isNotEmpty) return name;
          return projectId;
        }

        if (_selectedProjectId == null && projectDocs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_selectedProjectId != null) return;
            final d = projectDocs.first;
            final data = (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            setState(() {
              _selectedProjectId = d.id;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          });
        }

        final selectedProjectId = _selectedProjectId;
        final inventoryStream = selectedProjectId == null
            ? Stream<QuerySnapshot>.empty()
            : FirebaseService.instance.materialInventoryCollection(selectedProjectId)
                .orderBy('materialName')
                .snapshots();

        final deliveriesStream = FirebaseService.instance.firestore
            .collectionGroup('deliveries')
            .where('type', isEqualTo: 'material_request_release')
            .limit(500)
            .snapshots();

        final usageStream = FirebaseService.instance.firestore
            .collectionGroup('material_usage')
            .limit(500)
            .snapshots();

        return StreamBuilder<QuerySnapshot>(
          stream: inventoryStream,
          builder: (context, invSnap) {
            if (invSnap.hasError) {
              return AdminGlassScaffold(
                title: 'Material & Inventory Monitoring',
                showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                bottomNavigationBar: widget.showBottomNav
                    ? const AdminBottomNavBar(
                        current: AdminNavItem.materialInventory,
                      )
                    : null,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load inventory: ${invSnap.error}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.errorRed,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            final inventoryItems = invSnap.data?.docs
                    .map((d) => ((d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{})..['id'] = d.id)
                    .toList() ??
                <Map<String, dynamic>>[];

            // Build a price lookup from inventory (by material name)
            final Map<String, double> unitPriceByMaterial = {};
            for (final item in inventoryItems) {
              final name = (item['materialName'] ?? '').toString();
              if (name.isEmpty) continue;
              final priceRaw = item['unitPrice'] ?? item['price'];
              double? price;
              if (priceRaw is num) {
                price = priceRaw.toDouble();
              } else if (priceRaw is String) {
                final cleaned = priceRaw.replaceAll(',', '').replaceAll('₱', '').trim();
                price = double.tryParse(cleaned);
              }
              if (price != null) {
                unitPriceByMaterial[name] = price;
              }
            }

            double totalStock = 0;
            for (final item in inventoryItems) {
              final stockRaw = item['stock'];
              double stock;
              if (stockRaw is num) {
                stock = stockRaw.toDouble();
              } else {
                stock = double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;
              }
              totalStock += stock;
            }

            return StreamBuilder<QuerySnapshot>(
              stream: deliveriesStream,
              builder: (context, deliveriesSnap) {
                if (deliveriesSnap.hasError) {
                  return AdminGlassScaffold(
                    title: 'Material & Inventory Monitoring',
                    showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                    bottomNavigationBar: widget.showBottomNav
                        ? const AdminBottomNavBar(
                            current: AdminNavItem.materialInventory,
                          )
                        : null,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Failed to load deliveries: ${deliveriesSnap.error}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppTheme.errorRed,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }

                if (!deliveriesSnap.hasData) {
                  return AdminGlassScaffold(
                    title: 'Material & Inventory Monitoring',
                    showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                    bottomNavigationBar: widget.showBottomNav
                        ? const AdminBottomNavBar(
                            current: AdminNavItem.materialInventory,
                          )
                        : null,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                final deliveryDocs = deliveriesSnap.data?.docs ?? const [];
                final deliveryRows = deliveryDocs
                    .map(
                      (d) => <String, dynamic>{
                        ...(d.data() as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{},
                        'id': d.id,
                      },
                    )
                    .toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: usageStream,
                  builder: (context, usageSnap) {
                    if (usageSnap.hasError) {
                      return AdminGlassScaffold(
                        title: 'Material & Inventory Monitoring',
                        showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                        bottomNavigationBar: widget.showBottomNav
                            ? const AdminBottomNavBar(
                                current: AdminNavItem.materialInventory,
                              )
                            : null,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Failed to load material usage: ${usageSnap.error}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.errorRed,
                                    fontWeight: FontWeight.w700,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }

                    if (!usageSnap.hasData) {
                      return AdminGlassScaffold(
                        title: 'Material & Inventory Monitoring',
                        showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                        bottomNavigationBar: widget.showBottomNav
                            ? const AdminBottomNavBar(
                                current: AdminNavItem.materialInventory,
                              )
                            : null,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }

                    final usageDocs = usageSnap.data?.docs ?? const [];
                    final usageRows = usageDocs
                        .map(
                          (d) => <String, dynamic>{
                            ...(d.data() as Map?)?.cast<String, dynamic>() ??
                                <String, dynamic>{},
                            'id': d.id,
                          },
                        )
                        .toList();

                    final combinedDocs = <Map<String, dynamic>>[
                      ...usageRows,
                      ...deliveryRows,
                    ];

                    final now = DateTime.now();
                    final startOfMonth = DateTime(now.year, now.month, 1);
                    final endOfMonth = DateTime(now.year, now.month + 1, 1);

                    double monthQuantity = 0;
                    final List<_MaterialUsageEntry> usageEntries = [];
                    final List<_MaterialUsageEntry> monthUsageEntries = [];

                    for (final usage in combinedDocs) {
                      final isDelivery =
                          (usage['type'] ?? '').toString() ==
                              'material_request_release';

                      final name = (usage['materialName'] ??
                              usage['name'] ??
                              usage['subject'] ??
                              'Material')
                          .toString();

                      final quantityRaw = isDelivery
                          ? (usage['quantity'] ?? 0)
                          : (usage['quantity'] ?? usage['stock'] ?? 0);
                      final quantity =
                          double.tryParse(quantityRaw.toString()) ?? 0.0;

                      DateTime? usageDate;
                      final dateRaw = isDelivery
                          ? (usage['approvedAt'] ?? usage['createdAt'])
                          : (usage['date'] ?? usage['createdAt']);
                      if (dateRaw is String) {
                        try {
                          usageDate = DateTime.parse(dateRaw);
                        } catch (_) {}
                      } else if (dateRaw is Timestamp) {
                        usageDate = dateRaw.toDate();
                      } else if (dateRaw is DateTime) {
                        usageDate = dateRaw;
                      }

                      if (usageDate != null &&
                          !usageDate.isBefore(startOfMonth) &&
                          usageDate.isBefore(endOfMonth)) {
                        monthQuantity += quantity;
                      }

                      final status = isDelivery
                          ? (usage['status'] ?? 'released').toString()
                          : (usage['status'] ?? usage['syncStatus'] ?? '')
                              .toString();

                      final unit = (usage['unit'] ?? '').toString();
                      final unitPrice = unitPriceByMaterial[name];
                      final double? totalCost =
                          unitPrice != null ? unitPrice * quantity : null;

                      final entry = _MaterialUsageEntry(
                        materialName: name,
                        quantity: quantity,
                        unit: unit,
                        status: status,
                        projectId: (usage['projectId'] ?? '').toString(),
                        reportId: isDelivery
                            ? 'delivery:${(usage['id'] ?? '').toString()}'
                            : (usage['reportId'] ?? '').toString(),
                        date: usageDate,
                        unitPrice: unitPrice,
                        totalCost: totalCost,
                      );

                      usageEntries.add(entry);

                      if (usageDate != null &&
                          !usageDate.isBefore(startOfMonth) &&
                          usageDate.isBefore(endOfMonth)) {
                        monthUsageEntries.add(entry);
                      }
                    }

                    final Map<String, List<_MaterialUsageEntry>> usageByProject = {};
                    for (final e in usageEntries) {
                      usageByProject.putIfAbsent(e.projectId, () => []).add(e);
                    }

                    final List<_SiteDistributionSummary> siteSummaries = [];
                    usageByProject.forEach((projectId, entries) {
                      double siteTotalQuantity = 0;
                      double siteTotalCost = 0;
                      final Set<String> siteMaterials = {};
                      DateTime? lastUsageDate;

                      for (final entry in entries) {
                        siteTotalQuantity += entry.quantity;
                        siteTotalCost += entry.totalCost ?? 0.0;
                        siteMaterials.add(entry.materialName);
                        if (entry.date != null) {
                          if (lastUsageDate == null || entry.date!.isAfter(lastUsageDate)) {
                            lastUsageDate = entry.date;
                          }
                        }
                      }

                      siteSummaries.add(
                        _SiteDistributionSummary(
                          projectId: projectId,
                          siteLabel: siteLabel(projectId),
                          materialsCount: siteMaterials.length,
                          totalQuantity: siteTotalQuantity,
                          totalCost: siteTotalCost,
                          lastUsageDate: lastUsageDate,
                        ),
                      );
                    });

                    siteSummaries.sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));

                    return AdminGlassScaffold(
                      title: 'Material & Inventory Monitoring',
                      actions: [
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseService.instance.firestore
                              .collectionGroup('material_requests')
                              .where(
                                'status',
                                isEqualTo: AppConstants.materialRequestPending,
                              )
                              .snapshots(),
                          builder: (context, snapshot) {
                            return IconButton(
                              icon: const Icon(Icons.notifications_none),
                              tooltip: 'Material requests',
                              onPressed: _showMaterialRequestsBottomSheet,
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Assign/budget material',
                          icon: const Icon(Icons.playlist_add_rounded),
                          onPressed: _showAddAllocationDialog,
                        ),
                        IconButton(
                          tooltip: 'Sync inventory to site budget',
                          icon: const Icon(Icons.sync_alt_rounded),
                          onPressed: _showSyncInventoryToBudgetDialog,
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_outline),
                          onPressed: () => context.push(RouteNames.profile),
                        ),
                      ],
                      showSidebar: widget.showSidebar,
                sidebarMode: widget.sidebarMode,
                      bottomNavigationBar: widget.showBottomNav
                          ? const AdminBottomNavBar(
                              current: AdminNavItem.materialInventory,
                            )
                          : null,
                      child: GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(14),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
              Text(
                'Select project',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  final typedProjectDocs = projectDocs
                      .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

                  final options = typedProjectDocs
                      .map((d) {
                        final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{};
                        return <String, String>{
                          'id': d.id,
                          'name': (data['name'] ?? d.id).toString(),
                        };
                      })
                      .toList();

                  options.sort((a, b) =>
                      (a['name'] ?? '').compareTo((b['name'] ?? '')));
                  _projectOptions = options;

                  if (typedProjectDocs.isEmpty) {
                    return const Text(
                      'No projects found.',
                      style: TextStyle(color: Colors.black54),
                    );
                  }

                  final currentSelected = selectedProjectId;
                  final isCurrentValid = currentSelected != null &&
                      typedProjectDocs.any((d) => d.id == currentSelected);

                  final effectiveId =
                      isCurrentValid ? currentSelected : typedProjectDocs.first.id;

                  if (!isCurrentValid) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final first = typedProjectDocs.first;
                      final data = (first.data() as Map?)?.cast<String, dynamic>() ??
                          <String, dynamic>{};
                      setState(() {
                        _selectedProjectId = first.id;
                        _selectedProjectName = (data['name'] ?? '').toString();
                      });
                    });
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: effectiveId,
                    items: [
                      for (final d in typedProjectDocs)
                        () {
                          final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                              <String, dynamic>{};
                          final name = (data['name'] ?? d.id).toString();
                          return DropdownMenuItem<String>(
                            value: d.id,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          );
                        }(),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final doc = typedProjectDocs.firstWhere(
                        (e) => e.id == v,
                        orElse: () => typedProjectDocs.first,
                      );
                      final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
                          <String, dynamic>{};
                      setState(() {
                        _selectedProjectId = v;
                        _selectedProjectName = (data['name'] ?? '').toString();
                      });
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;

                  Widget buildStatCard({
                    required IconData icon,
                    required Color iconColor,
                    required String label,
                    required String value,
                    VoidCallback? onTap,
                  }) {
                    final card = AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: iconColor.withAlpha(24),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  icon,
                                  color: iconColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            value,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryBlue,
                                ),
                          ),
                        ],
                      ),
                    );

                    if (onTap == null) return card;

                    return GestureDetector(
                      onTap: onTap,
                      child: card,
                    );
                  }

                  final totalStockCard = buildStatCard(
                    icon: Icons.inventory_2_outlined,
                    iconColor: AppTheme.deepBlue,
                    label: 'Total material in stock',
                    value: totalStock.toStringAsFixed(1),
                    onTap: inventoryItems.isEmpty
                        ? null
                        : () => _showFullInventoryTable(
                              context,
                              inventoryItems,
                            ),
                  );

                  final usedThisMonthCard = buildStatCard(
                    icon: Icons.stacked_bar_chart,
                    iconColor: AppTheme.accentYellow,
                    label: 'Material used this month',
                    value: monthQuantity.toStringAsFixed(1),
                    onTap: monthUsageEntries.isEmpty
                        ? null
                        : () => _showFullMaterialUsageTable(
                              context,
                              'This month',
                              monthUsageEntries,
                            ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        totalStockCard,
                        const SizedBox(height: 12),
                        usedThisMonthCard,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: totalStockCard),
                      const SizedBox(width: 12),
                      Expanded(child: usedThisMonthCard),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Distribution per site',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              if (siteSummaries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Top site by material usage: '
                    '${siteSummaries.first.siteLabel} '
                    '(${siteSummaries.first.totalQuantity.toStringAsFixed(1)} units)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                ),
              if (siteSummaries.isEmpty)
                Text(
                  'No material distribution recorded yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                )
              else
                for (final summary in siteSummaries) ...[
                  Text(
                    'Site: ${summary.siteLabel}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _showFullSiteDistributionTable(
                      context,
                      siteSummaries,
                    ),
                    child: GlassDataTableTheme(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                columnSpacing: 16,
                                columns: const [
                                  DataColumn(label: Text('Materials')),
                                  DataColumn(label: Text('Total qty used')),
                                  DataColumn(label: Text('Total cost')),
                                  DataColumn(label: Text('Last usage')),
                                ],
                                rows: [
                                  _buildSiteDistributionRow(context, summary),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 16),
              Text(
                'Material usage details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              if (usageByProject.isEmpty)
                Text(
                  'No material usage records yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              if (usageByProject.isNotEmpty) const SizedBox(height: 4),
              for (final entry in usageByProject.entries) ...[
                Text(
                  'Site: ${siteLabel(entry.key)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showFullMaterialUsageTable(
                    context,
                    siteLabel(entry.key),
                    entry.value,
                  ),
                  child: GlassDataTableTheme(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: DataTable(
                              columnSpacing: 16,
                              columns: const [
                                DataColumn(label: Text('Material')),
                                DataColumn(label: Text('Qty')),
                                DataColumn(label: Text('Unit')),
                                DataColumn(label: Text('Unit price')),
                                DataColumn(label: Text('Cost')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Report ID')),
                                DataColumn(label: Text('Date')),
                              ],
                              rows: [
                                for (final usage in entry.value)
                                  _buildMaterialUsageRow(context, usage),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _showFullSiteDistributionTable(
    BuildContext context,
    List<_SiteDistributionSummary> siteSummaries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.92,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Distribution per site',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final verticalController = ScrollController();
                        return Scrollbar(
                          thumbVisibility: true,
                          controller: verticalController,
                          child: SingleChildScrollView(
                            controller: verticalController,
                            scrollDirection: Axis.vertical,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final summary in siteSummaries) ...[
                                  Text(
                                    'Site: ${summary.siteLabel}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  GlassDataTableTheme(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: constraints.maxWidth,
                                        ),
                                        child: DataTable(
                                          columnSpacing: 16,
                                          headingTextStyle: Theme.of(sheetContext)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.mediumGray,
                                              ),
                                          columns: const [
                                            DataColumn(label: Text('Materials')),
                                            DataColumn(label: Text('Total qty used')),
                                            DataColumn(label: Text('Total cost')),
                                            DataColumn(label: Text('Last usage')),
                                          ],
                                          rows: [
                                            _buildSiteDistributionRow(
                                              sheetContext,
                                              summary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
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
          ),
        );
      },
    );
  }

  void _showFullInventoryTable(
    BuildContext context,
    List<Map<String, dynamic>> inventoryItems,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Inventory items',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final verticalController = ScrollController();
                        return Scrollbar(
                          thumbVisibility: true,
                          controller: verticalController,
                          child: SingleChildScrollView(
                            controller: verticalController,
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: DataTable(
                                  columnSpacing: 16,
                                  headingTextStyle: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.mediumGray,
                                      ),
                                  columns: const [
                                    DataColumn(label: Text('Material')),
                                    DataColumn(label: Text('Stock')),
                                    DataColumn(label: Text('Unit')),
                                    DataColumn(label: Text('Unit price')),
                                  ],
                                  rows: [
                                    for (final item in inventoryItems)
                                      () {
                                        final name =
                                            (item['materialName'] ?? '')
                                                .toString();
                                        final unit =
                                            (item['unit'] ?? '').toString();
                                        final stockRaw = item['stock'];
                                        final stock = stockRaw is num
                                            ? stockRaw.toDouble()
                                            : (double.tryParse(
                                                    stockRaw?.toString() ??
                                                        '0') ??
                                                0.0);

                                        final unitPriceRaw =
                                            item['unitPrice'] ?? item['price'];
                                        final unitPrice = unitPriceRaw is num
                                            ? unitPriceRaw.toDouble()
                                            : double.tryParse(
                                                unitPriceRaw?.toString() ??
                                                    '');

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: constraints.maxWidth * 0.38,
                                                child: Text(
                                                  name.isEmpty ? '-' : name,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(stock.toStringAsFixed(1)),
                                            ),
                                            DataCell(
                                              Text(unit.isEmpty ? '-' : unit),
                                            ),
                                            DataCell(
                                              Text(unitPrice == null
                                                  ? '-'
                                                  : unitPrice.toStringAsFixed(2)),
                                            ),
                                          ],
                                        );
                                      }(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFullMaterialUsageTable(
    BuildContext context,
    String siteId,
    List<_MaterialUsageEntry> usages,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.92,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Material usage – Site: $siteId',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final verticalController = ScrollController();
                        return Scrollbar(
                          thumbVisibility: true,
                          controller: verticalController,
                          child: SingleChildScrollView(
                            controller: verticalController,
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: DataTable(
                                  columnSpacing: 16,
                                  headingTextStyle: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.mediumGray,
                                      ),
                                  columns: const [
                                    DataColumn(label: Text('Material')),
                                    DataColumn(label: Text('Qty')),
                                    DataColumn(label: Text('Unit')),
                                    DataColumn(label: Text('Unit price')),
                                    DataColumn(label: Text('Cost')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Report ID')),
                                    DataColumn(label: Text('Date')),
                                  ],
                                  rows: [
                                    for (final usage in usages)
                                      _buildMaterialUsageRow(sheetContext, usage),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMaterialRequestsBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (sheetContext) {
        final pendingStream = FirebaseService.instance.firestore
            .collectionGroup('material_requests')
            .where(
              'status',
              isEqualTo: AppConstants.materialRequestPending,
            )
            .snapshots();

        final releasedStream = FirebaseService.instance.firestore
            .collectionGroup('material_requests')
            .where(
              'status',
              isEqualTo: AppConstants.materialRequestApproved,
            )
            .snapshots();

        return DefaultTabController(
          length: 2,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Material(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  child: SizedBox(
                    height: MediaQuery.of(sheetContext).size.height * 0.82,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Material requests',
                                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                            ),
                            child: TabBar(
                              dividerHeight: 0,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              labelColor: AppTheme.deepBlue,
                              unselectedLabelColor: AppTheme.mediumGray,
                              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                              tabs: const [
                                Tab(text: 'Pending'),
                                Tab(text: 'Released'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildMaterialRequestList(
                                pendingStream,
                                emptyMessage: 'No pending material requests.',
                              ),
                              _buildMaterialRequestList(
                                releasedStream,
                                emptyMessage: 'No released material requests yet.',
                                showReleasedLabel: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMaterialRequestList(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream, {
    required String emptyMessage,
    bool showReleasedLabel = false,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load material requests: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.errorRed),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.mediumGray),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final subject =
                (data['subject'] ?? 'Material request').toString();
            final details = (data['details'] ?? '').toString();
            final projectId =
                (data['projectId'] ?? 'Unknown site').toString();
            final projectName = (data['projectName'] ?? '').toString();
            final createdBy = (data['createdBy'] ?? '').toString();
            final createdByName =
                (data['createdByName'] ?? '').toString();

            final siteLabel = projectName.isNotEmpty ? projectName : projectId;

            final managerText =
                (createdByName.isNotEmpty ? createdByName : createdBy).trim();

            return InkWell(
              onTap: () => _showMaterialRequestActionDialog(doc),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subject,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        if (showReleasedLabel)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.softGreen.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.softGreen.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              'Released',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.softGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        details,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.mediumGray),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            siteLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 16, color: AppTheme.mediumGray),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Site manager: ${managerText.isEmpty ? 'Unknown' : managerText}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (projectName.isNotEmpty && projectName != projectId) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Project ID: $projectId',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Open to approve / reject',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.deepBlue,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.mediumGray),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMaterialRequestActionDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final subject = (data['subject'] ?? 'Material request').toString();
    final details = (data['details'] ?? '').toString();
    final projectId = (data['projectId'] ?? 'Unknown site').toString();
    final projectName = (data['projectName'] ?? '').toString();
    final createdBy = (data['createdBy'] ?? '').toString();
    final createdByName = (data['createdByName'] ?? '').toString();
    final allocationId = (data['allocationId'] ?? '').toString().trim();

    final siteLabel = projectName.isNotEmpty ? projectName : projectId;
    final managerDisplay =
        (createdByName.isNotEmpty ? createdByName : createdBy).trim();

    Map<String, dynamic>? allocationData;
    if (projectId.isNotEmpty && projectId != 'Unknown site' && allocationId.isNotEmpty) {
      try {
        final allocSnap = await FirebaseService.instance
            .materialAllocationsCollection(projectId)
            .doc(allocationId)
            .get();
        if (allocSnap.exists) {
          allocationData = (allocSnap.data() as Map?)?.cast<String, dynamic>();
        }
      } catch (_) {
        allocationData = null;
      }
    }

    final inventoryItemsSnap = await FirebaseService.instance
        .materialInventoryCollection(projectId)
        .orderBy('materialName')
        .limit(500)
        .get();

    final inventoryItems = inventoryItemsSnap.docs
        .map(
          (d) => <String, dynamic>{
            ...(d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
            'id': d.id,
          },
        )
        .toList();

    if (!mounted) return;

    final commentController = TextEditingController();
    final quantityController = TextEditingController();
    String? selectedInventoryId;
    Map<String, dynamic>? selectedInventory;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            double? availableStock;
            double? unitPrice;
            String unitLabel = '';

            double? allocationUnitPrice;
            if (allocationData != null) {
              final raw = allocationData['unitPrice'] ?? allocationData['price'];
              if (raw is num) {
                allocationUnitPrice = raw.toDouble();
              } else if (raw is String) {
                final cleaned = raw.replaceAll(',', '').replaceAll('₱', '').trim();
                allocationUnitPrice = double.tryParse(cleaned);
              }
            }

            if (selectedInventory != null) {
              final stockRaw = selectedInventory!['stock'];
              if (stockRaw is num) {
                availableStock = stockRaw.toDouble();
              } else {
                availableStock =
                    double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;
              }

              final priceRaw =
                  selectedInventory!['unitPrice'] ?? selectedInventory!['price'];
              if (priceRaw is num) {
                unitPrice = priceRaw.toDouble();
              } else if (priceRaw is String) {
                final cleaned = priceRaw
                    .replaceAll(',', '')
                    .replaceAll('₱', '')
                    .trim();
                unitPrice = double.tryParse(cleaned);
              }

              unitLabel = (selectedInventory!['unit'] ?? '').toString();
            }

            final chosenUnitPrice = (allocationUnitPrice != null && allocationUnitPrice > 0)
                ? allocationUnitPrice
                : unitPrice;

            double? calculatedAmount;
            final quantityText = quantityController.text.trim();
            final quantity = double.tryParse(
              quantityText.isEmpty ? '0' : quantityText.replaceAll(',', ''),
            );
            if (quantity != null &&
                quantity > 0 &&
                chosenUnitPrice != null &&
                chosenUnitPrice > 0) {
              calculatedAmount = chosenUnitPrice * quantity;
            }

            final requestedMaterial = (data['materialName'] ?? subject).toString();

            Future<void> rejectAction() async {
              final comment = commentController.text.trim();
              Navigator.of(dialogContext).pop();
              await _updateMaterialRequestStatus(
                doc,
                AppConstants.materialRequestRejected,
                comment,
              );
            }

            Future<void> approveAction() async {
              if (inventoryItems.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No inventory materials available. Add materials in inventory first.',
                    ),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              if (selectedInventoryId == null ||
                  selectedInventory == null ||
                  selectedInventory!.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      (selectedInventoryId ?? '').startsWith('manual:')
                          ? 'Selected material is not in inventory. Add it to inventory first, then release.'
                          : 'Please select a material from inventory to release.',
                    ),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              final quantityText =
                  quantityController.text.trim().replaceAll(',', '');
              final releaseQuantity = double.tryParse(quantityText);
              if (releaseQuantity == null || releaseQuantity <= 0) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid quantity to release.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              final priceRaw =
                  selectedInventory!['unitPrice'] ?? selectedInventory!['price'];
              double? unitPriceForExpense;
              if (allocationUnitPrice != null && allocationUnitPrice > 0) {
                unitPriceForExpense = allocationUnitPrice;
              } else {
                if (priceRaw is num) {
                  unitPriceForExpense = priceRaw.toDouble();
                } else if (priceRaw is String) {
                  final cleaned = priceRaw
                      .replaceAll(',', '')
                      .replaceAll('₱', '')
                      .trim();
                  unitPriceForExpense = double.tryParse(cleaned);
                }
              }
              if (unitPriceForExpense == null || unitPriceForExpense <= 0) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Selected material has no valid price per unit. Set a unit price in assigned materials or inventory first.',
                    ),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              final expenseAmount = unitPriceForExpense * releaseQuantity;
              final comment = commentController.text.trim();

              Navigator.of(dialogContext).pop();

              await _updateMaterialRequestStatus(
                doc,
                AppConstants.materialRequestApproved,
                comment,
                inventoryItemId: selectedInventoryId,
                releasedQuantity: releaseQuantity,
                expenseAmount: expenseAmount,
                unitPrice: unitPriceForExpense,
              );
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Material(
                    color: Colors.white,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 820;

                        final header = Container(
                          padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                const Color(0xFFF5F6FA),
                              ],
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Material Release Request',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Site: $siteLabel | Project ID: $projectId',
                                      maxLines: 2,
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
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        );

                        Widget infoRow(IconData icon, String label, String value) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 18, color: AppTheme.mediumGray),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppTheme.mediumGray),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      value,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        final leftPanel = Container(
                          color: const Color(0xFFF5F6FA),
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Site Details',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    infoRow(
                                      Icons.person_outline,
                                      'Site Manager',
                                      managerDisplay.isEmpty ? 'Unknown' : managerDisplay,
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      height: 1,
                                      color: Colors.black.withValues(alpha: 0.06),
                                    ),
                                    const SizedBox(height: 12),
                                    infoRow(
                                      Icons.inventory_2_outlined,
                                      'Requested Material',
                                      requestedMaterial,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Status',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3CD),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Icon(
                                        Icons.schedule,
                                        size: 16,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Pending Approval',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (details.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  details,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              ],
                            ],
                          ),
                        );

                        final formPanel = Container(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Material Release',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: selectedInventoryId,
                                items: [
                                  for (final item in inventoryItems)
                                    () {
                                      final id = (item['id'] ?? '').toString();
                                      final name =
                                          (item['materialName'] ?? 'Material').toString();
                                      final unit = (item['unit'] ?? '').toString();
                                      final stockRaw = item['stock'];
                                      double stock;
                                      if (stockRaw is num) {
                                        stock = stockRaw.toDouble();
                                      } else {
                                        stock =
                                            double.tryParse(stockRaw?.toString() ?? '0') ??
                                                0.0;
                                      }
                                      return DropdownMenuItem<String>(
                                        value: id,
                                        child: Text(
                                          '$name (Stock: ${stock.toStringAsFixed(1)} $unit)',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }(),
                                  ...() {
                                    final inventoryNames = inventoryItems
                                        .map((i) => (i['materialName'] ?? '')
                                            .toString()
                                            .trim()
                                            .toLowerCase())
                                        .where((n) => n.isNotEmpty)
                                        .toSet();

                                    final extra = _fallbackMaterials
                                        .where(
                                          (m) =>
                                              !inventoryNames.contains(m.toLowerCase()),
                                        )
                                        .toList();
                                    extra.sort(
                                      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                                    );

                                    return extra
                                        .map(
                                          (name) => DropdownMenuItem<String>(
                                            value: 'manual:$name',
                                            child: Text(
                                              '$name (Not in inventory)',
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(color: AppTheme.mediumGray),
                                            ),
                                          ),
                                        )
                                        .toList();
                                  }(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Material to Release',
                                ),
                                onChanged: (value) {
                                  setStateDialog(() {
                                    selectedInventoryId = value;
                                    if (value != null && value.startsWith('manual:')) {
                                      selectedInventory = null;
                                    } else {
                                      selectedInventory = inventoryItems.firstWhere(
                                        (item) =>
                                            (item['id'] ?? '').toString() == value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 10),
                              if (availableStock != null && unitLabel.isNotEmpty)
                                Text(
                                  'Available stock: ${availableStock.toStringAsFixed(1)} $unitLabel',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              if (unitPrice != null)
                                Text(
                                  'Unit price: ₱${unitPrice.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              if (calculatedAmount != null && quantity != null && quantity > 0)
                                Text(
                                  'This release cost: ₱${calculatedAmount.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: commentController,
                                decoration: const InputDecoration(
                                  labelText: 'Comment / Reply',
                                ),
                                maxLines: 3,
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: rejectAction,
                                    child: const Text('Reject'),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton(
                                    onPressed: approveAction,
                                    child: const Text('Approve & Release'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );

                        final body = isNarrow
                            ? SingleChildScrollView(
                                child: Column(
                                  children: [
                                    leftPanel,
                                    const Divider(height: 1),
                                    SizedBox(height: 520, child: formPanel),
                                  ],
                                ),
                              )
                            : SizedBox(
                                height: 520,
                                child: Row(
                                  children: [
                                    SizedBox(width: 320, child: leftPanel),
                                    Container(
                                      width: 1,
                                      color: Colors.black.withValues(alpha: 0.06),
                                    ),
                                    Expanded(child: formPanel),
                                  ],
                                ),
                              );

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            header,
                            body,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateMaterialRequestStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String status,
    String comment, {
    String? inventoryItemId,
    double? releasedQuantity,
    double? expenseAmount,
    double? unitPrice,
  }) async {
    try {
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final data = doc.data();
      final projectId = (data['projectId'] ?? '').toString();
      final subject = (data['subject'] ?? 'Material request').toString();
      final allocationId = (data['allocationId'] ?? '').toString().trim();

      String? inventoryMaterialName;
      String? inventoryUnit;

      if (status == AppConstants.materialRequestApproved &&
          projectId.isNotEmpty &&
          inventoryItemId != null &&
          inventoryItemId.isNotEmpty &&
          releasedQuantity != null &&
          releasedQuantity > 0) {
        await FirebaseService.instance.firestore.runTransaction((tx) async {
          if (allocationId.isNotEmpty) {
            final allocationRef = FirebaseService.instance
                .materialAllocationsCollection(projectId)
                .doc(allocationId);
            final allocSnap = await tx.get(allocationRef);
            if (!allocSnap.exists) {
              throw Exception('Assigned material allocation not found. Ask admin to re-assign/budget materials.');
            }
            final allocData = (allocSnap.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

            double readNum(dynamic v) {
              if (v is num) return v.toDouble();
              return double.tryParse((v ?? '').toString().replaceAll(',', '')) ?? 0.0;
            }

            final budget = readNum(allocData['budgetQuantity']);
            final used = readNum(allocData['usedQuantity']);
            final remaining = (budget - used).clamp(0.0, double.infinity);
            if (releasedQuantity > remaining) {
              throw Exception('Release exceeds remaining allocation. Remaining: ${remaining.toStringAsFixed(1)}');
            }

            tx.update(allocationRef, {
              'usedQuantity': used + releasedQuantity,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          final inventoryRef = FirebaseService.instance
              .materialInventoryCollection(projectId)
              .doc(inventoryItemId);
          final invSnap = await tx.get(inventoryRef);
          if (!invSnap.exists) {
            throw Exception('Selected inventory item not found.');
          }

          final invData = (invSnap.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};

          inventoryMaterialName =
              (invData['materialName'] ?? subject).toString().trim();
          inventoryUnit = (invData['unit'] ?? '').toString().trim();
        });
      }

      await doc.reference.update({
        'status': status,
        'adminComment': comment,
        'handledAt': nowIso,
        if (status == AppConstants.materialRequestApproved) 'approvedAt': nowIso,
        if (status == AppConstants.materialRequestApproved)
          'release': {
            'inventoryItemId': inventoryItemId,
            'releasedQuantity': releasedQuantity,
            'expenseAmount': expenseAmount,
            'unitPrice': unitPrice,
            'materialName': inventoryMaterialName,
            'unit': inventoryUnit,
          },
      });

      if (status == AppConstants.materialRequestApproved &&
          projectId.isNotEmpty &&
          projectId != 'Unknown site' &&
          expenseAmount != null &&
          expenseAmount > 0) {
        await FirebaseService.instance.disbursementsCollection.add({
          'projectId': projectId,
          'amount': expenseAmount,
          'type': 'material_request',
          'materialRequestId': doc.id,
          'inventoryItemId': inventoryItemId,
          'releasedQuantity': releasedQuantity,
          'unitPrice': unitPrice,
          'subject': subject,
          'createdAt': nowIso,
        });
      }

      if (status == AppConstants.materialRequestApproved &&
          projectId.isNotEmpty &&
          projectId != 'Unknown site' &&
          inventoryItemId != null &&
          releasedQuantity != null &&
          releasedQuantity > 0 &&
          expenseAmount != null &&
          expenseAmount > 0) {
        final deliveryId = 'delivery_${doc.id}_${now.millisecondsSinceEpoch}';

        await FirebaseService.instance
            .deliveriesCollection(projectId)
            .doc(deliveryId)
            .set({
          'id': deliveryId,
          'type': 'material_request_release',
          'projectId': projectId,
          'materialRequestId': doc.id,
          'materialName': (inventoryMaterialName ?? subject).toString(),
          'inventoryItemId': inventoryItemId,
          'quantity': releasedQuantity,
          'unit': (inventoryUnit ?? '').toString(),
          'status': 'released',
          'approvedAt': nowIso,
          'createdAt': nowIso,
        });

        await doc.reference.update({'deliveryId': deliveryId});

        final dayKey =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final reportId = 'admin_release_${projectId}_$dayKey';
        final usageId = 'mr_${doc.id}_${now.millisecondsSinceEpoch.toString()}';

        final usage = <String, dynamic>{
          'id': usageId,
          'materialName': (inventoryMaterialName ?? subject).toString(),
          'quantity': releasedQuantity,
          'unit': (inventoryUnit ?? '').toString(),
          'projectId': projectId,
          'reportId': reportId,
          'status': 'released',
          'syncStatus': AppConstants.syncStatusCompleted,
          'materialRequestId': doc.id,
          'inventoryItemId': inventoryItemId,
          'date': nowIso,
          'createdAt': nowIso,
        };

        await FirebaseService.instance
            .materialUsageCollection(projectId, reportId)
            .doc(usageId)
            .set(usage);
      }

      final logDetails = <String, dynamic>{
        'requestId': doc.id,
        'subject': subject,
        'status': status,
      };
      if (inventoryItemId != null) {
        logDetails['inventoryItemId'] = inventoryItemId;
      }
      if (releasedQuantity != null) {
        logDetails['releasedQuantity'] = releasedQuantity;
      }
      if (expenseAmount != null) {
        logDetails['expenseAmount'] = expenseAmount;
      }
      if (unitPrice != null) {
        logDetails['unitPrice'] = unitPrice;
      }

      await AuditLogService.instance.logAction(
        action: status == AppConstants.materialRequestApproved
            ? 'material_request_approved'
            : 'material_request_rejected',
        projectId: projectId,
        details: logDetails,
      );

      if (!mounted) return;

      if (status == AppConstants.materialRequestApproved) {
        setState(() {});
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AppConstants.materialRequestApproved
                ? 'Material request released and recorded as project expense'
                : 'Material request rejected',
          ),
          backgroundColor: status == AppConstants.materialRequestApproved
              ? AppTheme.softGreen
              : AppTheme.errorRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update request: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  Future<void> _showAddAllocationDialog() async {
    final projectId = _selectedProjectId;
    if (projectId == null || projectId.isEmpty) return;

    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final unitPriceController = TextEditingController();
    final budgetController = TextEditingController();

    final rootMessenger = ScaffoldMessenger.of(context);

    final options = _allProjectOptions;
    String selectedProjectId = projectId;
    String? selectedProjectName = _selectedProjectName;

    String nameForProject(String id) {
      for (final p in options) {
        if ((p['id'] ?? '') == id) return (p['name'] ?? id).toString();
      }
      return id;
    }

    if (options.isNotEmpty) {
      final ok = options.any((p) => (p['id'] ?? '') == selectedProjectId);
      if (!ok) {
        selectedProjectId =
            (options.first['id'] ?? selectedProjectId).toString();
        selectedProjectName = nameForProject(selectedProjectId);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            bool isSaving = false;

            Future<void> save() async {
              if (isSaving) return;
              setStateDialog(() => isSaving = true);

              final navigator = Navigator.of(dialogContext);
              final name = nameController.text.trim();
              final unit = unitController.text.trim();
              final unitPrice = double.tryParse(
                unitPriceController.text.trim().replaceAll(',', ''),
              );
              final budget = double.tryParse(
                budgetController.text.trim().replaceAll(',', ''),
              );

              if (name.isEmpty || unit.isEmpty || budget == null || budget <= 0) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter material name, unit, and a valid budget quantity.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              try {
                final nowIso = DateTime.now().toIso8601String();
                final docRef = FirebaseService.instance
                    .materialAllocationsCollection(selectedProjectId)
                    .doc();
                final payload = <String, dynamic>{
                  'id': docRef.id,
                  'materialName': name,
                  'unit': unit,
                  'budgetQuantity': budget,
                  'requiredQuantity': budget,
                  'usedQuantity': 0,
                  if (unitPrice != null && unitPrice >= 0) 'unitPrice': unitPrice,
                  'projectId': selectedProjectId,
                  'projectName':
                      (selectedProjectName ?? nameForProject(selectedProjectId)),
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                try {
                  await docRef.set(payload);

                  try {
                    final invQuery = await FirebaseService.instance
                        .materialInventoryCollection(selectedProjectId)
                        .where('materialName', isEqualTo: name)
                        .where('unit', isEqualTo: unit)
                        .limit(1)
                        .get();

                    if (invQuery.docs.isEmpty) {
                      final invRef = FirebaseService.instance
                          .materialInventoryCollection(selectedProjectId)
                          .doc();

                      await invRef.set({
                        'id': invRef.id,
                        'materialName': name,
                        'unit': unit,
                        'stock': budget,
                        if (unitPrice != null && unitPrice >= 0)
                          'unitPrice': unitPrice,
                        'projectId': selectedProjectId,
                        'projectName':
                            (selectedProjectName ?? nameForProject(selectedProjectId)),
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    }
                  } catch (_) {
                    // ignore
                  }
                } catch (e) {
                  if (_isFirestoreUnreachableError(e)) {
                    final queuedPayload = <String, dynamic>{
                      ...payload,
                      'createdAt': nowIso,
                      'updatedAt': nowIso,
                    };
                    await SyncService.instance.addToSyncQueue(
                      'material_allocation_upsert',
                      <String, dynamic>{
                        'projectId': selectedProjectId,
                        'docId': docRef.id,
                        'payload': queuedPayload,
                      },
                    );
                  } else {
                    rethrow;
                  }
                }

                navigator.pop();
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Material assigned/budgeted for this project.'),
                    backgroundColor: AppTheme.softGreen,
                  ),
                );
              } catch (e) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to assign/budget material: $e'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Assign/Budget Material'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (options.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedProjectId,
                        items: [
                          for (final p in options)
                            DropdownMenuItem<String>(
                              value: (p['id'] ?? '').toString(),
                              child: Text(
                                (p['name'] ?? p['id'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (v) {
                                if (v == null || v.isEmpty) return;
                                setStateDialog(() {
                                  selectedProjectId = v;
                                  selectedProjectName = nameForProject(v);
                                });
                              },
                        decoration: const InputDecoration(
                          labelText: 'Project',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const Text('No projects found.'),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Material name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Unit (e.g. bag, m³)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Unit price (₱)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: budgetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => save(),
                      decoration: const InputDecoration(labelText: 'Budget quantity'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MaterialUsageEntry {
  final String materialName;
  final double quantity;
  final String unit;
  final String status;
  final String projectId;
  final String reportId;
  final DateTime? date;
  final double? unitPrice;
  final double? totalCost;

  _MaterialUsageEntry({
    required this.materialName,
    required this.quantity,
    required this.unit,
    required this.status,
    required this.projectId,
    required this.reportId,
    required this.date,
    this.unitPrice,
    this.totalCost,
  });
}

class _SiteDistributionSummary {
  final String projectId;
  final String siteLabel;
  final int materialsCount;
  final double totalQuantity;
  final double totalCost;
  final DateTime? lastUsageDate;

  _SiteDistributionSummary({
    required this.projectId,
    required this.siteLabel,
    required this.materialsCount,
    required this.totalQuantity,
    required this.totalCost,
    required this.lastUsageDate,
  });
}

DataRow _buildSiteDistributionRow(
  BuildContext context,
  _SiteDistributionSummary summary,
) {
  String dateText = '';
  if (summary.lastUsageDate != null) {
    final d = summary.lastUsageDate!;
    dateText = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  return DataRow(
    cells: [
      DataCell(
        Text(
          summary.materialsCount.toString(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          summary.totalQuantity.toStringAsFixed(1),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          summary.totalCost.toStringAsFixed(2),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          dateText,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

DataRow _buildMaterialUsageRow(BuildContext context, _MaterialUsageEntry entry) {
  String dateText = '';
  if (entry.date != null) {
    final d = entry.date!;
    dateText = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  return DataRow(
    cells: [
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            entry.materialName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      DataCell(
        Text(
          entry.quantity.toStringAsFixed(1),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          entry.unit,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          entry.unitPrice == null ? '-' : entry.unitPrice!.toStringAsFixed(2),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          entry.totalCost == null ? '-' : entry.totalCost!.toStringAsFixed(2),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          entry.status,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          entry.reportId,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DataCell(
        Text(
          dateText,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
