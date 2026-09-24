import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/project_model.dart';
import '../models/daily_report_model.dart';
import '../models/attendance_model.dart';
import '../models/payroll_model.dart';
import '../core/constants/app_constants.dart';
import '../core/security/secure_log.dart';
import '../core/security/secure_storage_service.dart';

class HiveService {
  static HiveService? _instance;
  static HiveService get instance => _instance ??= HiveService._();
  HiveService._();

  static HiveAesCipher? _cipher;

  /// Initialize Hive with AES encryption (key from platform secure storage).
  static Future<void> initialize() async {
    await Hive.initFlutter();

    try {
      final key = await SecureStorageService.instance.getOrCreateHiveKey();
      _cipher = HiveAesCipher(key);
    } catch (e) {
      SecureLog.e(e, null, 'HiveService');
      // Fail closed on encryption key — do not open plaintext boxes.
      rethrow;
    }

    // Register adapters
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(ProjectModelAdapter());
    Hive.registerAdapter(DailyReportModelAdapter());
    Hive.registerAdapter(WorkAccomplishmentAdapter());
    Hive.registerAdapter(AttendanceModelAdapter());
    Hive.registerAdapter(AttendanceRecordAdapter());
    Hive.registerAdapter(PayrollModelAdapter());
    Hive.registerAdapter(PayrollItemAdapter());

    await _openBoxes();
  }

  static Future<void> _openBoxes() async {
    final cipher = _cipher;
    if (cipher == null) {
      throw StateError('Hive encryption cipher not initialized');
    }

    // Encrypted box names (v2) — avoids clash with legacy plaintext boxes.
    await _openEncryptedBox<UserModel>(AppConstants.userBox, cipher);
    await _openEncryptedBox<DailyReportModel>(
      AppConstants.dailyReportsBox,
      cipher,
    );
    await _openEncryptedBox<AttendanceModel>(
      AppConstants.attendanceBox,
      cipher,
    );
    await _openEncryptedBox<Map>(AppConstants.materialUsageBox, cipher);
    await _openEncryptedBox<Map>(AppConstants.materialInventoryBox, cipher);
    await _openEncryptedBox<Map>(AppConstants.materialRequestsBox, cipher);
    await _openEncryptedBox<Map>(AppConstants.deliveriesBox, cipher);
    await _openEncryptedBox<Map>(AppConstants.syncQueueBox, cipher);
    await _openEncryptedBox<Map>(AppConstants.settingsBox, cipher);
  }

  static String _encName(String name) => '${name}_enc_v2';

  static Future<void> _openEncryptedBox<T>(
    String logicalName,
    HiveAesCipher cipher,
  ) async {
    final encName = _encName(logicalName);
    if (!Hive.isBoxOpen(encName)) {
      await Hive.openBox<T>(encName, encryptionCipher: cipher);
    }

    // Best-effort one-time migrate from legacy plaintext box, then wipe it.
    try {
      if (await Hive.boxExists(logicalName)) {
        final legacy = await Hive.openBox<T>(logicalName);
        final enc = Hive.box<T>(encName);
        if (enc.isEmpty && legacy.isNotEmpty) {
          for (final key in legacy.keys) {
            final value = legacy.get(key);
            if (value != null) await enc.put(key, value);
          }
        }
        await legacy.clear();
        await legacy.close();
        await Hive.deleteBoxFromDisk(logicalName);
      }
    } catch (e) {
      SecureLog.d('Legacy Hive migrate skipped for $logicalName: $e');
    }
  }

  // Box getters
  Box<UserModel> get userBox =>
      Hive.box<UserModel>(_encName(AppConstants.userBox));
  Box<DailyReportModel> get dailyReportsBox =>
      Hive.box<DailyReportModel>(_encName(AppConstants.dailyReportsBox));
  Box<AttendanceModel> get attendanceBox =>
      Hive.box<AttendanceModel>(_encName(AppConstants.attendanceBox));
  Box<Map> get materialUsageBox =>
      Hive.box<Map>(_encName(AppConstants.materialUsageBox));
  Box<Map> get materialInventoryBox =>
      Hive.box<Map>(_encName(AppConstants.materialInventoryBox));
  Box<Map> get materialRequestsBox =>
      Hive.box<Map>(_encName(AppConstants.materialRequestsBox));
  Box<Map> get deliveriesBox =>
      Hive.box<Map>(_encName(AppConstants.deliveriesBox));
  Box<Map> get syncQueueBox =>
      Hive.box<Map>(_encName(AppConstants.syncQueueBox));
  Box<Map> get settingsBox =>
      Hive.box<Map>(_encName(AppConstants.settingsBox));


