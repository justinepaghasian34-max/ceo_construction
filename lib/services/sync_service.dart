import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import 'firebase_service.dart';
import 'hive_service.dart';
import 'geo_tag_service.dart';
import 'local_notification_service.dart';

class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();
  SyncService._();

  final FirebaseService _firebaseService = FirebaseService.instance;
  final HiveService _hiveService = HiveService.instance;
  final Connectivity _connectivity = Connectivity();
  final Uuid _uuid = const Uuid();
  final GeoTagService _geoTagService = GeoTagService.instance;

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

  bool _isSyncing = false;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Sync status stream
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  // Initialize sync service
  Future<void> initialize() async {
    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none && !_isSyncing) {
        _startAutoSync();
      }
    });

    // Start periodic sync if online
    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.isNotEmpty && connectivityResults.first != ConnectivityResult.none) {
      _startAutoSync();
    }
  }

  // Start automatic sync
  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!_isSyncing) {
        syncPendingData();
      }
    });
  }

  // Stop automatic sync
  void stopAutoSync() {
    _syncTimer?.cancel();
  }

  // Check if device is online
  Future<bool> isOnline() async {
    final connectivityResults = await _connectivity.checkConnectivity();
    return connectivityResults.isNotEmpty && connectivityResults.first != ConnectivityResult.none;
  }

  // Main sync method
  Future<SyncResult> syncPendingData() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await isOnline()) {
      return SyncResult(success: false, message: 'No internet connection');
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      int totalSynced = 0;
      int totalFailed = 0;

      // Sync daily reports
      final dailyReportsResult = await _syncDailyReports();
      totalSynced += dailyReportsResult.synced;
      totalFailed += dailyReportsResult.failed;

      // Sync attendance records
      final attendanceResult = await _syncAttendance();
      totalSynced += attendanceResult.synced;
      totalFailed += attendanceResult.failed;

      // Sync material usage
      final materialUsageResult = await _syncMaterialUsage();
      totalSynced += materialUsageResult.synced;
      totalFailed += materialUsageResult.failed;

      // Sync material requests
      final materialRequestsResult = await _syncMaterialRequests();
      totalSynced += materialRequestsResult.synced;
      totalFailed += materialRequestsResult.failed;

      // Sync deliveries
      final deliveriesResult = await _syncDeliveries();
      totalSynced += deliveriesResult.synced;
      totalFailed += deliveriesResult.failed;

      // Sync generic queue items
      final queueResult = await _syncQueueItems();
      totalSynced += queueResult.synced;
      totalFailed += queueResult.failed;

      final success = totalFailed == 0;
      final message = success 
          ? 'Successfully synced $totalSynced items'
          : 'Synced $totalSynced items, $totalFailed failed';

      _syncStatusController.add(success ? SyncStatus.completed : SyncStatus.failed);
      
      return SyncResult(
        success: success,
        message: message,
        syncedCount: totalSynced,
        failedCount: totalFailed,
      );

    } catch (e) {
      final errorText = e.toString().toLowerCase();
      final looksLikeDns = errorText.contains('unknownhostexception') ||
          errorText.contains('unable to resolve host') ||
          errorText.contains('eai_nodata') ||
          errorText.contains('firestore.googleapis.com');
      final looksUnavailable = errorText.contains('status{code=unavailable') ||
          errorText.contains('code=unavailable') ||
          errorText.contains('unavailable');

      if (looksLikeDns || looksUnavailable) {
        if (!kIsWeb) {
          try {
            await LocalNotificationService.instance.showNotification(
              id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
              title: 'Sync queued',
              body:
                  'Unable to reach Firestore. Your submission is saved locally and will sync when the network works.',
            );
          } catch (_) {}
        }

        _syncStatusController.add(SyncStatus.failed);
        return SyncResult(
          success: false,
          message:
              'Unable to reach Firestore (DNS/network issue). Submission saved locally and queued for sync.',
        );
      }

      _syncStatusController.add(SyncStatus.failed);
      return SyncResult(success: false, message: 'Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // Sync daily reports
  Future<SyncItemResult> _syncDailyReports() async {
    final pendingReports = _hiveService.getPendingSyncReports();
    int synced = 0;
    int failed = 0;

    for (final report in pendingReports) {
      try {
        // Update sync status
        final updatedReport = report.copyWith(syncStatus: AppConstants.syncStatusSyncing);
        await _hiveService.saveDailyReport(updatedReport);

        final payload = updatedReport.toJson();
        payload['geoTag'] ??= await _geoTagService.captureGeoTag();
        try {
          final projectSnap = await _firebaseService.projectsCollection
              .doc(report.projectId)
              .get();
          final projectData =
              (projectSnap.data() as Map?)?.cast<String, dynamic>() ?? {};
          payload['projectName'] =
              (projectData['name'] ?? payload['projectName'] ?? report.projectId)
                  .toString();
        } catch (_) {
          payload['projectName'] ??= report.projectId;
        }

        // Upload to Firestore
        await _firebaseService.dailyReportsCollection(report.projectId)
            .doc(report.id)
            .set(payload);

        try {
          final notifId = 'notif_daily_report_${report.id}';
          await _firebaseService.notificationsCollection.doc(notifId).set({
            'id': notifId,
            'type': 'daily_report_submitted',
            'audienceRole': 'admin',
            'title': 'Daily report submitted',
            'message':
                '${payload['projectName'] ?? report.projectId} sent a daily report',
            'priority': 'normal',
            'projectId': report.projectId,
            'projectName': payload['projectName'] ?? report.projectId,
            'dailyReportId': report.id,
            'createdAt': DateTime.now().toIso8601String(),
            'userId': 'admin',
            'createdByUid': report.reporterId,
            'isRead': false,
          });
        } catch (_) {}

        // Update sync status to completed
        final completedReport = report.copyWith(
          syncStatus: AppConstants.syncStatusCompleted,
          syncedAt: DateTime.now(),
        );
        await _hiveService.saveDailyReport(completedReport);

        synced++;
      } catch (e) {
        // Update sync status to failed
        final failedReport = report.copyWith(syncStatus: AppConstants.syncStatusFailed);
        await _hiveService.saveDailyReport(failedReport);
        failed++;
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync material requests
  Future<SyncItemResult> _syncMaterialRequests() async {
    final requests = _hiveService
        .getAllMaterialRequests()
        .where((r) {
          final status = (r['syncStatus']?.toString() ?? '').toLowerCase();
          return status == AppConstants.syncStatusPending ||
              status == AppConstants.syncStatusFailed;
        })
        .toList();
    if (requests.isEmpty) {
      return SyncItemResult(synced: 0, failed: 0);
    }

    int synced = 0;
    int failed = 0;

    for (final req in requests) {
      try {
        final projectId = req['projectId']?.toString();
        final id = req['id']?.toString();
        if (projectId == null || id == null || id.isEmpty) {
          continue;
        }

        req['geoTag'] ??= await _geoTagService.captureGeoTag();
        // Mark as completed before writing. We must not call update() after set()
        // because material_requests updates are admin-only in Firestore rules.
        req['syncStatus'] = AppConstants.syncStatusCompleted;
        req['syncedAt'] ??= DateTime.now().toIso8601String();
        await _hiveService.saveMaterialRequest(id, req);

        await _firebaseService
            .projectsCollection
            .doc(projectId)
            .collection('material_requests')
            .doc(id)
            .set(req);

        final priority = (req['priority'] ?? 'normal').toString().toLowerCase();
        final isUrgent = priority == 'urgent';
        final materialName = (req['materialName'] ?? req['subject'] ?? 'Material')
            .toString();
        final qty = req['requestedQuantity']?.toString() ?? '';
        final unit = (req['unit'] ?? '').toString();
        final qtyLabel = [
          if (qty.isNotEmpty) qty,
          if (unit.isNotEmpty) unit,
        ].join(' ');
        final projectLabel = (req['projectName'] ?? projectId).toString();
        final title = isUrgent
            ? 'URGENT material request'
            : 'New material request';
        final message = qtyLabel.isEmpty
            ? '$materialName requested for $projectLabel'
            : '$materialName ($qtyLabel) requested for $projectLabel'
                '${isUrgent ? ' — buy first' : ''}';

        Future<void> writeRequestNotification({
          required String notifId,
          required String audienceRole,
          required String userId,
        }) {
          return _firebaseService.notificationsCollection.doc(notifId).set({
            'id': notifId,
            'type': AppConstants.notificationMaterialRequest,
            'audienceRole': audienceRole,
            'title': title,
            'message': message,
            'priority': priority,
            'projectId': projectId,
            'projectName': projectLabel,
            'materialRequestId': id,
            'materialName': materialName,
            'requestedQuantity': req['requestedQuantity'],
            'unit': unit,
            'createdAt': DateTime.now().toIso8601String(),
            'userId': userId,
            'createdByUid': req['createdBy'] ?? '',
            'createdByName': req['createdByName'] ?? '',
            'isRead': false,
          });
        }

        await writeRequestNotification(
          notifId: 'notif_material_request_$id',
          audienceRole: 'admin',
          userId: 'admin',
        );
        await writeRequestNotification(
          notifId: 'notif_material_request_purchaser_$id',
          audienceRole: AppConstants.roleMaterials,
          userId: 'materials',
        );

        // Ensure local copy stays consistent
        await _hiveService.saveMaterialRequest(id, req);

        synced++;
      } catch (e) {
        if (_isFirestoreUnreachableError(e)) {
          // Keep pending so it retries later, and propagate up so the user gets
          // the queued message + local notification.
          req['syncStatus'] = AppConstants.syncStatusPending;
          req.remove('syncedAt');
          final id = req['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await _hiveService.saveMaterialRequest(id, req);
          }
          rethrow;
        } else {
          req['syncStatus'] = AppConstants.syncStatusFailed;
          req['lastError'] = e.toString();
          req['lastErrorAt'] = DateTime.now().toIso8601String();
          final id = req['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await _hiveService.saveMaterialRequest(id, req);
          }
          failed++;
        }
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync attendance records
  Future<SyncItemResult> _syncAttendance() async {
    final pendingAttendance = _hiveService.getPendingSyncAttendance();
    int synced = 0;
    int failed = 0;

    for (final attendance in pendingAttendance) {
      try {
        // Update sync status to syncing
        final updatedAttendance = attendance.copyWith(syncStatus: AppConstants.syncStatusSyncing);
        await _hiveService.saveAttendance(updatedAttendance);

        final payload = updatedAttendance.toJson();
        payload['geoTag'] ??= await _geoTagService.captureGeoTag();
        payload['attendanceDateTs'] = Timestamp.fromDate(updatedAttendance.attendanceDate);
        payload['createdAtTs'] = Timestamp.fromDate(updatedAttendance.createdAt);
        payload['updatedAtTs'] = Timestamp.fromDate(updatedAttendance.updatedAt);

        // Upload to Firestore
        await _firebaseService.attendanceCollection(attendance.projectId)
            .doc(attendance.id)
            .set(payload);

        // Update sync status to completed
        final completedAttendance = attendance.copyWith(
          syncStatus: AppConstants.syncStatusCompleted,
          syncedAt: DateTime.now(),
        );
        await _hiveService.saveAttendance(completedAttendance);

        synced++;
      } catch (e) {
        if (_isFirestoreUnreachableError(e)) {
          final pending = attendance.copyWith(syncStatus: AppConstants.syncStatusPending);
          await _hiveService.saveAttendance(pending);
          rethrow;
        } else {
          final failedAttendance =
              attendance.copyWith(syncStatus: AppConstants.syncStatusFailed);
          await _hiveService.saveAttendance(failedAttendance);
          failed++;
        }
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync material usage
  Future<SyncItemResult> _syncMaterialUsage() async {
    final usageItems = _hiveService
        .getAllMaterialUsage()
        .where((u) {
          final status = (u['syncStatus']?.toString() ?? '').toLowerCase();
          return status == AppConstants.syncStatusPending ||
              status == AppConstants.syncStatusFailed;
        })
        .toList();
    if (usageItems.isEmpty) {
      return SyncItemResult(synced: 0, failed: 0);
    }

    int synced = 0;
    int failed = 0;

    for (final usage in usageItems) {
      try {
        final projectId = usage['projectId']?.toString();
        final reportId = usage['reportId']?.toString();
        final id = usage['id']?.toString();
        if (projectId == null || reportId == null || id == null) {
          continue;
        }

        final inventoryItemId = usage['inventoryItemId']?.toString();
        final quantityRaw = usage['quantity'];
        final usedQuantity = quantityRaw is num
            ? quantityRaw.toDouble()
            : double.tryParse(quantityRaw?.toString() ?? '0') ?? 0.0;

        usage['geoTag'] ??= await _geoTagService.captureGeoTag();
        await _hiveService.saveMaterialUsage(id, usage);

        // Upload to Firestore
        await _firebaseService
            .materialUsageCollection(projectId, reportId)
            .doc(id)
            .set(usage);

        // Best-effort: decrement inventory stock when usage is linked to an
        // inventory item.
        if (inventoryItemId != null &&
            inventoryItemId.isNotEmpty &&
            usedQuantity > 0) {
          try {
            await _firebaseService.firestore.runTransaction((tx) async {
              final invRef = _firebaseService
                  .materialInventoryCollection(projectId)
                  .doc(inventoryItemId);
              final invSnap = await tx.get(invRef);
              if (!invSnap.exists) return;

              final invData =
                  (invSnap.data() as Map?)?.cast<String, dynamic>() ??
                      <String, dynamic>{};
              final stockRaw = invData['stock'];
              final currentStock = stockRaw is num
                  ? stockRaw.toDouble()
                  : double.tryParse(stockRaw?.toString() ?? '0') ?? 0.0;

              final newStock =
                  (currentStock - usedQuantity).clamp(0.0, double.infinity);
              tx.update(invRef, {
                'stock': newStock,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            });
          } catch (_) {
            // Ignore inventory update errors; usage upload already succeeded.
          }
        }

        // Update sync status to completed
        usage['syncStatus'] = AppConstants.syncStatusCompleted;
        usage['syncedAt'] = DateTime.now().toIso8601String();
        await _hiveService.saveMaterialUsage(id, usage);

        // Keep Firestore in sync with local status so Admin sees correct status.
        await _firebaseService
            .materialUsageCollection(projectId, reportId)
            .doc(id)
            .update({
          'syncStatus': AppConstants.syncStatusCompleted,
          'syncedAt': usage['syncedAt'],
        });

        synced++;
      } catch (e) {
        if (_isFirestoreUnreachableError(e)) {
          usage['syncStatus'] = AppConstants.syncStatusPending;
          final id = usage['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await _hiveService.saveMaterialUsage(id, usage);
          }
          rethrow;
        } else {
          usage['syncStatus'] = AppConstants.syncStatusFailed;
          final id = usage['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await _hiveService.saveMaterialUsage(id, usage);
          }
          failed++;
        }
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync deliveries
  Future<SyncItemResult> _syncDeliveries() async {
    final allDeliveries = _hiveService.getAllDeliveries();
    final pendingDeliveries = allDeliveries
        .where((item) => item['syncStatus'] == AppConstants.syncStatusPending)
        .toList();

    int synced = 0;
    int failed = 0;

    for (final delivery in pendingDeliveries) {
      try {
        final id = delivery['id'] as String;
        final projectId = delivery['projectId'] as String;

        // Update sync status
        delivery['syncStatus'] = AppConstants.syncStatusSyncing;
        await _hiveService.saveDelivery(id, delivery);

        // Upload to Firestore
        await _firebaseService.deliveriesCollection(projectId)
            .doc(id)
            .set(delivery);

        // Update sync status to completed
        delivery['syncStatus'] = AppConstants.syncStatusCompleted;
        delivery['syncedAt'] = DateTime.now().toIso8601String();
        await _hiveService.saveDelivery(id, delivery);

        synced++;
      } catch (e) {
        // Update sync status to failed
        delivery['syncStatus'] = AppConstants.syncStatusFailed;
        await _hiveService.saveDelivery(delivery['id'], delivery);
        failed++;
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync generic queue items
  Future<SyncItemResult> _syncQueueItems() async {
    final pendingItems = _hiveService.getPendingSyncItems();
    int synced = 0;
    int failed = 0;

    for (final item in pendingItems) {
      try {
        final id = item['id'] as String;
        final type = item['type'] as String;
        final data = item['data'] as Map<String, dynamic>;

        // Update sync status
        await _hiveService.updateSyncQueueItemStatus(id, AppConstants.syncStatusSyncing);

        // Process based on type
        await _processSyncQueueItem(type, data);

        // Remove from sync queue
        await _hiveService.removeSyncQueueItem(id);

        synced++;
      } catch (e) {
        // Update sync status to failed
        await _hiveService.updateSyncQueueItemStatus(item['id'], AppConstants.syncStatusFailed);
        failed++;
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Process individual sync queue item
  Future<void> _processSyncQueueItem(String type, Map<String, dynamic> data) async {
    switch (type) {
      case 'notification':
        await _firebaseService.notificationsCollection.add(data);
        break;
      case 'history_log':
        final projectId = data['projectId'] as String;
        await _firebaseService.historyCollection(projectId).add(data);
        break;
      case 'audit_log':
        await _firebaseService.auditLogsCollection.add(data);
        break;
      case 'material_inventory_upsert':
        {
          final projectId = (data['projectId'] ?? '').toString();
          final docId = (data['docId'] ?? '').toString();
          final payload =
              (data['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          if (projectId.isEmpty || docId.isEmpty) {
            throw Exception('material_inventory_upsert missing projectId/docId');
          }
          await _firebaseService
              .materialInventoryCollection(projectId)
              .doc(docId)
              .set(payload, SetOptions(merge: true));
          break;
        }
      case 'material_allocation_upsert':
        {
          final projectId = (data['projectId'] ?? '').toString();
          final docId = (data['docId'] ?? '').toString();
          final payload =
              (data['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          if (projectId.isEmpty || docId.isEmpty) {
            throw Exception('material_allocation_upsert missing projectId/docId');
          }
          await _firebaseService
              .materialAllocationsCollection(projectId)
              .doc(docId)
              .set(payload, SetOptions(merge: true));
          break;
        }
      default:
        throw Exception('Unknown sync queue item type: $type');
    }
  }

  // Add item to sync queue
  Future<void> addToSyncQueue(String type, Map<String, dynamic> data) async {
    final id = _uuid.v4();
    await _hiveService.addToSyncQueue(id, {
      'id': id,
      'type': type,
      'data': data,
    });
  }

  // Force sync specific item
  Future<bool> forceSyncItem(String itemId, String itemType) async {
    if (!await isOnline()) return false;

    try {
      switch (itemType) {
        case 'daily_report':
          final report = _hiveService.getDailyReport(itemId);
          if (report != null) {
            await _firebaseService.dailyReportsCollection(report.projectId)
                .doc(report.id)
                .set(report.toJson());
            
            final updatedReport = report.copyWith(
              syncStatus: AppConstants.syncStatusCompleted,
              syncedAt: DateTime.now(),
            );
            await _hiveService.saveDailyReport(updatedReport);
          }
          break;
        case 'attendance':
          final attendance = _hiveService.getAttendance(itemId);
          if (attendance != null) {
            await _firebaseService.attendanceCollection(attendance.projectId)
                .doc(attendance.id)
                .set(attendance.toJson());
            
            final updatedAttendance = attendance.copyWith(
              syncStatus: AppConstants.syncStatusCompleted,
              syncedAt: DateTime.now(),
            );
            await _hiveService.saveAttendance(updatedAttendance);
          }
          break;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get sync statistics
  SyncStats getSyncStats() {
    final pendingReports = _hiveService.getPendingSyncReports().length;
    final pendingAttendance = _hiveService.getPendingSyncAttendance().length;
    final pendingQueue = _hiveService.getPendingSyncItems().length;

    return SyncStats(
      pendingDailyReports: pendingReports,
      pendingAttendance: pendingAttendance,
      pendingQueueItems: pendingQueue,
      totalPending: pendingReports + pendingAttendance + pendingQueue,
      isSyncing: _isSyncing,
    );
  }

  // Dispose
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

// Data classes
enum SyncStatus { idle, syncing, completed, failed }

class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int failedCount;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.failedCount = 0,
  });
}

class SyncItemResult {
  final int synced;
  final int failed;

  SyncItemResult({required this.synced, required this.failed});
}

class SyncStats {
  final int pendingDailyReports;
  final int pendingAttendance;
  final int pendingQueueItems;
  final int totalPending;
  final bool isSyncing;

  SyncStats({
    required this.pendingDailyReports,
    required this.pendingAttendance,
    required this.pendingQueueItems,
    required this.totalPending,
    required this.isSyncing,
  });
}
