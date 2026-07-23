import 'hive_service.dart';

/// Persistent site worker roster (survives weekly checklist resets).
class RegisteredWorker {
  const RegisteredWorker({
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.rate,
    required this.registeredAt,
  });

  final String workerId;
  final String workerName;
  final String position;
  final double rate;
  final DateTime registeredAt;

  static String idFromName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  factory RegisteredWorker.fromMap(Map<String, dynamic> map) {
    return RegisteredWorker(
      workerId: (map['workerId'] ?? '').toString(),
      workerName: (map['workerName'] ?? '').toString(),
      position: (map['position'] ?? 'Laborer').toString(),
      rate: map['rate'] is num
          ? (map['rate'] as num).toDouble()
          : double.tryParse(map['rate']?.toString() ?? '') ?? 0,
      registeredAt: DateTime.tryParse(map['registeredAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'workerId': workerId,
        'workerName': workerName,
        'position': position,
        'rate': rate,
        'registeredAt': registeredAt.toIso8601String(),
      };
}

class AttendanceWorkerRegistryService {
  AttendanceWorkerRegistryService._();
  static final instance = AttendanceWorkerRegistryService._();

  static String _rosterKey(String projectId) => 'attendance_roster_$projectId';

  List<RegisteredWorker> loadRoster(String projectId) {
    if (projectId.isEmpty) return [];
    final raw = HiveService.instance.getSetting<List>(_rosterKey(projectId));
    if (raw == null) return _migrateLegacyRoster(projectId);
    return raw
        .whereType<Map>()
        .map((e) => RegisteredWorker.fromMap(e.cast<String, dynamic>()))
        .where((w) => w.workerName.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.workerName.toLowerCase().compareTo(b.workerName.toLowerCase()));
  }

  /// Pull workers from old fingerprint meta + past attendance if roster empty.
  List<RegisteredWorker> _migrateLegacyRoster(String projectId) {
    final out = <String, RegisteredWorker>{};
    final meta = HiveService.instance
        .getSetting<Map>('fingerprint_registered_workers_meta')
        ?.cast<String, dynamic>();
    meta?.forEach((name, dateStr) {
      final displayName = name.replaceAll('_', ' ');
      final id = RegisteredWorker.idFromName(displayName);
      out[id] = RegisteredWorker(
        workerId: id,
        workerName: displayName[0].toUpperCase() + displayName.substring(1),
        position: 'Laborer',
        rate: 450,
        registeredAt: DateTime.tryParse(dateStr.toString()) ?? DateTime.now(),
      );
    });

    for (final att in HiveService.instance.getAllAttendance()) {
      if (att.projectId != projectId) continue;
      for (final r in att.records) {
        final name = r.workerName.trim();
        if (name.isEmpty) continue;
        final id = r.workerId.trim().isNotEmpty ? r.workerId : RegisteredWorker.idFromName(name);
        out.putIfAbsent(
          id.toLowerCase(),
          () => RegisteredWorker(
            workerId: id,
            workerName: name,
            position: r.position.trim().isEmpty ? 'Laborer' : r.position.trim(),
            rate: r.rate,
            registeredAt: att.attendanceDate,
          ),
        );
      }
    }

    final list = out.values.toList();
    if (list.isNotEmpty) {
      saveRoster(projectId, list);
    }
    return list;
  }

  Future<void> saveRoster(String projectId, List<RegisteredWorker> workers) async {
    await HiveService.instance.saveSetting(
      _rosterKey(projectId),
      workers.map((w) => w.toMap()).toList(),
    );
  }

  Future<RegisteredWorker> registerWorker({
    required String projectId,
    required String workerName,
    required String position,
    required double rate,
  }) async {
    final name = workerName.trim();
    final id = RegisteredWorker.idFromName(name);
    final roster = loadRoster(projectId);
    final existing = roster.indexWhere((w) => w.workerId.toLowerCase() == id.toLowerCase());

    final worker = RegisteredWorker(
      workerId: id,
      workerName: name,
      position: position.trim().isEmpty ? 'Laborer' : position.trim(),
      rate: rate,
      registeredAt: existing >= 0 ? roster[existing].registeredAt : DateTime.now(),
    );

    if (existing >= 0) {
      roster[existing] = worker;
    } else {
      roster.add(worker);
    }
    roster.sort((a, b) => a.workerName.toLowerCase().compareTo(b.workerName.toLowerCase()));
    await saveRoster(projectId, roster);
    return worker;
  }

  Future<void> removeWorker(String projectId, String workerId) async {
    final roster = loadRoster(projectId)
      ..removeWhere((w) => w.workerId.toLowerCase() == workerId.toLowerCase());
    await saveRoster(projectId, roster);
  }

  Map<String, DateTime> registeredAtMap(String projectId) {
    return {
      for (final w in loadRoster(projectId)) w.workerId.toLowerCase(): DateTime(
        w.registeredAt.year,
        w.registeredAt.month,
        w.registeredAt.day,
      ),
    };
  }
}
