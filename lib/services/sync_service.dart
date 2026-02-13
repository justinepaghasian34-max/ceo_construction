import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import 'firebase_service.dart';
import 'hive_service.dart';

class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();
  SyncService._();

  final FirebaseService _firebaseService = FirebaseService.instance;
  final HiveService _hiveService = HiveService.instance;
  final Connectivity _connectivity = Connectivity();
  final Uuid _uuid = const Uuid();

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
        // Update sync status to syncing
        final updatedReport = report.copyWith(syncStatus: AppConstants.syncStatusSyncing);
        await _hiveService.saveDailyReport(updatedReport);

        // Upload to Firestore
        await _firebaseService.dailyReportsCollection(report.projectId)
            .doc(report.id)
            .set(report.toJson());

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

        // Upload to Firestore
        await _firebaseService.attendanceCollection(attendance.projectId)
            .doc(attendance.id)
            .set(attendance.toJson());

        // Update sync status to completed
        final completedAttendance = attendance.copyWith(
          syncStatus: AppConstants.syncStatusCompleted,
          syncedAt: DateTime.now(),
        );
        await _hiveService.saveAttendance(completedAttendance);

        synced++;
      } catch (e) {
        // Update sync status to failed
        final failedAttendance = attendance.copyWith(syncStatus: AppConstants.syncStatusFailed);
        await _hiveService.saveAttendance(failedAttendance);
        failed++;
      }
    }

    return SyncItemResult(synced: synced, failed: failed);
  }

  // Sync material usage
  Future<SyncItemResult> _syncMaterialUsage() async {
    final allMaterialUsage = _hiveService.getAllMaterialUsage();
    final pendingMaterialUsage = allMaterialUsage
        .where((item) => item['syncStatus'] == AppConstants.syncStatusPending)
        .toList();

    int synced = 0;
    int failed = 0;

    for (final usage in pendingMaterialUsage) {
      try {
        final id = usage['id'] as String;
        final projectId = usage['projectId'] as String;
        final reportId = usage['reportId'] as String;

        // Update sync status
        usage['syncStatus'] = AppConstants.syncStatusSyncing;
        await _hiveService.saveMaterialUsage(id, usage);

        // Upload to Firestore
        await _firebaseService.materialUsageCollection(projectId, reportId)
            .doc(id)
            .set(usage);

        // Update sync status to completed
        usage['syncStatus'] = AppConstants.syncStatusCompleted;
        usage['syncedAt'] = DateTime.now().toIso8601String();
        await _hiveService.saveMaterialUsage(id, usage);

        synced++;
      } catch (e) {
        // Update sync status to failed
        usage['syncStatus'] = AppConstants.syncStatusFailed;
        await _hiveService.saveMaterialUsage(usage['id'], usage);
        failed++;
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
