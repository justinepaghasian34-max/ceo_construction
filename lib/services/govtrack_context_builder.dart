import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firebase_service.dart';
import '../services/hive_service.dart';
import '../services/site_weather_context_service.dart';

/// Assembles a rich, structured project context payload that is sent to
/// the Gemini Cloud Function so GovTrack AI can answer questions about
/// materials, daily reports, attendance, safety, and project status.
///
/// Data sources (in priority order):
///   1. Firestore — live project doc, material inventory sub-collection,
///      recent daily reports, recent attendance, material requests
///   2. Hive — offline-first local cache fallback for every collection
///   3. Weather — SiteWeatherBundle (already loaded separately)
class GovtrackContextBuilder {
  GovtrackContextBuilder._();
  static final instance = GovtrackContextBuilder._();

  /// Builds the full context map for a given project.
  /// All fields are safe-to-serialize (no DateTime objects — converted to ISO strings).
  Future<Map<String, dynamic>> build({
    required String projectId,
    required String? projectName,
    required String? projectLocation,
    SiteWeatherBundle? weatherBundle,
  }) async {
    final hive = HiveService.instance;

    // ── 1. Project document ──────────────────────────────────────────────────
    Map<String, dynamic> projectDoc = {};
    try {
      final snap = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      if (snap.exists) {
        projectDoc = _sanitizeMap(snap.data() as Map<String, dynamic>? ?? {});
      }
    } catch (_) {}

    // ── 2. Material inventory ────────────────────────────────────────────────
    List<Map<String, dynamic>> materials = [];
    try {
      // Firestore sub-collection first
      final snap = await FirebaseService.instance
          .materialInventoryCollection(projectId)
          .orderBy('updatedAt', descending: true)
          .limit(40)
          .get();
      materials = snap.docs
          .map((d) => _sanitizeMap(d.data() as Map<String, dynamic>? ?? {}))
          .toList();
    } catch (_) {
      // Fallback: Hive local inventory filtered by project
      materials = hive
          .getAllMaterialInventory()
          .where((m) =>
              (m['projectId'] ?? '').toString() == projectId ||
              projectId.isEmpty)
          .take(40)
          .toList();
    }

    // ── 3. Material usage ────────────────────────────────────────────────────
    List<Map<String, dynamic>> materialUsage = [];
    try {
      final snap = await FirebaseService.instance
          .materialInventoryCollection(projectId)
          .doc('__usage__')  // Try subcollection path
          .collection('usage_logs')
          .orderBy('date', descending: true)
          .limit(20)
          .get();
      materialUsage = snap.docs
          .map((d) => _sanitizeMap(d.data() as Map<String, dynamic>? ?? {}))
          .toList();
    } catch (_) {
      materialUsage = hive
          .getAllMaterialUsage()
          .where((m) =>
              (m['projectId'] ?? '').toString() == projectId ||
              projectId.isEmpty)
          .take(20)
          .toList();
    }

    // ── 4. Material requests ─────────────────────────────────────────────────
    List<Map<String, dynamic>> materialRequests = [];
    try {
      final snap = await FirebaseService.instance.firestore
          .collection('material_requests')
          .where('projectId', isEqualTo: projectId)
          .orderBy('createdAt', descending: true)
          .limit(15)
          .get();
      materialRequests = snap.docs
          .map((d) => _sanitizeMap(d.data()))
          .toList();
    } catch (_) {
      materialRequests = hive
          .getAllMaterialRequests()
          .where((r) =>
              (r['projectId'] ?? '').toString() == projectId ||
              projectId.isEmpty)
          .take(15)
          .toList();
    }

    // ── 5. Deliveries ────────────────────────────────────────────────────────
    List<Map<String, dynamic>> deliveries = [];
    try {
      final snap = await FirebaseService.instance.firestore
          .collection('deliveries')
          .where('projectId', isEqualTo: projectId)
          .orderBy('deliveryDate', descending: true)
          .limit(15)
          .get();
      deliveries = snap.docs
          .map((d) => _sanitizeMap(d.data()))
          .toList();
    } catch (_) {
      deliveries = hive
          .getAllDeliveries()
          .where((d) =>
              (d['projectId'] ?? '').toString() == projectId ||
              projectId.isEmpty)
          .take(15)
          .toList();
    }

    // ── 6. Daily reports ─────────────────────────────────────────────────────
    List<Map<String, dynamic>> dailyReports = [];
    try {
      final snap = await FirebaseService.instance
          .dailyReportsCollection(projectId)
          .orderBy('date', descending: true)
          .limit(10)
          .get();
      dailyReports = snap.docs
          .map((d) => _sanitizeMap(d.data() as Map<String, dynamic>? ?? {}))
          .toList();
    } catch (_) {
      dailyReports = hive
          .getDailyReportsByProject(projectId)
          .take(10)
          .map((r) => {
                'date': r.reportDate.toIso8601String(),
                'reporterId': r.reporterId,
                'projectId': r.projectId,
                'status': r.status,
                'weatherCondition': r.weatherCondition,
                'temperatureC': r.temperatureC,
                'workAccomplishments': r.workAccomplishments
                    .map((w) => {
                          'description': w.description,
                          'quantityAccomplished': w.quantityAccomplished,
                          'percentageComplete': w.percentageComplete,
                          'unit': w.unit,
                          'wbsCode': w.wbsCode,
                        })
                    .toList(),
                'issues': r.issues,
                'remarks': r.remarks ?? '',
                'syncStatus': r.syncStatus,
              })
          .toList();
    }

    // ── 7. Attendance ────────────────────────────────────────────────────────
    List<Map<String, dynamic>> attendance = [];
    try {
      final snap = await FirebaseService.instance
          .attendanceCollection(projectId)
          .orderBy('date', descending: true)
          .limit(10)
          .get();
      attendance = snap.docs
          .map((d) => _sanitizeMap(d.data() as Map<String, dynamic>? ?? {}))
          .toList();
    } catch (_) {
      attendance = hive
          .getAttendanceByProject(projectId)
          .take(10)
          .map((a) => {
                'date': a.attendanceDate.toIso8601String(),
                'projectId': a.projectId,
                'recorderId': a.recorderId,
                'status': a.status,
                'workers': a.records
                    .map((r) => {
                          'name': r.workerName,
                          'position': r.position,
                          'isPresent': r.isPresent,
                          'status': r.isPresent ? 'present' : 'absent',
                          'hoursWorked': r.hoursWorked,
                          'timeIn': r.timeIn?.toIso8601String(),
                          'timeOut': r.timeOut?.toIso8601String(),
                        })
                    .toList(),
              })
          .toList();
    }

    // ── 8. Issues / defects ──────────────────────────────────────────────────
    List<Map<String, dynamic>> issues = [];
    try {
      final snap = await FirebaseService.instance.firestore
          .collection('issues')
          .where('projectId', isEqualTo: projectId)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      issues = snap.docs.map((d) => _sanitizeMap(d.data())).toList();
    } catch (_) {}

    // ── 9. Latest AI progress report ─────────────────────────────────────────
    Map<String, dynamic>? latestProgress;
    try {
      final snap = await FirebaseService.instance.aiAnalysisCollection
          .where('projectId', isEqualTo: projectId)
          .where('kind', isEqualTo: 'govtrack_progress_report')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        latestProgress =
            _sanitizeMap(snap.docs.first.data() as Map<String, dynamic>? ?? {});
      }
    } catch (_) {}

