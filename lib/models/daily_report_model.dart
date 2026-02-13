import 'package:hive/hive.dart';

part 'daily_report_model.g.dart';

@HiveType(typeId: 2)
class DailyReportModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String projectId;

  @HiveField(2)
  String reporterId;

  @HiveField(3)
  DateTime reportDate;

  @HiveField(4)
  String weatherCondition;

  @HiveField(5)
  double temperatureC;

  @HiveField(6)
  List<WorkAccomplishment> workAccomplishments;

  @HiveField(7)
  List<String> issues;

  @HiveField(8)
  List<String> attachmentUrls;

  @HiveField(9)
  String status;

  @HiveField(10)
  String? remarks;

  @HiveField(11)
  DateTime createdAt;

  @HiveField(12)
  DateTime updatedAt;

  @HiveField(13)
  String syncStatus;

  @HiveField(14)
  DateTime? syncedAt;

  DailyReportModel({
    required this.id,
    required this.projectId,
    required this.reporterId,
    required this.reportDate,
    required this.weatherCondition,
    required this.temperatureC,
    required this.workAccomplishments,
    required this.issues,
    required this.attachmentUrls,
    this.status = 'draft',
    this.remarks,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.syncedAt,
  });

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  bool get isPendingSync => syncStatus == 'pending';
  bool get isSyncing => syncStatus == 'syncing';
  bool get isSynced => syncStatus == 'completed';
  bool get hasSyncFailed => syncStatus == 'failed';

  factory DailyReportModel.fromJson(Map<String, dynamic> json) {
    return DailyReportModel(
      id: json['id'] ?? '',
      projectId: json['projectId'] ?? '',
      reporterId: json['reporterId'] ?? '',
      reportDate: DateTime.parse(json['reportDate'] ?? DateTime.now().toIso8601String()),
      weatherCondition: json['weatherCondition'] ?? '',
      temperatureC: (json['temperatureC'] ?? 0).toDouble(),
      workAccomplishments: (json['workAccomplishments'] as List<dynamic>?)
          ?.map((e) => WorkAccomplishment.fromJson(e))
          .toList() ?? [],
      issues: List<String>.from(json['issues'] ?? []),
      attachmentUrls: List<String>.from(json['attachmentUrls'] ?? []),
      status: json['status'] ?? 'draft',
      remarks: json['remarks'],
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
      'reporterId': reporterId,
      'reportDate': reportDate.toIso8601String(),
      'weatherCondition': weatherCondition,
      'temperatureC': temperatureC,
      'workAccomplishments': workAccomplishments.map((e) => e.toJson()).toList(),
      'issues': issues,
      'attachmentUrls': attachmentUrls,
      'status': status,
      'remarks': remarks,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  DailyReportModel copyWith({
    String? id,
    String? projectId,
    String? reporterId,
    DateTime? reportDate,
    String? weatherCondition,
    double? temperatureC,
    List<WorkAccomplishment>? workAccomplishments,
    List<String>? issues,
    List<String>? attachmentUrls,
    String? status,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? syncedAt,
  }) {
    return DailyReportModel(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      reporterId: reporterId ?? this.reporterId,
      reportDate: reportDate ?? this.reportDate,
      weatherCondition: weatherCondition ?? this.weatherCondition,
      temperatureC: temperatureC ?? this.temperatureC,
      workAccomplishments: workAccomplishments ?? this.workAccomplishments,
      issues: issues ?? this.issues,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

@HiveType(typeId: 3)
class WorkAccomplishment extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String wbsCode;

  @HiveField(2)
  String description;

  @HiveField(3)
  String unit;

  @HiveField(4)
  double quantityAccomplished;

  @HiveField(5)
  double percentageComplete;

  @HiveField(6)
  String? remarks;

  WorkAccomplishment({
    required this.id,
    required this.wbsCode,
    required this.description,
    required this.unit,
    required this.quantityAccomplished,
    required this.percentageComplete,
    this.remarks,
  });

  factory WorkAccomplishment.fromJson(Map<String, dynamic> json) {
    return WorkAccomplishment(
      id: json['id'] ?? '',
      wbsCode: json['wbsCode'] ?? '',
      description: json['description'] ?? '',
      unit: json['unit'] ?? '',
      quantityAccomplished: (json['quantityAccomplished'] ?? 0).toDouble(),
      percentageComplete: (json['percentageComplete'] ?? 0).toDouble(),
      remarks: json['remarks'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wbsCode': wbsCode,
      'description': description,
      'unit': unit,
      'quantityAccomplished': quantityAccomplished,
      'percentageComplete': percentageComplete,
      'remarks': remarks,
    };
  }

  WorkAccomplishment copyWith({
    String? id,
    String? wbsCode,
    String? description,
    String? unit,
    double? quantityAccomplished,
    double? percentageComplete,
    String? remarks,
  }) {
    return WorkAccomplishment(
      id: id ?? this.id,
      wbsCode: wbsCode ?? this.wbsCode,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      quantityAccomplished: quantityAccomplished ?? this.quantityAccomplished,
      percentageComplete: percentageComplete ?? this.percentageComplete,
      remarks: remarks ?? this.remarks,
    );
  }
}