  // User operations
  Future<void> saveUser(UserModel user) async {
    await userBox.put('current_user', user);
  }

  UserModel? getCurrentUser() {
    return userBox.get('current_user');
  }

  Future<void> clearUser() async {
    await userBox.delete('current_user');
  }

  // Daily Reports operations
  Future<void> saveDailyReport(DailyReportModel report) async {
    await dailyReportsBox.put(report.id, report);
  }

  DailyReportModel? getDailyReport(String id) {
    return dailyReportsBox.get(id);
  }

  List<DailyReportModel> getAllDailyReports() {
    return dailyReportsBox.values.toList();
  }

  // Daily Reports filtered helpers
  List<DailyReportModel> getDailyReportsByReporter(String reporterId) {
    return dailyReportsBox.values
        .where((report) => report.reporterId == reporterId)
        .toList();
  }

  List<DailyReportModel> getDailyReportsByProject(String projectId) {
    return dailyReportsBox.values
        .where((report) => report.projectId == projectId)
        .toList();
  }

  List<DailyReportModel> getPendingSyncReports() {
    return dailyReportsBox.values
        .where((report) => report.syncStatus == AppConstants.syncStatusPending)
        .toList();
  }

  List<DailyReportModel> getPendingSyncReportsForProject(String projectId) {
    return dailyReportsBox.values
        .where((report) =>
            report.projectId == projectId &&
            report.syncStatus == AppConstants.syncStatusPending)
        .toList();
  }

  Future<void> deleteDailyReport(String id) async {
    await dailyReportsBox.delete(id);
  }

  // Attendance operations
  Future<void> saveAttendance(AttendanceModel attendance) async {
    await attendanceBox.put(attendance.id, attendance);
  }

  AttendanceModel? getAttendance(String id) {
    return attendanceBox.get(id);
  }

  List<AttendanceModel> getAllAttendance() {
    return attendanceBox.values.toList();
  }

  // Attendance filtered helpers
  List<AttendanceModel> getAttendanceByRecorder(String recorderId) {
    return attendanceBox.values
        .where((attendance) => attendance.recorderId == recorderId)
        .toList();
  }

  List<AttendanceModel> getAttendanceByProject(String projectId) {
    return attendanceBox.values
        .where((attendance) => attendance.projectId == projectId)
        .toList();
  }

  List<AttendanceModel> getPendingSyncAttendance() {
    return attendanceBox.values
        .where((attendance) => attendance.syncStatus == AppConstants.syncStatusPending)
        .toList();
  }

  List<AttendanceModel> getPendingSyncAttendanceForProject(String projectId) {
    return attendanceBox.values
        .where((attendance) =>
            attendance.projectId == projectId &&
            attendance.syncStatus == AppConstants.syncStatusPending)
        .toList();
  }

  Future<void> deleteAttendance(String id) async {
    await attendanceBox.delete(id);
  }

  // Material Usage operations
  Future<void> saveMaterialUsage(String id, Map<String, dynamic> data) async {
    await materialUsageBox.put(id, data);
  }