    // ── 10. Safety incidents (if collection exists) ───────────────────────────
    List<Map<String, dynamic>> safetyIncidents = [];
    try {
      final snap = await FirebaseService.instance.firestore
          .collection('safety_incidents')
          .where('projectId', isEqualTo: projectId)
          .orderBy('date', descending: true)
          .limit(10)
          .get();
      safetyIncidents = snap.docs.map((d) => _sanitizeMap(d.data())).toList();
    } catch (_) {}

    // ── Assemble ──────────────────────────────────────────────────────────────
    final payload = <String, dynamic>{
      'projectId': projectId,
      'projectName': projectName ?? projectDoc['name'] ?? 'Unknown Project',
      'projectLocation':
          projectLocation ?? projectDoc['location'] ?? '',
      'projectStatus': projectDoc['status'] ?? 'unknown',
      'progressPercentage':
          projectDoc['progressPercentage'] ?? projectDoc['progress'] ?? 0,
      'contractAmount': projectDoc['contractAmount'] ?? 0,
      'startDate': projectDoc['startDate'] ?? '',
      'endDate': projectDoc['endDate'] ?? '',
      'projectManager': projectDoc['projectManager'] ?? '',
      'siteManagerName': projectDoc['siteManagerName'] ?? '',
      'description': projectDoc['description'] ?? '',

      // Materials
      'materialInventory': materials,
      'materialUsage': materialUsage,
      'materialRequests': materialRequests,
      'deliveries': deliveries,

      // Work records
      'recentDailyReports': dailyReports,
      'recentAttendance': attendance,

      // Safety & issues
      'issues': issues,
      'safetyIncidents': safetyIncidents,

      // AI progress
      if (latestProgress != null) 'latestProgressReport': latestProgress,

      // Summary stats (for quick reference)
      '_summary': {
        'totalMaterials': materials.length,
        'totalDailyReports': dailyReports.length,
        'totalAttendanceRecords': attendance.length,
        'totalIssues': issues.length,
        'totalMaterialRequests': materialRequests.length,
        'totalDeliveries': deliveries.length,
        'lowStockItems': _countLowStock(materials),
        'pendingRequests': _countPending(materialRequests),
        'presentWorkersToday': _countTodayPresent(attendance),
      },
    };

