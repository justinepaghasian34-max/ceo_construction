import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/project_model.dart';
import '../models/daily_report_model.dart';
import '../models/attendance_model.dart';
import '../models/payroll_model.dart';
import '../core/constants/app_constants.dart';

class HiveService {
  static HiveService? _instance;
  static HiveService get instance => _instance ??= HiveService._();
  HiveService._();

  // Initialize Hive
  static Future<void> initialize() async {
    await Hive.initFlutter();
    
    // Register adapters
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(ProjectModelAdapter());
    Hive.registerAdapter(DailyReportModelAdapter());
    Hive.registerAdapter(WorkAccomplishmentAdapter());
    Hive.registerAdapter(AttendanceModelAdapter());
    Hive.registerAdapter(AttendanceRecordAdapter());
    Hive.registerAdapter(PayrollModelAdapter());
    Hive.registerAdapter(PayrollItemAdapter());

    // Open boxes
    await _openBoxes();
  }

  static Future<void> _openBoxes() async {
    await Hive.openBox<UserModel>(AppConstants.userBox);
    await Hive.openBox<DailyReportModel>(AppConstants.dailyReportsBox);
    await Hive.openBox<AttendanceModel>(AppConstants.attendanceBox);
    await Hive.openBox<Map>(AppConstants.materialUsageBox);
    await Hive.openBox<Map>(AppConstants.materialInventoryBox);
    await Hive.openBox<Map>(AppConstants.deliveriesBox);
    await Hive.openBox<Map>(AppConstants.syncQueueBox);
    await Hive.openBox<Map>(AppConstants.settingsBox);
  }

  // Box getters
  Box<UserModel> get userBox => Hive.box<UserModel>(AppConstants.userBox);
  Box<DailyReportModel> get dailyReportsBox => Hive.box<DailyReportModel>(AppConstants.dailyReportsBox);
  Box<AttendanceModel> get attendanceBox => Hive.box<AttendanceModel>(AppConstants.attendanceBox);
  Box<Map> get materialUsageBox => Hive.box<Map>(AppConstants.materialUsageBox);
  Box<Map> get materialInventoryBox => Hive.box<Map>(AppConstants.materialInventoryBox);
  Box<Map> get deliveriesBox => Hive.box<Map>(AppConstants.deliveriesBox);
  Box<Map> get syncQueueBox => Hive.box<Map>(AppConstants.syncQueueBox);
  Box<Map> get settingsBox => Hive.box<Map>(AppConstants.settingsBox);

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
