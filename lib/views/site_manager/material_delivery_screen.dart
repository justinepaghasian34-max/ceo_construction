import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../utils/dialog_utils.dart';
import 'widgets/site_manager_card.dart';
import '../../widgets/common/status_chip.dart';

class MaterialDeliveryScreen extends StatefulWidget {
  const MaterialDeliveryScreen({super.key});

  @override
  State<MaterialDeliveryScreen> createState() => _MaterialDeliveryScreenState();
}

class _MaterialDeliveryScreenState extends State<MaterialDeliveryScreen> {
  String? get _projectId {
    final user = AuthService.instance.currentUser;
    if (user == null) return null;
    if (user.assignedProjects.isEmpty) return null;
    return user.assignedProjects.first;
  }

  Future<void> _markDeliveryCompleted(
    BuildContext context,
    String projectId,
    String materialRequestId,
    Map<String, dynamic> request,
  ) async {
    final confirm = await showConfirmDialog(
      context: context,
      title: 'Complete Delivery',
      message: 'Confirm that the delivered materials match the approved release.',
      confirmText: 'Materials Complete',
      cancelText: 'Cancel',
    );

    if (!mounted || confirm != true) return;

    try {
      final user = AuthService.instance.currentUser;
      final nowIso = DateTime.now().toIso8601String();
      final reqRef = FirebaseService.instance.projectsCollection
          .doc(projectId)
          .collection('material_requests')
          .doc(materialRequestId);

      await reqRef.set({
        'deliveryStatus': 'completed',
        'deliveredAt': nowIso,
        'deliveredBy': user?.id ?? user?.email,
        'deliveredByName': user?.displayName ?? '',
      }, SetOptions(merge: true));

      final deliveryId = (request['deliveryId'] ?? '').toString();
      if (deliveryId.isNotEmpty) {
        final deliveryRef = FirebaseService.instance
            .deliveriesCollection(projectId)
            .doc(deliveryId);

        // Use set+merge so this works whether the delivery doc exists or not.
        await deliveryRef.set({
          'status': 'completed',
          'completedAt': nowIso,
          'completedBy': user?.id ?? user?.email,
          'completedByName': user?.displayName ?? '',
          'projectId': projectId,
          'materialRequestId': materialRequestId,
        }, SetOptions(merge: true));
      } else {
        // No deliveryId — create a new delivery record automatically.
        await FirebaseService.instance
            .deliveriesCollection(projectId)
            .add({
          'status': 'completed',
          'completedAt': nowIso,
          'completedBy': user?.id ?? user?.email,
          'completedByName': user?.displayName ?? '',
          'projectId': projectId,
          'materialRequestId': materialRequestId,
          'materialName': request['materialName'] ?? request['subject'] ?? '',
          'createdAt': nowIso,
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery marked as completed.'),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete delivery: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = _projectId;

    if (projectId == null || projectId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text(
            'Material Delivery',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Text(
            'No assigned project found for this user',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mediumGray,
                ),
          ),
        ),
      );
    }

    final requestStream = FirebaseService.instance.projectsCollection
        .doc(projectId)
        .collection('material_requests')
        .where('status', isEqualTo: AppConstants.materialRequestApproved)
        .limit(250)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Material Delivery',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: requestStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load deliveries',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.errorRed,
                    ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No approved material releases yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            );
          }

          final rows = docs
              .map((d) => <String, dynamic>{
                    'id': d.id,
                    ...(d.data() as Map?)?.cast<String, dynamic>() ??
                        <String, dynamic>{},
                  })
              .toList();

          rows.sort((a, b) {
            DateTime? toDate(dynamic v) {
              if (v is Timestamp) return v.toDate();
              final s = (v ?? '').toString();
              try {
                return DateTime.parse(s);
              } catch (_) {
                return null;
              }
            }

            final aDt = toDate(a['approvedAt'] ?? a['handledAt'] ?? a['createdAt']);
            final bDt = toDate(b['approvedAt'] ?? b['handledAt'] ?? b['createdAt']);
            if (aDt == null && bDt == null) return 0;
            if (aDt == null) return 1;
            if (bDt == null) return -1;
            return bDt.compareTo(aDt);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = rows[index];
              final id = (request['id'] ?? '').toString();

              final materialName = (request['materialName'] ?? request['subject'] ?? 'Material')
                  .toString();

              final release = (request['release'] as Map?)?.cast<String, dynamic>();
              final unit = (release?['unit'] ?? request['unit'] ?? '').toString();
              final qtyRaw = release?['releasedQuantity'] ?? request['requestedQuantity'];
              final qty = qtyRaw is num
                  ? qtyRaw.toDouble()
                  : (double.tryParse(qtyRaw?.toString() ?? '0') ?? 0.0);
              final deliveryStatus = (request['deliveryStatus'] ?? '').toString();

              final syncStatus =
                  (request['syncStatus'] ?? AppConstants.syncStatusCompleted)
                      .toString();

              final isCompleted = deliveryStatus.toLowerCase() == 'completed';

              DateTime? toDate(dynamic v) {
                if (v is Timestamp) return v.toDate();
                final s = (v ?? '').toString();
                try {
                  return DateTime.parse(s);
                } catch (_) {
                  return null;
                }
              }

              final approvedAt =
                  toDate(request['approvedAt'] ?? request['handledAt']);
              String approvedText = '';
              if (approvedAt != null) {
                approvedText = '${approvedAt.year.toString().padLeft(4, '0')}-'
                    '${approvedAt.month.toString().padLeft(2, '0')}-'
                    '${approvedAt.day.toString().padLeft(2, '0')}';
              }

              return SiteManagerCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      color: AppTheme.residentBlue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            materialName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Approved release: ${qty.toStringAsFixed(1)} ${unit.isEmpty ? '' : unit}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.mediumGray,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (approvedText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Approved date: $approvedText',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (!isCompleted)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: id.isEmpty
                                    ? null
                                    : () => _markDeliveryCompleted(
                                          context,
                                          projectId,
                                          id,
                                          request,
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.residentBlue,
                                  foregroundColor: AppTheme.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Materials Complete'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusChip(
                          label: isCompleted ? 'Completed' : 'Released',
                          status: isCompleted
                              ? StatusType.success
                              : StatusType.info,
                          isSmall: true,
                        ),
                        const SizedBox(height: 6),
                        SyncStatusChip(
                          syncStatus: syncStatus,
                          isSmall: true,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
