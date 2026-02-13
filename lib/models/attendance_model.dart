import 'package:hive/hive.dart';

part 'attendance_model.g.dart';

@HiveType(typeId: 4)
class AttendanceModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String projectId;

  @HiveField(2)
  String recorderId;

  @HiveField(3)
  DateTime attendanceDate;

  @HiveField(4)
  List<AttendanceRecord> records;

  @HiveField(5)
  String status;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;

  @HiveField(8)
  String syncStatus;

  @HiveField(9)
  DateTime? syncedAt;

  AttendanceModel({
    required this.id,
    required this.projectId,
    required this.recorderId,
    required this.attendanceDate,
    required this.records,
    this.status = 'draft',
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.syncedAt,
  });

  int get totalWorkers => records.length;
  int get presentWorkers => records.where((r) => r.isPresent).length;
  int get absentWorkers => records.where((r) => !r.isPresent).length;
  double get attendanceRate => totalWorkers > 0 ? (presentWorkers / totalWorkers) * 100 : 0;

  bool get isPendingSync => syncStatus == 'pending';
  bool get isSynced => syncStatus == 'completed';

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    return AttendanceModel(
      id: json['id'] ?? '',
      projectId: json['projectId'] ?? '',
      recorderId: json['recorderId'] ?? '',
      attendanceDate: DateTime.parse(json['attendanceDate'] ?? DateTime.now().toIso8601String()),
      records: (json['records'] as List<dynamic>?)
          ?.map((e) => AttendanceRecord.fromJson(e))
          .toList() ?? [],
      status: json['status'] ?? 'draft',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      syncStatus: json['syncStatus'] ?? 'pending',
      syncedAt: json['syncedAt'] != null ? DateTime.parse(json['syncedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'recorderId': recorderId,
      'attendanceDate': attendanceDate.toIso8601String(),
      'records': records.map((e) => e.toJson()).toList(),
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  AttendanceModel copyWith({
    String? id,
    String? projectId,
    String? recorderId,
    DateTime? attendanceDate,
    List<AttendanceRecord>? records,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? syncedAt,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      recorderId: recorderId ?? this.recorderId,
      attendanceDate: attendanceDate ?? this.attendanceDate,
      records: records ?? this.records,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

@HiveType(typeId: 5)
class AttendanceRecord extends HiveObject {
  @HiveField(0)
  String workerId;

  @HiveField(1)
  String workerName;

  @HiveField(2)
  String position;

  @HiveField(3)
  bool isPresent;

  @HiveField(4)
  DateTime? timeIn;

  @HiveField(5)
  DateTime? timeOut;

  @HiveField(6)
  double hoursWorked;

  @HiveField(7)
  double overtimeHours;

  @HiveField(8)
  String? remarks;

  @HiveField(9)
  DateTime? amTimeIn;

  @HiveField(10)
  DateTime? amTimeOut;

  @HiveField(11)
  DateTime? pmTimeIn;

  @HiveField(12)
  DateTime? pmTimeOut;

  @HiveField(13)
  String workerType;

  @HiveField(14)
  double rate;

  @HiveField(15)
  bool monPresent;

  @HiveField(16)
  bool tuePresent;

  @HiveField(17)
  bool wedPresent;

  @HiveField(18)
  bool thuPresent;

  @HiveField(19)
  bool friPresent;

  @HiveField(20)
  bool satPresent;

  AttendanceRecord({
    required this.workerId,
    required this.workerName,
    required this.position,
    this.isPresent = false,
    this.timeIn,
    this.timeOut,
    this.hoursWorked = 0.0,
    this.overtimeHours = 0.0,
    this.remarks,
    this.amTimeIn,
    this.amTimeOut,
    this.pmTimeIn,
    this.pmTimeOut,
    this.workerType = 'labor',
    this.rate = 0.0,
    this.monPresent = false,
    this.tuePresent = false,
    this.wedPresent = false,
    this.thuPresent = false,
    this.friPresent = false,
    this.satPresent = false,
  });

  double get totalHours => hoursWorked + overtimeHours;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      workerId: json['workerId'] ?? '',
      workerName: json['workerName'] ?? '',
      position: json['position'] ?? '',
      isPresent: json['isPresent'] ?? false,
      timeIn: json['timeIn'] != null ? DateTime.parse(json['timeIn']) : null,
      timeOut: json['timeOut'] != null ? DateTime.parse(json['timeOut']) : null,
      hoursWorked: (json['hoursWorked'] ?? 0).toDouble(),
      overtimeHours: (json['overtimeHours'] ?? 0).toDouble(),
      remarks: json['remarks'],
      amTimeIn: json['amTimeIn'] != null ? DateTime.parse(json['amTimeIn']) : null,
      amTimeOut: json['amTimeOut'] != null ? DateTime.parse(json['amTimeOut']) : null,
      pmTimeIn: json['pmTimeIn'] != null ? DateTime.parse(json['pmTimeIn']) : null,
      pmTimeOut: json['pmTimeOut'] != null ? DateTime.parse(json['pmTimeOut']) : null,
      workerType: (json['workerType'] ?? 'labor').toString(),
      rate: json['rate'] is num
          ? (json['rate'] as num).toDouble()
          : double.tryParse(json['rate']?.toString() ?? '') ?? 0.0,
      monPresent: json['monPresent'] ?? false,
      tuePresent: json['tuePresent'] ?? false,
      wedPresent: json['wedPresent'] ?? false,
      thuPresent: json['thuPresent'] ?? false,
      friPresent: json['friPresent'] ?? false,
      satPresent: json['satPresent'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workerId': workerId,
      'workerName': workerName,
      'position': position,
      'isPresent': isPresent,
      'timeIn': timeIn?.toIso8601String(),
      'timeOut': timeOut?.toIso8601String(),
      'hoursWorked': hoursWorked,
      'overtimeHours': overtimeHours,
      'remarks': remarks,
      'amTimeIn': amTimeIn?.toIso8601String(),
      'amTimeOut': amTimeOut?.toIso8601String(),
      'pmTimeIn': pmTimeIn?.toIso8601String(),
      'pmTimeOut': pmTimeOut?.toIso8601String(),
      'workerType': workerType,
      'rate': rate,
      'monPresent': monPresent,
      'tuePresent': tuePresent,
      'wedPresent': wedPresent,
      'thuPresent': thuPresent,
      'friPresent': friPresent,
      'satPresent': satPresent,
    };
  }
}