  Map<String, dynamic>? getMaterialUsage(String id) {
    return materialUsageBox.get(id)?.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> getAllMaterialUsage() {
    return materialUsageBox.values
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> deleteMaterialUsage(String id) async {
    await materialUsageBox.delete(id);
  }

  Future<void> saveMaterialInventory(String id, Map<String, dynamic> data) async {
    await materialInventoryBox.put(id, data);
  }

  Map<String, dynamic>? getMaterialInventory(String id) {
    return materialInventoryBox.get(id)?.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> getAllMaterialInventory() {
    final box = materialInventoryBox;
    final List<Map<String, dynamic>> items = [];

    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;

      final map = raw.cast<String, dynamic>();
      final currentId = (map['id'] ?? '').toString();
      if (currentId.isEmpty) {
        map['id'] = key.toString();
      }
      items.add(map);
    }

    return items;
  }

  Future<void> deleteMaterialInventory(String id) async {
    await materialInventoryBox.delete(id);
  }

  // Deliveries operations
  Future<void> saveDelivery(String id, Map<String, dynamic> data) async {
    await deliveriesBox.put(id, data);
  }

  Map<String, dynamic>? getDelivery(String id) {
    return deliveriesBox.get(id)?.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> getAllDeliveries() {
    return deliveriesBox.values
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> deleteDelivery(String id) async {
    await deliveriesBox.delete(id);
  }

  // Material Requests operations
  Future<void> saveMaterialRequest(String id, Map<String, dynamic> data) async {
    await materialRequestsBox.put(id, data);
  }

  Map<String, dynamic>? getMaterialRequest(String id) {
    return materialRequestsBox.get(id)?.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> getAllMaterialRequests() {
    return materialRequestsBox.values
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> deleteMaterialRequest(String id) async {
    await materialRequestsBox.delete(id);
  }

  // Sync Queue operations
  Future<void> addToSyncQueue(String id, Map<String, dynamic> data) async {
    await syncQueueBox.put(id, {
      ...data,
      'addedAt': DateTime.now().toIso8601String(),
      'status': AppConstants.syncStatusPending,
    });
  }

  Map<String, dynamic>? getSyncQueueItem(String id) {
    return syncQueueBox.get(id)?.cast<String, dynamic>();
  }

  List<Map<String, dynamic>> getAllSyncQueueItems() {
    return syncQueueBox.values
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  List<Map<String, dynamic>> getPendingSyncItems() {
    return syncQueueBox.values
        .map((e) => e.cast<String, dynamic>())
        .where((item) => item['status'] == AppConstants.syncStatusPending)
        .toList();
  }

  Future<void> updateSyncQueueItemStatus(String id, String status) async {
    final item = syncQueueBox.get(id);
    if (item != null) {
      final updatedItem = Map<String, dynamic>.from(item);
      updatedItem['status'] = status;
      updatedItem['updatedAt'] = DateTime.now().toIso8601String();
      await syncQueueBox.put(id, updatedItem);
    }
  }

  Future<void> removeSyncQueueItem(String id) async {
    await syncQueueBox.delete(id);
  }

  Future<void> clearSyncQueue() async {
    await syncQueueBox.clear();
  }

  // Settings operations
  Future<void> saveSetting(String key, dynamic value) async {
    await settingsBox.put(key, {'value': value, 'updatedAt': DateTime.now().toIso8601String()});
  }

  T? getSetting<T>(String key) {
    final data = settingsBox.get(key);
    return data != null ? data['value'] as T? : null;
  }

  Future<void> deleteSetting(String key) async {
    await settingsBox.delete(key);
  }

  // Utility methods
  Future<void> clearAllData() async {
    await userBox.clear();
    await dailyReportsBox.clear();
    await attendanceBox.clear();
    await materialUsageBox.clear();
    await materialInventoryBox.clear();
    await deliveriesBox.clear();
    await syncQueueBox.clear();
    await settingsBox.clear();
  }

  Future<void> compactBoxes() async {
    await userBox.compact();
    await dailyReportsBox.compact();
    await attendanceBox.compact();
    await materialUsageBox.compact();
    await materialInventoryBox.compact();
    await deliveriesBox.compact();
    await syncQueueBox.compact();
    await settingsBox.compact();
  }

  Future<void> closeBoxes() async {
    await userBox.close();
    await dailyReportsBox.close();
    await attendanceBox.close();
    await materialUsageBox.close();
    await materialInventoryBox.close();
    await deliveriesBox.close();
    await syncQueueBox.close();
    await settingsBox.close();
  }

  // Statistics
  int get totalDailyReports => dailyReportsBox.length;
  int get totalAttendanceRecords => attendanceBox.length;
  int get totalMaterialUsageRecords => materialUsageBox.length;
  int get totalDeliveryRecords => deliveriesBox.length;
  int get pendingSyncItemsCount => getPendingSyncItems().length;

  Map<String, int> get storageStats => {
    'dailyReports': dailyReportsBox.length,
    'attendance': attendanceBox.length,
    'materialUsage': materialUsageBox.length,
    'materialInventory': materialInventoryBox.length,
    'deliveries': deliveriesBox.length,
    'syncQueue': syncQueueBox.length,
    'settings': settingsBox.length,
  };
}
