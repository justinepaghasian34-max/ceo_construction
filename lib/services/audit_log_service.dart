import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central helper for writing structured audit logs via the
/// `logUserAction` Cloud Function.
///
/// The Cloud Function is responsible for:
/// - Attaching the authenticated user (id/email/role)
/// - Writing to the `audit_logs` collection
/// - Recording server-side timestamp and IP address
class AuditLogService {
  static AuditLogService? _instance;
  static AuditLogService get instance => _instance ??= AuditLogService._();
  AuditLogService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Log a generic user action to the audit trail.
  ///
  /// [action] is a short machine-friendly key, e.g. `user_login`,
  /// `project_created`, `material_request_approved`.
  /// [projectId] is optional and can be null for global actions
  /// like login/logout.
  /// [details] is an optional structured payload with any extra
  /// context you want to record.
  Future<void> logAction({
    required String action,
    String? projectId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final callable = _functions.httpsCallable('logUserAction');
      await callable.call(<String, dynamic>{
        'projectId': projectId,
        'action': action,
        'details': details ?? <String, dynamic>{},
      });
    } catch (e, stack) {
      developer.log(
        'Failed to log audit action: $action  $e',
        name: 'AuditLogService',
        error: e,
        stackTrace: stack,
      );
    }

    // Fallback: write directly to Firestore so the audit trail
    // remains functional even if the Cloud Function is unavailable.
    try {
      await _logDirectlyToFirestore(
        action: action,
        projectId: projectId,
        details: details,
      );
    } catch (fallbackError, fallbackStack) {
      developer.log(
        'Fallback Firestore audit log failed: $fallbackError',
        name: 'AuditLogService',
        error: fallbackError,
        stackTrace: fallbackStack,
      );
    }
  }

  Future<void> _logDirectlyToFirestore({
    required String action,
    String? projectId,
    Map<String, dynamic>? details,
  }) async {
    final user = _auth.currentUser;
    final userId = user?.uid;
    String? userEmail = user?.email;
    String? userRole;

    if (userId != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(userId).get();
        final data = userDoc.data();
        if (data != null) {
          userEmail = (data['email'] ?? userEmail)?.toString();
          userRole = data['role']?.toString();
        }
      } catch (e, stack) {
        developer.log(
          'Failed to load user for fallback audit log: $e',
          name: 'AuditLogService',
          error: e,
          stackTrace: stack,
        );
      }
    }

    await _firestore.collection('audit_logs').add(<String, dynamic>{
      'userId': userId,
      'userEmail': userEmail ?? 'unknown',
      'userRole': userRole ?? 'unknown',
      'projectId': projectId,
      'action': action,
      'details': details ?? <String, dynamic>{},
      'timestamp': FieldValue.serverTimestamp(),
      'ipAddress': null,
    });
  }

  Future<void> logLogin() async {
    await logAction(action: 'user_login');
  }

  Future<void> logLogout() async {
    await logAction(action: 'user_logout');
  }
}
