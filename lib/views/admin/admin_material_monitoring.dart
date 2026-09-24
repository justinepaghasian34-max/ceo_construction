import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/budget_model.dart';
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
  State<AdminMaterialMonitoring> createState() =>
      _AdminMaterialMonitoringState();
}

class _AdminMaterialMonitoringState extends State<AdminMaterialMonitoring>
    with SingleTickerProviderStateMixin {
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
  String _requestPriorityFilter = 'all';

  static double _toMoney(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(',', '').replaceAll('₱', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  static String _peso(double value) =>
      '${AppConstants.currencySymbol}${value.toStringAsFixed(2)}';

  DateTime _parseRequestDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _prettyDate(DateTime? date) {
    if (date == null) return '—';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _qtyWithUnit(double qty, [String unit = '']) {
    final amount = qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);
    final trimmed = unit.trim();
    return trimmed.isEmpty ? amount : '$amount $trimmed';
  }

  String _projectIdFromSnapshot(DocumentSnapshot d) {
    final data =
        (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final fromField = (data['projectId'] ?? '').toString().trim();
    if (fromField.isNotEmpty) return fromField;
    final segments = d.reference.path.split('/');
    if (segments.length >= 2 && segments.first == 'projects') {
      return segments[1];
    }
    return '';
  }

  String _projectNameFor(String projectId) {
    if (projectId.isEmpty) return 'This project';
    if (projectId == _selectedProjectId &&
        (_selectedProjectName ?? '').trim().isNotEmpty) {
      return _selectedProjectName!.trim();
    }
    for (final p in _allProjectOptions) {
      if ((p['id'] ?? '') == projectId) {
        final name = (p['name'] ?? '').trim();
        if (name.isNotEmpty) return name;
      }
    }
    return projectId;
  }

  Widget _sectionHeading(
    BuildContext context, {
    required String title,
    String? subtitle,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String rawStatus) {
    final status = rawStatus.trim().toLowerCase();
    late final Color color;
    late final String label;
    if (status == 'used' || status == 'completed') {
      color = AppTheme.softGreen;
      label = 'Used';
    } else if (status == 'released' || status == 'approved') {
      color = AppTheme.deepBlue;
      label = 'Released';
    } else if (status.contains('sync')) {
      color = AppTheme.warningOrange;
      label = 'Syncing';
    } else if (status.isEmpty) {
      color = AppTheme.mediumGray;
      label = 'Logged';
    } else {
      color = AppTheme.mediumGray;
      label = rawStatus;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _metricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _siteSummaryCard(
    BuildContext context,
    _SiteDistributionSummary summary,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.deepBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppTheme.deepBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary.siteLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metricChip(
                label: 'Materials',
                value: '${summary.materialsCount}',
                color: AppTheme.deepBlue,
              ),
              const SizedBox(width: 8),
              _metricChip(
                label: 'Qty used',
                value: _qtyWithUnit(summary.totalQuantity),
                color: const Color(0xFF0F766E),
              ),
              const SizedBox(width: 8),
              _metricChip(
                label: 'Last used',
                value: summary.lastUsageDate == null
                    ? '—'
                    : _prettyDate(summary.lastUsageDate)
                        .replaceAll(RegExp(r', \d{4}$'), ''),
                color: const Color(0xFFB45309),
              ),
            ],
          ),
          if (summary.totalCost > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Cost ${_peso(summary.totalCost)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _projectStockCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final name = (item['materialName'] ?? 'Material').toString();
    final unit = (item['unit'] ?? '').toString();
    final stock = _toMoney(item['stock']);
    final unitPrice = _toMoney(item['unitPrice'] ?? item['price']);
    final cost = unitPrice > 0 ? unitPrice * stock : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.deepBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppTheme.deepBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showRestockDialog(item),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Restock'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metricChip(
                label: 'In stock',
                value: _qtyWithUnit(stock, unit),
                color: AppTheme.deepBlue,
              ),
              if (unitPrice > 0) ...[
                const SizedBox(width: 8),
                _metricChip(
                  label: 'Unit price',
                  value: _peso(unitPrice),
                  color: const Color(0xFF0F766E),
                ),
              ],
            ],
          ),
          if (cost > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Stock value ${_peso(cost)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRestockDialog(Map<String, dynamic> item) async {
    final projectId = (_selectedProjectId ?? '').trim();
    final itemId = (item['id'] ?? '').toString().trim();
    if (projectId.isEmpty || itemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a project first, then restock that item.'),
        ),
      );
      return;
    }

    final name = (item['materialName'] ?? 'Material').toString();
    final unit = (item['unit'] ?? '').toString();
    final currentStock = _toMoney(item['stock']);
    final qtyController = TextEditingController();
    final noteController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Restock $name'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current stock: ${_qtyWithUnit(currentStock, unit)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: unit.isEmpty
                        ? 'Quantity to add'
                        : 'Quantity to add ($unit)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Purchase / restock note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add to stock'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;
    final qty = _toMoney(qtyController.text);
    if (qty <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a quantity greater than 0.')),
      );
      return;
    }

    try {
      final ref = FirebaseService.instance
          .materialInventoryCollection(projectId)
          .doc(itemId);
      await FirebaseService.instance.firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw Exception('Inventory item not found.');
        }
        final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
        final stock = _toMoney(data['stock']);
        tx.update(ref, {
          'stock': stock + qty,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastRestockAt': FieldValue.serverTimestamp(),
          'lastRestockQty': qty,
          'lastRestockNote': noteController.text.trim(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restocked ${_qtyWithUnit(qty, unit)} of $name on ${_selectedProjectName ?? 'this project'}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restock failed: $e')),
      );
    }
  }

  Widget _usageLineCard(BuildContext context, _MaterialUsageEntry entry) {
    final costText = entry.totalCost != null && entry.totalCost! > 0
        ? _peso(entry.totalCost!)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entry.materialName.isEmpty
                  ? '?'
                  : entry.materialName[0].toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.deepBlue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.materialName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _qtyWithUnit(entry.quantity, entry.unit),
                    if (costText != null) costText,
                    _prettyDate(entry.date),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusChip(entry.status),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.mediumGray,
            ),
      ),
    );
  }

  Future<_ProjectMaterialBudget> _loadProjectMaterialBudget(
    String projectId,
  ) async {
    double remainingFromBudgets = 0;
    double allocatedFromBudgets = 0;
    var hasBudgetDocs = false;

    try {
      final snap = await FirebaseService.instance.budgetsCollection
          .where('projectId', isEqualTo: projectId)
          .get();
      for (final doc in snap.docs) {
        final budget = BudgetModel.fromFirestore(doc);
        final status = budget.status.toLowerCase();
        if (status == 'closed' || status == 'cancelled') continue;
        hasBudgetDocs = true;
        allocatedFromBudgets += budget.allocatedAmount;
        remainingFromBudgets += budget.remaining;
      }
    } catch (_) {}

    double committed = 0;
    try {
      final allocSnap = await FirebaseService.instance
          .materialAllocationsCollection(projectId)
          .get();
      for (final doc in allocSnap.docs) {
        final data =
            (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final qty = _toMoney(data['budgetQuantity'] ?? data['requiredQuantity']);
        final price = _toMoney(data['unitPrice'] ?? data['price']);
        committed += qty * price;
      }
    } catch (_) {}

    if (hasBudgetDocs) {
      return _ProjectMaterialBudget(
        remaining: remainingFromBudgets < 0 ? 0 : remainingFromBudgets,
        allocated: allocatedFromBudgets,
        committed: committed,
        sourceLabel: 'project budget',
      );
    }

    double contract = 0;
    try {
      final proj = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      final data =
          (proj.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      contract = _toMoney(data['contractAmount'] ?? data['approvedBudget']);
    } catch (_) {}

    final remaining = contract - committed;
    return _ProjectMaterialBudget(
      remaining: remaining < 0 ? 0 : remaining,
      allocated: contract,
      committed: committed,
      sourceLabel: 'contract amount',
    );
  }

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
          norm(((d.data() as Map?)?.cast<String, dynamic>() ??
                      const {})['materialName']
                  ?.toString() ??
              ''),
      }..remove('');

      final inventoryItems = <Map<String, dynamic>>[];
      for (final d in invSnap.docs) {
        final data =
            (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
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
            content: Text(
                'All inventory materials are already assigned/budgeted for this project.'),
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
                  norm((it['materialName'] ?? '').toString()):
                      TextEditingController(),
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
                        content: Text(
                            'Enter a valid budget quantity for at least one material.'),
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
                        content: Text(
                            'Added $added materials to site budget (assigned materials).'),
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
                        content: Text(
                            'Saved offline ($added). Will sync to Firestore when online.'),
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
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
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
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
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isSaving ? null : save,
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
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
                    content: Text(
                        'Please select where to save: Inventory and/or Site budget.'),
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
                    content: Text(
                        'Please enter material name, unit, and a valid stock.'),
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
                    if (unitPrice != null && unitPrice >= 0)
                      'unitPrice': unitPrice,
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
                      await HiveService.instance
                          .saveMaterialInventory(docRef.id, queuedPayload);
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
                    if (unitPrice != null && unitPrice >= 0)
                      'unitPrice': unitPrice,
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
                          : (v) => setStateDialog(
                              () => saveToInventory = v ?? false),
                      title: const Text('Save to inventory'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: saveToBudget,
                      onChanged: isSaving
                          ? null
                          : (v) =>
                              setStateDialog(() => saveToBudget = v ?? false),
                      title: const Text(
                          'Save to site budget (Assigned materials)'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration:
                          const InputDecoration(labelText: 'Material name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: 'Unit (e.g. bag, pcs)'),
                    ),
                    const SizedBox(height: 8),
                    if (saveToInventory) ...[
                      TextField(
                        controller: stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Initial stock'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Unit price (₱)'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (saveToBudget) ...[
                      TextField(
                        controller: budgetController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                        decoration:
                            const InputDecoration(labelText: 'Budget quantity'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
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
    final projectStream =
        FirebaseService.instance.projectsCollection.snapshots();

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

        String siteLabel(String projectId) => _projectNameFor(projectId);

        if (_selectedProjectId == null && projectDocs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_selectedProjectId != null) return;
            final d = projectDocs.first;
            final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            setState(() {
              _selectedProjectId = d.id;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          });
        }

        final selectedProjectId = _selectedProjectId;
        final inventoryStream = selectedProjectId == null
            ? Stream<QuerySnapshot>.empty()
            : FirebaseService.instance
                .materialInventoryCollection(selectedProjectId)
                .orderBy('materialName')
                .snapshots();

        final deliveriesStream = selectedProjectId == null
            ? Stream<QuerySnapshot>.empty()
            : FirebaseService.instance
                .deliveriesCollection(selectedProjectId)
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
                    .map((d) => ((d.data() as Map?)?.cast<String, dynamic>() ??
                        <String, dynamic>{})
                      ..['id'] = d.id)
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
                final cleaned =
                    priceRaw.replaceAll(',', '').replaceAll('₱', '').trim();
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
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    .where((d) {
                      final data =
                          (d.data() as Map?)?.cast<String, dynamic>() ??
                              <String, dynamic>{};
                      return (data['type'] ?? '').toString() ==
                          'material_request_release';
                    })
                    .map(
                      (d) => <String, dynamic>{
                        ...(d.data() as Map?)?.cast<String, dynamic>() ??
                            <String, dynamic>{},
                        'id': d.id,
                        'projectId': _projectIdFromSnapshot(d),
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
                            'projectId': _projectIdFromSnapshot(d),
                          },
                        )
                        .where(
                          (row) =>
                              selectedProjectId == null ||
                              (row['projectId'] ?? '').toString() ==
                                  selectedProjectId,
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
                      if (selectedProjectId != null &&
                          (usage['projectId'] ?? '').toString() !=
                              selectedProjectId) {
                        continue;
                      }

                      final isDelivery = (usage['type'] ?? '').toString() ==
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

                    final Map<String, List<_MaterialUsageEntry>>
                        usageByProject = {};
                    for (final e in usageEntries) {
                      usageByProject.putIfAbsent(e.projectId, () => []).add(e);
                    }
                    for (final list in usageByProject.values) {
                      list.sort((a, b) {
                        final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                        return bd.compareTo(ad);
                      });
                    }

                    final isPhone = MediaQuery.of(context).size.width < 720;

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
                            final pending = snapshot.data?.docs ?? const [];
                            final urgentCount = pending.where((d) {
                              final data = d.data();
                              return (data['priority'] ?? '')
                                      .toString()
                                      .toLowerCase() ==
                                  'urgent';
                            }).length;
                            return IconButton(
                              tooltip: urgentCount > 0
                                  ? '$urgentCount urgent request${urgentCount == 1 ? '' : 's'}'
                                  : 'Material requests',
                              onPressed: _showMaterialRequestsBottomSheet,
                              icon: Badge(
                                isLabelVisible: pending.isNotEmpty,
                                label: Text('${pending.length}'),
                                backgroundColor: urgentCount > 0
                                    ? AppTheme.errorRed
                                    : AppTheme.deepBlue,
                                child: Icon(
                                  pending.isEmpty
                                      ? Icons.notifications_none
                                      : Icons.notifications_active_outlined,
                                ),
                              ),
                            );
                          },
                        ),
                        if (!isPhone) ...[
                          IconButton(
                            tooltip: 'Add material to project',
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
                        ] else
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'add':
                                  _showAddAllocationDialog();
                                  break;
                                case 'sync':
                                  _showSyncInventoryToBudgetDialog();
                                  break;
                                case 'profile':
                                  context.push(RouteNames.profile);
                                  break;
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'add',
                                child: Text('Add material to project'),
                              ),
                              PopupMenuItem(
                                value: 'sync',
                                child: Text('Sync inventory to site budget'),
                              ),
                              PopupMenuItem(
                                value: 'profile',
                                child: Text('Profile'),
                              ),
                            ],
                          ),
                      ],
                      floatingActionButton: isPhone && !widget.showBottomNav
                          ? FloatingActionButton.extended(
                              onPressed: _showAddAllocationDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Add material'),
                            )
                          : null,
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
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final typedProjectDocs = projectDocs.cast<
                                      QueryDocumentSnapshot<
                                          Map<String, dynamic>>>();

                                  final options = typedProjectDocs.map((d) {
                                    final data = (d.data() as Map?)
                                            ?.cast<String, dynamic>() ??
                                        <String, dynamic>{};
                                    return <String, String>{
                                      'id': d.id,
                                      'name': (data['name'] ?? d.id).toString(),
                                    };
                                  }).toList();

                                  options.sort((a, b) => (a['name'] ?? '')
                                      .compareTo((b['name'] ?? '')));
                                  _projectOptions = options;

                                  if (typedProjectDocs.isEmpty) {
                                    return const Text(
                                      'No projects found.',
                                      style: TextStyle(color: Colors.black54),
                                    );
                                  }

                                  final currentSelected = selectedProjectId;
                                  final isCurrentValid = currentSelected !=
                                          null &&
                                      typedProjectDocs
                                          .any((d) => d.id == currentSelected);

                                  final effectiveId = isCurrentValid
                                      ? currentSelected
                                      : typedProjectDocs.first.id;

                                  if (!isCurrentValid) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      final first = typedProjectDocs.first;
                                      final data = (first.data() as Map?)
                                              ?.cast<String, dynamic>() ??
                                          <String, dynamic>{};
                                      setState(() {
                                        _selectedProjectId = first.id;
                                        _selectedProjectName =
                                            (data['name'] ?? '').toString();
                                      });
                                    });
                                  }

                                  return DropdownButtonFormField<String>(
                                    initialValue: effectiveId,
                                    items: [
                                      for (final d in typedProjectDocs)
                                        () {
                                          final data = (d.data() as Map?)
                                                  ?.cast<String, dynamic>() ??
                                              <String, dynamic>{};
                                          final name =
                                              (data['name'] ?? d.id).toString();
                                          return DropdownMenuItem<String>(
                                            value: d.id,
                                            child: Text(name,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          );
                                        }(),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      final doc = typedProjectDocs.firstWhere(
                                        (e) => e.id == v,
                                        orElse: () => typedProjectDocs.first,
                                      );
                                      final data = (doc.data() as Map?)
                                              ?.cast<String, dynamic>() ??
                                          <String, dynamic>{};
                                      setState(() {
                                        _selectedProjectId = v;
                                        _selectedProjectName =
                                            (data['name'] ?? '').toString();
                                      });
                                    },
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream: FirebaseService.instance.firestore
                                    .collectionGroup('material_requests')
                                    .where(
                                      'status',
                                      isEqualTo:
                                          AppConstants.materialRequestPending,
                                    )
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  final pending = (snapshot.data?.docs ??
                                          const [])
                                      .where((d) =>
                                          selectedProjectId == null ||
                                          _projectIdFromSnapshot(d) ==
                                              selectedProjectId)
                                      .toList();
                                  if (pending.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final urgent = pending.where((d) {
                                    return (d.data()['priority'] ?? '')
                                            .toString()
                                            .toLowerCase() ==
                                        'urgent';
                                  }).toList();
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Material(
                                      color: urgent.isNotEmpty
                                          ? const Color(0xFFFFF1F2)
                                          : const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap:
                                            _showMaterialRequestsBottomSheet,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Icon(
                                                urgent.isNotEmpty
                                                    ? Icons.priority_high
                                                    : Icons
                                                        .shopping_cart_outlined,
                                                color: urgent.isNotEmpty
                                                    ? AppTheme.errorRed
                                                    : AppTheme.deepBlue,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  urgent.isEmpty
                                                      ? '${pending.length} Resident Engineer request${pending.length == 1 ? '' : 's'} waiting to purchase'
                                                      : '${urgent.length} urgent • ${pending.length} total — buy urgent items first',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: urgent.isNotEmpty
                                                            ? AppTheme.errorRed
                                                            : AppTheme.deepBlue,
                                                      ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right,
                                                color: AppTheme.mediumGray,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (selectedProjectId != null &&
                                  selectedProjectId.isNotEmpty)
                                FutureBuilder<_ProjectMaterialBudget>(
                                  key: ValueKey<String>(
                                      'budget_$selectedProjectId'),
                                  future: _loadProjectMaterialBudget(
                                      selectedProjectId),
                                  builder: (context, snap) {
                                    final budget = snap.data;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.black
                                                    .withValues(alpha: 0.06),
                                              ),
                                            ),
                                            child: Text(
                                              budget == null
                                                  ? 'Loading project budget…'
                                                  : budget.hasBudget
                                                      ? 'Remaining ${budget.sourceLabel}: ${_peso(budget.remaining)}'
                                                      : 'No project budget on file',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.deepBlue,
                                                  ),
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed:
                                                _showAddAllocationDialog,
                                            icon: const Icon(Icons.add, size: 18),
                                            label: const Text(
                                                'Add material to this project'),
                                          ),
                                        ],
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color:
                                                      iconColor.withAlpha(24),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                          color: AppTheme
                                                              .mediumGray),
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

                                  final projectLabel = selectedProjectId == null
                                      ? 'this project'
                                      : siteLabel(selectedProjectId);

                                  final totalStockCard = buildStatCard(
                                    icon: Icons.inventory_2_outlined,
                                    iconColor: AppTheme.deepBlue,
                                    label: 'Stock on $projectLabel',
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
                                    label: 'Used this month on $projectLabel',
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
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
                              _sectionHeading(
                                context,
                                title: selectedProjectId == null
                                    ? 'Stock on this project'
                                    : 'Stock on ${siteLabel(selectedProjectId)}',
                                subtitle:
                                    'Saved only to the selected project. Other projects cannot see or use this stock.',
                                onSeeAll: inventoryItems.isEmpty
                                    ? null
                                    : () => _showFullInventoryTable(
                                          context,
                                          inventoryItems,
                                        ),
                              ),
                              if (inventoryItems.isEmpty)
                                _emptyState(
                                  context,
                                  'No stock saved to this project yet. Use Add material to this project.',
                                )
                              else
                                for (final item in inventoryItems)
                                  _projectStockCard(context, item),
                              _sectionHeading(
                                context,
                                title: selectedProjectId == null
                                    ? 'Material usage'
                                    : 'Usage on ${siteLabel(selectedProjectId)}',
                                subtitle: usageByProject.isEmpty
                                    ? null
                                    : 'Releases and site usage for this project only',
                              ),
                              if (usageByProject.isEmpty)
                                _emptyState(
                                  context,
                                  'No material usage records yet.',
                                )
                              else
                                for (final entry in usageByProject.entries) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 12, 14, 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.apartment_outlined,
                                              size: 16,
                                              color: AppTheme.deepBlue,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                siteLabel(entry.key),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: AppTheme.deepBlue,
                                                    ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _showFullMaterialUsageTable(
                                                context,
                                                siteLabel(entry.key),
                                                entry.value,
                                              ),
                                              child: const Text('See all'),
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 8),
                                        for (final usage in entry.value.take(6))
                                          _usageLineCard(context, usage),
                                        if (entry.value.length > 6)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 4, bottom: 6),
                                            child: Text(
                                              '+${entry.value.length - 6} more records',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppTheme.mediumGray,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              const SizedBox(height: 72),
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
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Distribution per site',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: siteSummaries.length,
                      itemBuilder: (context, index) =>
                          _siteSummaryCard(context, siteSummaries[index]),
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
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (_selectedProjectName ?? '').trim().isEmpty
                              ? 'Inventory'
                              : 'Inventory on ${_selectedProjectName!.trim()}',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: inventoryItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = inventoryItems[index];
                        final name =
                            (item['materialName'] ?? 'Material').toString();
                        final unit = (item['unit'] ?? '').toString();
                        final stock = _toMoney(item['stock']);
                        final unitPrice =
                            _toMoney(item['unitPrice'] ?? item['price']);
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        _qtyWithUnit(stock, unit),
                                        if (unitPrice > 0)
                                          '${_peso(unitPrice)} / ${unit.isEmpty ? 'unit' : unit}',
                                      ].join('  ·  '),
                                      style: const TextStyle(
                                        color: AppTheme.mediumGray,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  _showRestockDialog(item);
                                },
                                child: const Text('Restock'),
                              ),
                            ],
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
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          siteId,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  Text(
                    '${usages.length} usage record${usages.length == 1 ? '' : 's'}',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mediumGray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: usages.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (context, index) =>
                          _usageLineCard(context, usages[index]),
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

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return DefaultTabController(
          length: 2,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Material(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                  child: SizedBox(
                    height: MediaQuery.of(sheetContext).size.height *
                        (MediaQuery.of(sheetContext).size.width < 720
                            ? 0.92
                            : 0.82),
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
                                  'Purchase queue',
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
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
                              border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06)),
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
                              labelStyle:
                                  const TextStyle(fontWeight: FontWeight.w700),
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
                                emptyMessage:
                                    'No pending material requests from Resident Engineers.',
                                enablePriorityFilter: true,
                                onPriorityFilterChanged: (value) =>
                                    setSheetState(() =>
                                        _requestPriorityFilter = value),
                              ),
                              _buildMaterialRequestList(
                                releasedStream,
                                emptyMessage:
                                    'No released material requests yet.',
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
      },
    );
  }

  Widget _buildMaterialRequestList(
    Stream<QuerySnapshot<Map<String, dynamic>>> stream, {
    required String emptyMessage,
    bool showReleasedLabel = false,
    bool enablePriorityFilter = false,
    ValueChanged<String>? onPriorityFilterChanged,
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

        var docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          snapshot.data?.docs ?? const [],
        );
        docs.sort((a, b) {
          final ap = (a.data()['priority'] ?? '').toString().toLowerCase() ==
                  'urgent'
              ? 0
              : 1;
          final bp = (b.data()['priority'] ?? '').toString().toLowerCase() ==
                  'urgent'
              ? 0
              : 1;
          if (ap != bp) return ap.compareTo(bp);
          return _parseRequestDate(b.data()['createdAt'])
              .compareTo(_parseRequestDate(a.data()['createdAt']));
        });

        if (enablePriorityFilter && _requestPriorityFilter != 'all') {
          docs = docs
              .where((d) =>
                  (d.data()['priority'] ?? 'normal')
                      .toString()
                      .toLowerCase() ==
                  _requestPriorityFilter)
              .toList();
        }

        if (snapshot.data?.docs.isEmpty ?? true) {
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

        return Column(
          children: [
            if (enablePriorityFilter)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const [
                      ('all', 'All'),
                      ('urgent', 'Urgent — buy first'),
                      ('normal', 'Normal'),
                    ])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: _requestPriorityFilter == option.$1,
                        onSelected: (_) {
                          onPriorityFilterChanged?.call(option.$1);
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Text(
                        _requestPriorityFilter == 'urgent'
                            ? 'No urgent requests right now.'
                            : 'No normal-priority requests.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final subject = (data['subject'] ?? 'Material request').toString();
            final details = (data['details'] ?? '').toString();
            final projectId = (data['projectId'] ?? 'Unknown site').toString();
            final projectName = (data['projectName'] ?? '').toString();
            final createdBy = (data['createdBy'] ?? '').toString();
            final createdByName = (data['createdByName'] ?? '').toString();
            final isUrgent =
                (data['priority'] ?? '').toString().toLowerCase() == 'urgent';
            final qty = data['requestedQuantity'];
            final unit = (data['unit'] ?? '').toString();
            final qtyText = qty == null
                ? ''
                : '${qty is num ? qty.toStringAsFixed(qty % 1 == 0 ? 0 : 1) : qty} $unit'
                    .trim();

            final siteLabel = projectName.isNotEmpty ? projectName : projectId;

            final managerText =
                (createdByName.isNotEmpty ? createdByName : createdBy).trim();

            return InkWell(
              onTap: () => _showMaterialRequestActionDialog(doc),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUrgent ? const Color(0xFFFFF1F2) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isUrgent
                        ? AppTheme.errorRed.withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
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
                    // Project first so admin can tell which site needs materials.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.deepBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.deepBlue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.apartment_outlined,
                              size: 18, color: AppTheme.deepBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PROJECT',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppTheme.deepBlue,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                ),
                                Text(
                                  siteLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.deepBlue,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (isUrgent)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.errorRed.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'URGENT',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.errorRed,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          if (showReleasedLabel)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.softGreen
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: AppTheme.softGreen
                                        .withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                'Released',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.softGreen,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subject,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        details,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    if (qtyText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Need: $qtyText${isUrgent ? ' — purchase immediately' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isUrgent
                                  ? AppTheme.errorRed
                                  : AppTheme.deepBlue,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.engineering_outlined,
                            size: 16, color: AppTheme.mediumGray),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Resident Engineer: ${managerText.isEmpty ? 'Unknown' : managerText}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.mediumGray,
                                  fontWeight: FontWeight.w600,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (projectName.isNotEmpty && projectName != projectId) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Project ID: $projectId',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          isUrgent
                              ? 'Open to buy now'
                              : 'Open to purchase / reject',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.deepBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios,
                            size: 14, color: AppTheme.mediumGray),
                      ],
                    ),
                  ],
                ),
              ),
            );
                      },
                    ),
            ),
          ],
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
    final isUrgent =
        (data['priority'] ?? '').toString().toLowerCase() == 'urgent';
    final requestedQty = _toMoney(data['requestedQuantity']);
    final requestedUnit = (data['unit'] ?? '').toString();
    final dateNeeded = (data['dateNeeded'] ?? '').toString();

    final siteLabel = projectName.isNotEmpty ? projectName : projectId;
    final managerDisplay =
        (createdByName.isNotEmpty ? createdByName : createdBy).trim();

    Map<String, dynamic>? allocationData;
    if (projectId.isNotEmpty &&
        projectId != 'Unknown site' &&
        allocationId.isNotEmpty) {
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
            ...(d.data() as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{},
            'id': d.id,
          },
        )
        .toList();

    if (!mounted) return;

    final commentController = TextEditingController();
    final quantityController = TextEditingController(
      text: requestedQty > 0
          ? (requestedQty % 1 == 0
              ? requestedQty.toStringAsFixed(0)
              : requestedQty.toStringAsFixed(1))
          : '',
    );
    String? selectedInventoryId;
    Map<String, dynamic>? selectedInventory;

    final requestedName =
        (data['materialName'] ?? subject).toString().trim().toLowerCase();
    if (requestedName.isNotEmpty) {
      for (final item in inventoryItems) {
        final name = (item['materialName'] ?? '').toString().trim().toLowerCase();
        if (name == requestedName) {
          selectedInventoryId = (item['id'] ?? '').toString();
          selectedInventory = item;
          break;
        }
      }
    }

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
              final raw =
                  allocationData['unitPrice'] ?? allocationData['price'];
              if (raw is num) {
                allocationUnitPrice = raw.toDouble();
              } else if (raw is String) {
                final cleaned =
                    raw.replaceAll(',', '').replaceAll('₱', '').trim();
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

              final priceRaw = selectedInventory!['unitPrice'] ??
                  selectedInventory!['price'];
              if (priceRaw is num) {
                unitPrice = priceRaw.toDouble();
              } else if (priceRaw is String) {
                final cleaned =
                    priceRaw.replaceAll(',', '').replaceAll('₱', '').trim();
                unitPrice = double.tryParse(cleaned);
              }

              unitLabel = (selectedInventory!['unit'] ?? '').toString();
            }

            final chosenUnitPrice =
                (allocationUnitPrice != null && allocationUnitPrice > 0)
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

            final requestedMaterial =
                (data['materialName'] ?? subject).toString();

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

              final priceRaw = selectedInventory!['unitPrice'] ??
                  selectedInventory!['price'];
              double? unitPriceForExpense;
              if (allocationUnitPrice != null && allocationUnitPrice > 0) {
                unitPriceForExpense = allocationUnitPrice;
              } else {
                if (priceRaw is num) {
                  unitPriceForExpense = priceRaw.toDouble();
                } else if (priceRaw is String) {
                  final cleaned =
                      priceRaw.replaceAll(',', '').replaceAll('₱', '').trim();
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
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
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
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Site: $siteLabel | Project ID: $projectId',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: AppTheme.mediumGray),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        );

                        Widget infoRow(
                            IconData icon, String label, String value) {
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
                                          ?.copyWith(
                                              color: AppTheme.mediumGray),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      value,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
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
                                      'Resident Engineer',
                                      managerDisplay.isEmpty
                                          ? 'Unknown'
                                          : managerDisplay,
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      height: 1,
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
                                    ),
                                    const SizedBox(height: 12),
                                    infoRow(
                                      Icons.inventory_2_outlined,
                                      'Requested Material',
                                      requestedMaterial,
                                    ),
                                    const SizedBox(height: 12),
                                    infoRow(
                                      Icons.priority_high,
                                      'Priority',
                                      isUrgent
                                          ? 'URGENT — buy first'
                                          : 'Normal — purchase when ready',
                                    ),
                                    if (requestedQty > 0) ...[
                                      const SizedBox(height: 12),
                                      infoRow(
                                        Icons.numbers,
                                        'Requested quantity',
                                        '${requestedQty.toStringAsFixed(requestedQty % 1 == 0 ? 0 : 1)} $requestedUnit'
                                            .trim(),
                                      ),
                                    ],
                                    if (dateNeeded.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      infoRow(
                                        Icons.event_outlined,
                                        'Date needed',
                                        dateNeeded.split('T').first,
                                      ),
                                    ],
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
                                        borderRadius:
                                            BorderRadius.circular(999),
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
                                        isUrgent
                                            ? 'Urgent — purchaser should buy now'
                                            : 'Pending purchase',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
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
                                          (item['materialName'] ?? 'Material')
                                              .toString();
                                      final unit =
                                          (item['unit'] ?? '').toString();
                                      final stockRaw = item['stock'];
                                      double stock;
                                      if (stockRaw is num) {
                                        stock = stockRaw.toDouble();
                                      } else {
                                        stock = double.tryParse(
                                                stockRaw?.toString() ?? '0') ??
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
                                          (m) => !inventoryNames
                                              .contains(m.toLowerCase()),
                                        )
                                        .toList();
                                    extra.sort(
                                      (a, b) => a
                                          .toLowerCase()
                                          .compareTo(b.toLowerCase()),
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
                                                  ?.copyWith(
                                                      color:
                                                          AppTheme.mediumGray),
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
                                    if (value != null &&
                                        value.startsWith('manual:')) {
                                      selectedInventory = null;
                                    } else {
                                      selectedInventory =
                                          inventoryItems.firstWhere(
                                        (item) =>
                                            (item['id'] ?? '').toString() ==
                                            value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 10),
                              if (availableStock != null &&
                                  unitLabel.isNotEmpty)
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
                              if (calculatedAmount != null &&
                                  quantity != null &&
                                  quantity > 0)
                                Text(
                                  'This purchase cost: ₱${calculatedAmount.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: quantityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Quantity to buy / release',
                                  hintText: requestedQty > 0
                                      ? 'Requested: ${requestedQty.toStringAsFixed(requestedQty % 1 == 0 ? 0 : 1)}'
                                      : null,
                                ),
                                onChanged: (_) => setStateDialog(() {}),
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
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: rejectAction,
                                    child: const Text('Reject'),
                                  ),
                                  FilledButton(
                                    onPressed: approveAction,
                                    style: isUrgent
                                        ? FilledButton.styleFrom(
                                            backgroundColor: AppTheme.errorRed,
                                          )
                                        : null,
                                    child: Text(
                                      isUrgent
                                          ? 'Buy now (urgent)'
                                          : 'Purchase & release',
                                    ),
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
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
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
              throw Exception(
                  'Assigned material allocation not found. Ask admin to re-assign/budget materials.');
            }
            final allocData =
                (allocSnap.data() as Map?)?.cast<String, dynamic>() ??
                    <String, dynamic>{};

            double readNum(dynamic v) {
              if (v is num) return v.toDouble();
              return double.tryParse(
                      (v ?? '').toString().replaceAll(',', '')) ??
                  0.0;
            }

            final budget = readNum(allocData['budgetQuantity']);
            final used = readNum(allocData['usedQuantity']);
            final remaining = (budget - used).clamp(0.0, double.infinity);
            if (releasedQuantity > remaining) {
              throw Exception(
                  'Release exceeds remaining allocation. Remaining: ${remaining.toStringAsFixed(1)}');
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

          double readStock(dynamic v) {
            if (v is num) return v.toDouble();
            return double.tryParse(
                    (v ?? '').toString().replaceAll(',', '')) ??
                0.0;
          }

          final currentStock = readStock(invData['stock']);
          if (releasedQuantity > currentStock) {
            throw Exception(
                'Not enough stock to release. In stock: ${currentStock.toStringAsFixed(1)}');
          }

          tx.update(inventoryRef, {
            'stock': currentStock - releasedQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastReleasedAt': FieldValue.serverTimestamp(),
            'lastReleasedQty': releasedQuantity,
            'lastReleaseRequestId': doc.id,
          });
        });
      }

      await doc.reference.update({
        'status': status,
        'adminComment': comment,
        'handledAt': nowIso,
        if (status == AppConstants.materialRequestApproved)
          'approvedAt': nowIso,
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
                ? 'Material purchased and released to the site'
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

    _ProjectMaterialBudget budgetSummary =
        await _loadProjectMaterialBudget(selectedProjectId);
    if (!mounted) return;

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

              if (name.isEmpty ||
                  unit.isEmpty ||
                  budget == null ||
                  budget <= 0) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Please enter material name, unit, and a valid budget quantity.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              if (unitPrice == null || unitPrice < 0) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Enter a unit price so this material can be checked against the project budget.'),
                    backgroundColor: AppTheme.errorRed,
                  ),
                );
                return;
              }

              final estimatedCost = unitPrice * budget;
              if (budgetSummary.hasBudget &&
                  estimatedCost > budgetSummary.remaining + 0.009) {
                setStateDialog(() => isSaving = false);
                if (!mounted) return;
                rootMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'This material (${_peso(estimatedCost)}) exceeds remaining ${budgetSummary.sourceLabel} (${_peso(budgetSummary.remaining)}).',
                    ),
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
                  'unitPrice': unitPrice,
                  'projectId': selectedProjectId,
                  'projectName': (selectedProjectName ??
                      nameForProject(selectedProjectId)),
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
                        'unitPrice': unitPrice,
                        'projectId': selectedProjectId,
                        'projectName': (selectedProjectName ??
                            nameForProject(selectedProjectId)),
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
                    content: Text(
                        'Material added to this project from the project budget.'),
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

            final livePrice = double.tryParse(
                  unitPriceController.text.trim().replaceAll(',', ''),
                ) ??
                0;
            final liveQty = double.tryParse(
                  budgetController.text.trim().replaceAll(',', ''),
                ) ??
                0;
            final liveCost = livePrice * liveQty;

            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Text('Add material to project'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: budgetSummary.hasBudget
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          budgetSummary.hasBudget
                              ? 'Remaining ${budgetSummary.sourceLabel}: ${_peso(budgetSummary.remaining)}\nAlready assigned materials: ${_peso(budgetSummary.committed)}'
                              : 'No project budget on file. Add a unit price and quantity so costs stay trackable.',
                          style: Theme.of(dialogContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                            : (v) async {
                                if (v == null || v.isEmpty) return;
                                setStateDialog(() {
                                  selectedProjectId = v;
                                  selectedProjectName = nameForProject(v);
                                });
                                final next =
                                    await _loadProjectMaterialBudget(v);
                                setStateDialog(() => budgetSummary = next);
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
                      decoration:
                          const InputDecoration(labelText: 'Material name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: 'Unit (e.g. bag, m³)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setStateDialog(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Unit price (₱)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: budgetController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setStateDialog(() {}),
                      onSubmitted: (_) => save(),
                      decoration: const InputDecoration(
                        labelText: 'Budget quantity',
                        helperText:
                            'How many units this project may request',
                      ),
                    ),
                    if (liveCost > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Estimated cost: ${_peso(liveCost)}'
                        '${budgetSummary.hasBudget ? ' • remaining after add: ${_peso((budgetSummary.remaining - liveCost).clamp(0, double.infinity))}' : ''}',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: budgetSummary.hasBudget &&
                                      liveCost > budgetSummary.remaining
                                  ? AppTheme.errorRed
                                  : AppTheme.deepBlue,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
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

class _ProjectMaterialBudget {
  const _ProjectMaterialBudget({
    required this.remaining,
    required this.allocated,
    required this.committed,
    required this.sourceLabel,
  });

  final double remaining;
  final double allocated;
  final double committed;
  final String sourceLabel;

  bool get hasBudget => allocated > 0;
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
