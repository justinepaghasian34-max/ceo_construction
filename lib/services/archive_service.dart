import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'audit_log_service.dart';
import 'firebase_service.dart';

/// Soft-delete helper for records that must remain available for audit review.
///
/// Archived documents stay in Firestore with `isArchived: true` and metadata
/// about who archived them and when. Sub-collections (reports, materials, etc.)
/// are preserved under the parent document.
class ArchiveService {
  static ArchiveService? _instance;
  static ArchiveService get instance => _instance ??= ArchiveService._();
  ArchiveService._();

  static const String fieldIsArchived = 'isArchived';
  static const String fieldArchivedAt = 'archivedAt';
  static const String fieldArchivedBy = 'archivedBy';
  static const String fieldArchivedByEmail = 'archivedByEmail';
  static const String fieldStatusBeforeArchive = 'statusBeforeArchive';
  static const String fieldRestoredAt = 'restoredAt';
  static const String fieldRestoredBy = 'restoredBy';
  static const String fieldRestoredByEmail = 'restoredByEmail';

  static bool isArchived(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data[fieldIsArchived] == true;
  }

  Map<String, dynamic> _archivePayload({String? previousStatus}) {
    final user = FirebaseAuth.instance.currentUser;
    return {
      fieldIsArchived: true,
      fieldArchivedAt: FieldValue.serverTimestamp(),
      fieldArchivedBy: user?.uid ?? '',
      fieldArchivedByEmail: user?.email ?? '',
      if (previousStatus != null && previousStatus.isNotEmpty)
        fieldStatusBeforeArchive: previousStatus,
    };
  }

  Future<void> _unassignSiteManager(String projectId, String siteManagerId) async {
    if (siteManagerId.isEmpty) return;

    final userRef = FirebaseService.instance.usersCollection.doc(siteManagerId);
    final userSnap = await userRef.get();
    if (!userSnap.exists) return;

    final userData = (userSnap.data() as Map?)?.cast<String, dynamic>() ?? {};
    final assigned = List<dynamic>.from(userData['assignedProjects'] ?? []);
    if (!assigned.contains(projectId)) return;

    assigned.remove(projectId);
    await userRef.update({
      'assignedProjects': assigned,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Archives a project instead of deleting it. All related sub-collections remain.
  Future<void> archiveProject({
    required String projectId,
    required String projectName,
    required String siteManagerId,
    String? previousStatus,
  }) async {
    await _unassignSiteManager(projectId, siteManagerId);

    await FirebaseService.instance.projectsCollection.doc(projectId).update(
      _archivePayload(previousStatus: previousStatus),
    );

    final user = FirebaseAuth.instance.currentUser;
    await AuditLogService.instance.logAction(
      action: 'project_archived',
      projectId: projectId,
      details: {
        'name': projectName,
        'archivedByEmail': user?.email ?? '',
        'retention': 'permanent_for_audit',
      },
    );
  }

  /// Restores a previously archived project back to the active list.
  Future<void> restoreProject({
    required String projectId,
    required String projectName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseService.instance.projectsCollection.doc(projectId).update({
      fieldIsArchived: false,
      fieldRestoredAt: FieldValue.serverTimestamp(),
      fieldRestoredBy: user?.uid ?? '',
      fieldRestoredByEmail: user?.email ?? '',
    });

    await AuditLogService.instance.logAction(
      action: 'project_restored',
      projectId: projectId,
      details: {'name': projectName},
    );
  }

  /// Archives a material template for audit retention.
  Future<void> archiveMaterialTemplate({
    required String templateId,
    required String templateName,
  }) async {
    await FirebaseService.instance.materialTemplatesCollection
        .doc(templateId)
        .update(_archivePayload());

    final user = FirebaseAuth.instance.currentUser;
    await AuditLogService.instance.logAction(
      action: 'material_template_archived',
      details: {
        'templateId': templateId,
        'name': templateName,
        'archivedByEmail': user?.email ?? '',
        'retention': 'permanent_for_audit',
      },
    );
  }

  static String formatArchivedAt(Map<String, dynamic> data) {
    final raw = data[fieldArchivedAt];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    }
    if (dt == null) return 'Unknown date';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
