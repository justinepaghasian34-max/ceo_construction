import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/audit_log_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

class AdminMaterialMonitoring extends StatefulWidget {
  const AdminMaterialMonitoring({super.key});

  @override
  State<AdminMaterialMonitoring> createState() => _AdminMaterialMonitoringState();
}

class _AdminMaterialMonitoringState extends State<AdminMaterialMonitoring> {
  @override
  Widget build(BuildContext context) {
    final hive = HiveService.instance;
    final usages = hive.getAllMaterialUsage();
    final inventoryItems = hive.getAllMaterialInventory();
    final reports = hive.getAllDailyReports();

    final reportById = <String, dynamic>{};
    for (final r in reports) {
      reportById[r.id] = r;
    }

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);

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

    double monthQuantity = 0;

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

    final Map<String, List<_MaterialUsageEntry>> usageByProject = {};

    for (final usage in usages) {
      final name = (usage['materialName'] ?? 'Material').toString();

      final quantityRaw = usage['quantity'] ?? usage['stock'] ?? 0;
      final quantity = double.tryParse(quantityRaw.toString()) ?? 0.0;

      DateTime? usageDate;
      final reportId = (usage['reportId'] ?? '').toString();
      final report = reportById[reportId];
      if (report != null) {
        final dateDynamic = report.reportDate;
        if (dateDynamic is DateTime) {
          usageDate = dateDynamic;
        }
      }

      if (usageDate == null) {
        final dateRaw = usage['date'];
        if (dateRaw is String) {
          try {
            usageDate = DateTime.parse(dateRaw);
          } catch (_) {}
        } else if (dateRaw is DateTime) {
          usageDate = dateRaw;
        }
      }

      if (usageDate != null &&
          !usageDate.isBefore(startOfMonth) &&
          usageDate.isBefore(endOfMonth)) {
        monthQuantity += quantity;
      }

      final status = (usage['status'] ?? usage['syncStatus'] ?? '').toString();

      final projectId = (usage['projectId'] ?? 'Unknown site').toString();

      final unitPrice = unitPriceByMaterial[name];
      final double? totalCost = unitPrice != null ? unitPrice * quantity : null;

      usageByProject.putIfAbsent(projectId, () => []).add(
            _MaterialUsageEntry(
              materialName: name,
              quantity: quantity,
              unit: (usage['unit'] ?? '').toString(),
              status: status,
              projectId: projectId,
              reportId: reportId,
              date: usageDate,
              unitPrice: unitPrice,
              totalCost: totalCost,
            ),
          );
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
            final count = snapshot.data?.docs.length ?? 0;

            return IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none),
                  if (count > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Material requests',
              onPressed: _showMaterialRequestsBottomSheet,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.materialInventory,
      ),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SmartInsightCard(
                title: 'Smart Insight',
                message:
                    'Keep material stock and monthly usage visible to prevent site delays.',
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;

                  Widget buildStatCard({
                    required IconData icon,
                    required Color iconColor,
                    required String label,
                    required String value,
                  }) {
                    return AppCard(
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
                  }

                  final totalStockCard = buildStatCard(
                    icon: Icons.inventory_2_outlined,
                    iconColor: AppTheme.deepBlue,
                    label: 'Total material in stock',
                    value: totalStock.toStringAsFixed(1),
                  );

                  final usedThisMonthCard = buildStatCard(
                    icon: Icons.stacked_bar_chart,
                    iconColor: AppTheme.accentYellow,
                    label: 'Material used this month',
                    value: monthQuantity.toStringAsFixed(1),
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
                    '${siteSummaries.first.projectId} '
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
                GestureDetector(
                  onTap: () => _showFullSiteDistributionTable(
                    context,
                    siteSummaries,
                  ),
                  child: GlassDataTableTheme(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        columns: const [
                          DataColumn(label: Text('Site')),
                          DataColumn(label: Text('Materials')),
                          DataColumn(label: Text('Total qty used')),
                          DataColumn(label: Text('Total cost')),
                          DataColumn(label: Text('Last usage')),
                        ],
                        rows: [
                          for (final summary in siteSummaries)
                            _buildSiteDistributionRow(context, summary),
                        ],
                      ),
                    ),
                  ),
                ),
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
                  'Site: ${entry.key}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showFullMaterialUsageTable(
                    context,
                    entry.key,
                    entry.value,
                  ),
                  child: GlassDataTableTheme(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showFullInventoryTable(
    BuildContext context,
    List<dynamic> inventoryItems,
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
                        'Material inventory',
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
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                          DataColumn(label: Text('Material ID')),
                          DataColumn(label: Text('Material name')),
                          DataColumn(label: Text('Stock')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Price / unit')),
                          DataColumn(label: Text('Location')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final item in inventoryItems)
                            _buildInventoryRow(sheetContext, item),
                        ],
                      ),
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
            height: MediaQuery.of(sheetContext).size.height * 0.8,
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
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                          DataColumn(label: Text('Site')),
                          DataColumn(label: Text('Materials')),
                          DataColumn(label: Text('Total qty used')),
                          DataColumn(label: Text('Total cost')),
                          DataColumn(label: Text('Last usage')),
                        ],
                        rows: [
                          for (final summary in siteSummaries)
                            _buildSiteDistributionRow(sheetContext, summary),
                        ],
                      ),
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
            height: MediaQuery.of(sheetContext).size.height * 0.8,
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
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                'Failed to load material requests.',
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

    final siteLabel = projectName.isNotEmpty ? projectName : projectId;
    final managerDisplay =
        (createdByName.isNotEmpty ? createdByName : createdBy).trim();

    final inventoryItems = HiveService.instance.getAllMaterialInventory();
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

            double? calculatedAmount;
            final quantityText = quantityController.text.trim();
            final quantity = double.tryParse(
              quantityText.isEmpty ? '0' : quantityText.replaceAll(',', ''),
            );
            if (quantity != null &&
                quantity > 0 &&
                unitPrice != null &&
                unitPrice > 0) {
              calculatedAmount = unitPrice * quantity;
            }

            return AlertDialog(
              title: Text(subject),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Site: $siteLabel',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mediumGray),
                    ),
                    if (projectName.isNotEmpty && projectName != projectId)
                      Text(
                        'Project ID: $projectId',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Site manager: '
                      '${managerDisplay.isEmpty ? 'Unknown' : managerDisplay}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.mediumGray),
                    ),
                    const SizedBox(height: 8),
                    if (details.isNotEmpty) ...[
                      Text(details),
                      const SizedBox(height: 12),
                    ],
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
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Material to release',
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          selectedInventoryId = value;
                          selectedInventory = inventoryItems.firstWhere(
                            (item) =>
                                (item['id'] ?? '').toString() == value,
                            orElse: () => <String, dynamic>{},
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantity to release',
                        hintText:
                            availableStock != null && unitLabel.isNotEmpty
                                ? 'Max ${availableStock.toStringAsFixed(1)} $unitLabel'
                                : null,
                      ),
                      onChanged: (_) {
                        setStateDialog(() {});
                      },
                    ),
                    if (availableStock != null && unitLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Available stock: ${availableStock.toStringAsFixed(1)} $unitLabel',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    if (unitPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Unit price: ₱${unitPrice.toStringAsFixed(2)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    if (calculatedAmount != null &&
                        quantity != null &&
                        quantity > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'This release cost: ₱${calculatedAmount.toStringAsFixed(2)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.mediumGray),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comment / reply to site manager',
                        hintText:
                            'Example: Approved 10 out of 20 bags of cement (remaining stock) or No stock today.',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () async {
                    final comment = commentController.text.trim();
                    Navigator.of(dialogContext).pop();
                    await _updateMaterialRequestStatus(
                      doc,
                      AppConstants.materialRequestRejected,
                      comment,
                    );
                  },
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () async {
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
                        const SnackBar(
                          content: Text(
                            'Please select a material from inventory to release.',
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
                          content:
                              Text('Enter a valid quantity to release.'),
                          backgroundColor: AppTheme.errorRed,
                        ),
                      );
                      return;
                    }

                    final stockRaw = selectedInventory!['stock'];
                    double currentStock;
                    if (stockRaw is num) {
                      currentStock = stockRaw.toDouble();
                    } else {
                      currentStock =
                          double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;
                    }
                    if (releaseQuantity > currentStock) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Not enough stock. Available: ${currentStock.toStringAsFixed(1)}',
                          ),
                          backgroundColor: AppTheme.errorRed,
                        ),
                      );
                      return;
                    }

                    final priceRaw = selectedInventory!['unitPrice'] ??
                        selectedInventory!['price'];
                    double? unitPriceForExpense;
                    if (priceRaw is num) {
                      unitPriceForExpense = priceRaw.toDouble();
                    } else if (priceRaw is String) {
                      final cleaned = priceRaw
                          .replaceAll(',', '')
                          .replaceAll('₱', '')
                          .trim();
                      unitPriceForExpense = double.tryParse(cleaned);
                    }
                    if (unitPriceForExpense == null ||
                        unitPriceForExpense <= 0) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Selected material has no valid price per unit. Set a price in the inventory first.',
                          ),
                          backgroundColor: AppTheme.errorRed,
                        ),
                      );
                      return;
                    }

                    final expenseAmount =
                        unitPriceForExpense * releaseQuantity;
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
                  },
                  child: const Text('Approve & Release'),
                ),
              ],
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

      await doc.reference.update({
        'status': status,
        'adminComment': comment,
        'handledAt': nowIso,
        if (status == AppConstants.materialRequestApproved)
          'release': {
            'inventoryItemId': inventoryItemId,
            'releasedQuantity': releasedQuantity,
            'expenseAmount': expenseAmount,
            'unitPrice': unitPrice,
          },
      });

      Map<String, dynamic>? inventorySnapshot;

      if (status == AppConstants.materialRequestApproved &&
          inventoryItemId != null &&
          releasedQuantity != null &&
          releasedQuantity > 0) {
        final hive = HiveService.instance;
        final existing = hive.getMaterialInventory(inventoryItemId);
        if (existing != null) {
          inventorySnapshot = Map<String, dynamic>.from(existing);

          final updated = Map<String, dynamic>.from(existing);
          final stockRaw = updated['stock'];
          double currentStock;
          if (stockRaw is num) {
            currentStock = stockRaw.toDouble();
          } else {
            currentStock =
                double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;
          }
          final newStock =
              (currentStock - releasedQuantity).clamp(0.0, double.infinity);
          updated['stock'] = newStock;
          updated['status'] = newStock <= 0 ? 'lowstock' : 'instock';

          await hive.saveMaterialInventory(inventoryItemId, updated);
        }
      }

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
        final hive = HiveService.instance;

        final materialName =
            (inventorySnapshot?['materialName'] ?? subject).toString();
        final unit = (inventorySnapshot?['unit'] ?? '').toString();

        final usageId =
            'mr_${doc.id}_${now.millisecondsSinceEpoch.toString()}';

        final usage = <String, dynamic>{
          'id': usageId,
          'materialName': materialName,
          'quantity': releasedQuantity,
          'unit': unit,
          'projectId': projectId,
          'reportId': 'material_request:${doc.id}',
          'status': 'released',
          'syncStatus': AppConstants.syncStatusCompleted,
          'materialRequestId': doc.id,
          'inventoryItemId': inventoryItemId,
          'date': nowIso,
        };

        await hive.saveMaterialUsage(usageId, usage);
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

  DataRow _buildInventoryRow(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final id = (item['id'] ?? '').toString();
    final materialId = (item['materialId'] ?? '').toString();
    final materialName = (item['materialName'] ?? 'Material').toString();
    final unit = (item['unit'] ?? '').toString();
    final location = (item['location'] ?? '').toString();

    final stockRaw = item['stock'];
    double stock;
    if (stockRaw is num) {
      stock = stockRaw.toDouble();
    } else {
      stock = double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;
    }

    final priceRaw = item['unitPrice'] ?? item['price'];
    double? unitPrice;
    if (priceRaw is num) {
      unitPrice = priceRaw.toDouble();
    } else if (priceRaw is String) {
      final cleaned = priceRaw.replaceAll(',', '').replaceAll('₱', '').trim();
      unitPrice = double.tryParse(cleaned);
    }

    final rawStatus = (item['status'] ?? '').toString().toLowerCase();
    final computedStatus = stock <= 0 ? 'lowstock' : 'instock';
    final status = rawStatus.isEmpty ? computedStatus : rawStatus;

    return DataRow(
      cells: [
        DataCell(
          Text(
            materialId.isEmpty ? '-' : materialId,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              materialName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        DataCell(
          Text(
            stock.toStringAsFixed(1),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            unit,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            unitPrice == null ? '-' : unitPrice.toStringAsFixed(2),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            location,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        DataCell(
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      status == 'lowstock' ? AppTheme.errorRed : AppTheme.softGreen,
                ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Edit',
                onPressed:
                    id.isEmpty ? null : () => _showInventoryItemDialog(existing: item),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                onPressed:
                    id.isEmpty ? null : () => _confirmDeleteInventoryItem(id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showInventoryItemDialog({Map<String, dynamic>? existing}) async {
    final materialIdController = TextEditingController(
      text: (existing?['materialId'] ?? '').toString(),
    );
    final materialNameController = TextEditingController(
      text: (existing?['materialName'] ?? '').toString(),
    );
    final stockController = TextEditingController(
      text: existing == null
          ? ''
          : (() {
              final raw = existing['stock'];
              if (raw is num) return raw.toString();
              return raw?.toString() ?? '';
            })(),
    );
    final unitController = TextEditingController(
      text: (existing?['unit'] ?? '').toString(),
    );
    final locationController = TextEditingController(
      text: (existing?['location'] ?? '').toString(),
    );
    final priceController = TextEditingController(
      text: existing == null
          ? ''
          : (() {
              final raw = existing['unitPrice'] ?? existing['price'];
              if (raw is num) return raw.toString();
              return raw?.toString() ?? '';
            })(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existing == null ? 'Add material' : 'Edit material'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: materialIdController,
                  decoration: const InputDecoration(
                    labelText: 'Material ID',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: materialNameController,
                  decoration: const InputDecoration(
                    labelText: 'Material name',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price per unit',
                    prefixText: '₱',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);

                final materialId = materialIdController.text.trim();
                final materialName = materialNameController.text.trim();
                final unit = unitController.text.trim();
                final location = locationController.text.trim();
                final stockValue =
                    double.tryParse(stockController.text.trim()) ?? 0.0;

                final rawPriceText = priceController.text
                    .trim()
                    .replaceAll(',', '')
                    .replaceAll('₱', '');
                final unitPrice =
                    double.tryParse(rawPriceText.isEmpty ? '0' : rawPriceText) ??
                        0.0;

                final status = stockValue <= 0 ? 'lowstock' : 'instock';

                String id = (existing?['id'] ?? '').toString();
                if (id.isEmpty) {
                  id = DateTime.now()
                      .millisecondsSinceEpoch
                      .toString();
                }

                final data = <String, dynamic>{
                  'id': id,
                  'materialId': materialId,
                  'materialName': materialName,
                  'stock': stockValue,
                  'unit': unit,
                  'location': location,
                  'unitPrice': unitPrice,
                  'status': status,
                };

                await HiveService.instance.saveMaterialInventory(id, data);

                if (mounted) {
                  setState(() {});
                }

                navigator.pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteInventoryItem(String id) async {
    if (id.isEmpty) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete material'),
          content: const Text(
            'Are you sure you want to delete this material from the material inventory?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await HiveService.instance.deleteMaterialInventory(id);
      if (mounted) {
        setState(() {});
      }
    }
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
  final int materialsCount;
  final double totalQuantity;
   final double totalCost;
  final DateTime? lastUsageDate;

  _SiteDistributionSummary({
    required this.projectId,
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            summary.projectId,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
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
