import 'package:hive/hive.dart';

part 'project_model.g.dart';

@HiveType(typeId: 1)
class ProjectModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String description;

  @HiveField(3)
  String location;

  @HiveField(4)
  String contractorName;

  @HiveField(5)
  double contractAmount;

  @HiveField(6)
  DateTime startDate;

  @HiveField(7)
  DateTime endDate;

  @HiveField(8)
  String status;

  @HiveField(9)
  double progressPercentage;

  @HiveField(10)
  String projectManager;

  @HiveField(11)
  List<String> assignedUsers;

  @HiveField(12)
  Map<String, dynamic>? wbsStructure;

  @HiveField(13)
  DateTime createdAt;

  @HiveField(14)
  DateTime updatedAt;

  @HiveField(15)
  bool isActive;

  ProjectModel({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.contractorName,
    required this.contractAmount,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.progressPercentage = 0.0,
    required this.projectManager,
    required this.assignedUsers,
    this.wbsStructure,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  bool get isCompleted => status == 'completed';
  bool get isOngoing => status == 'ongoing';
  bool get isPaused => status == 'paused';
  bool get isDelayed => DateTime.now().isAfter(endDate) && !isCompleted;

  int get daysRemaining {
    if (isCompleted) return 0;
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  double get completionRatio {
    final totalDays = endDate.difference(startDate).inDays;
    final elapsedDays = DateTime.now().difference(startDate).inDays;
    return totalDays > 0 ? (elapsedDays / totalDays).clamp(0.0, 1.0) : 0.0;
  }

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      contractorName: json['contractorName'] ?? '',
      contractAmount: (json['contractAmount'] ?? 0).toDouble(),
      startDate: DateTime.parse(json['startDate'] ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(json['endDate'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'planning',
      progressPercentage: (json['progressPercentage'] ?? 0).toDouble(),
      projectManager: json['projectManager'] ?? '',
      assignedUsers: List<String>.from(json['assignedUsers'] ?? []),
      wbsStructure: json['wbsStructure'] != null ? Map<String, dynamic>.from(json['wbsStructure']) : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'location': location,
      'contractorName': contractorName,
      'contractAmount': contractAmount,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'status': status,
      'progressPercentage': progressPercentage,
      'projectManager': projectManager,
      'assignedUsers': assignedUsers,
      'wbsStructure': wbsStructure,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  ProjectModel copyWith({
    String? id,
    String? name,
    String? description,
    String? location,
    String? contractorName,
    double? contractAmount,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    double? progressPercentage,
    String? projectManager,
    List<String>? assignedUsers,
    Map<String, dynamic>? wbsStructure,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      contractorName: contractorName ?? this.contractorName,
      contractAmount: contractAmount ?? this.contractAmount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      projectManager: projectManager ?? this.projectManager,
      assignedUsers: assignedUsers ?? this.assignedUsers,
      wbsStructure: wbsStructure ?? this.wbsStructure,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'ProjectModel(id: $id, name: $name, status: $status, progress: ${progressPercentage.toStringAsFixed(1)}%)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