    return payload;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Recursively sanitize a Firestore map: convert Timestamps → ISO strings,
  /// GeoPoints → lat/lng map, remove null values.
  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    return map.map((k, v) {
      if (v is Timestamp) return MapEntry(k, v.toDate().toIso8601String());
      if (v is GeoPoint) {
        return MapEntry(k, {'lat': v.latitude, 'lng': v.longitude});
      }
      if (v is Map<String, dynamic>) return MapEntry(k, _sanitizeMap(v));
      if (v is List) return MapEntry(k, _sanitizeList(v));
      return MapEntry(k, v);
    });
  }

  static List<dynamic> _sanitizeList(List<dynamic> list) {
    return list.map((v) {
      if (v is Timestamp) return v.toDate().toIso8601String();
      if (v is Map<String, dynamic>) return _sanitizeMap(v);
      if (v is List) return _sanitizeList(v);
      return v;
    }).toList();
  }

  static int _countLowStock(List<Map<String, dynamic>> materials) {
    return materials.where((m) {
      final qty = (m['quantity'] ?? m['currentStock'] ?? m['stock'] ?? 0);
      final threshold =
          (m['minimumStock'] ?? m['minStock'] ?? m['threshold'] ?? 10);
      final q = qty is num ? qty.toDouble() : double.tryParse(qty.toString()) ?? 0;
      final t = threshold is num
          ? threshold.toDouble()
          : double.tryParse(threshold.toString()) ?? 10;
      return q <= t;
    }).length;
  }

  static int _countPending(List<Map<String, dynamic>> requests) {
    return requests
        .where((r) =>
            (r['status'] ?? '').toString().toLowerCase() == 'pending')
        .length;
  }

  static int _countTodayPresent(List<Map<String, dynamic>> attendance) {
    final today = DateTime.now();
    for (final record in attendance) {
      final dateStr = (record['date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      try {
        final d = DateTime.parse(dateStr);
        if (d.year == today.year &&
            d.month == today.month &&
            d.day == today.day) {
          final workers = record['workers'] as List? ?? [];
          return workers
              .where((w) =>
                  (w as Map?)?['status']?.toString().toLowerCase() ==
                  'present')
              .length;
        }
      } catch (_) {}
    }
    return 0;
  }
}
