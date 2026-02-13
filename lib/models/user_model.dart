import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String email;

  @HiveField(2)
  String firstName;

  @HiveField(3)
  String lastName;

  @HiveField(4)
  String role;

  @HiveField(5)
  String? profileImageUrl;

  @HiveField(6)
  String? phoneNumber;

  @HiveField(7)
  String? department;

  @HiveField(8)
  List<String> assignedProjects;

  @HiveField(9)
  bool isActive;

  @HiveField(10)
  DateTime createdAt;

  @HiveField(11)
  DateTime updatedAt;

  @HiveField(12)
  Map<String, dynamic>? permissions;

  UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.profileImageUrl,
    this.phoneNumber,
    this.department,
    required this.assignedProjects,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.permissions,
  });

  String get fullName => '$firstName $lastName';

  String get displayName => fullName.isNotEmpty ? fullName : email;

  bool get isSiteManager => role == 'site_manager';
  bool get isAdmin => role == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      role: json['role'] ?? '',
      profileImageUrl: json['profileImageUrl'],
      phoneNumber: json['phoneNumber'],
      department: json['department'],
      assignedProjects: List<String>.from(json['assignedProjects'] ?? []),
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
      permissions: json['permissions'] != null
          ? Map<String, dynamic>.from(json['permissions'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'role': role,
      'profileImageUrl': profileImageUrl,
      'phoneNumber': phoneNumber,
      'department': department,
      'assignedProjects': assignedProjects,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'permissions': permissions,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    String? role,
    String? profileImageUrl,
    String? phoneNumber,
    String? department,
    List<String>? assignedProjects,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? permissions,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role ?? this.role,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      department: department ?? this.department,
      assignedProjects: assignedProjects ?? this.assignedProjects,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      permissions: permissions ?? this.permissions,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, fullName: $fullName, role: $role)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
