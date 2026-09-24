import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/security/secure_log.dart';
import '../core/security/secure_storage_service.dart';
import '../models/user_model.dart';
import '../utils/password_validator.dart';
import 'archive_service.dart';
import 'audit_log_service.dart';
import 'firebase_service.dart';
import 'hive_service.dart';
import 'session_timeout_service.dart';

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  final FirebaseService _firebaseService = FirebaseService.instance;
  final HiveService _hiveService = HiveService.instance;
  final SecureStorageService _secureStorage = SecureStorageService.instance;

  /// In-memory OTP gate for the current process. Never trust plain Hive alone.
  bool _otpSessionOk = false;

  // Current user stream
  Stream<User?> get authStateChanges => _firebaseService.authStateChanges;

  // Get current Firebase user
  User? get currentFirebaseUser => _firebaseService.auth.currentUser;

  // Get current user model
  UserModel? get currentUser => _hiveService.getCurrentUser();

  bool get isOtpVerified =>
      currentFirebaseUser != null && _otpSessionOk;

  bool get isEmailVerified => currentFirebaseUser?.emailVerified == true;

  /// Short-lived anti-abuse challenge from checkLoginAllowed.
  String? _loginChallenge;

  /// Sync OTP session from Firestore (source of truth) + secure storage.
  Future<void> hydrateOtpSession() async {
    final uid = currentFirebaseUser?.uid;
    if (uid == null) {
      _otpSessionOk = false;
      return;
    }
    try {
      final snap = await _firebaseService.usersCollection.doc(uid).get();
      final raw = snap.data();
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final serverOk = map['otpVerified'] == true;
      _otpSessionOk = serverOk;
      await _secureStorage.setOtpSessionVerified(uid, serverOk);
      // Remove legacy plaintext Hive OTP flag if present.
      try {
        await _hiveService.settingsBox.delete('otp_verified_$uid');
      } catch (_) {}
    } catch (e) {
      SecureLog.d('hydrateOtpSession fallback: $e', tag: 'Auth');
      _otpSessionOk = await _secureStorage.isOtpSessionVerified(uid);
    }
  }

  Future<void> markOtpSessionVerified() async {
    final uid = currentFirebaseUser?.uid;
    if (uid == null) return;
    _otpSessionOk = true;
    await _secureStorage.setOtpSessionVerified(uid, true);
    try {
      await _hiveService.settingsBox.delete('otp_verified_$uid');
    } catch (_) {}
  }

  Future<void> clearOtpSession() async {
    final uid = currentFirebaseUser?.uid;
    _otpSessionOk = false;
    if (uid != null) {
      await _secureStorage.clearOtpSession(uid);
      try {
        await _hiveService.settingsBox.delete('otp_verified_$uid');
      } catch (_) {}
    }
  }

  // Sign in with email and password
  Future<AuthResult> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final emailLower = email.trim().toLowerCase();
    try {
      final blocked = await _assertLoginAllowed(emailLower);
      if (blocked != null) return blocked;

      // Sign in with Firebase. Passwords are hashed with scrypt by Firebase Auth;
      // this client never stores or hashes the password.
      final credential = await _firebaseService.signInWithEmailAndPassword(
        emailLower,
        password,
      );
      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        await _recordAuthFailure(emailLower);
        return AuthResult(success: false, message: _genericLoginError);
      }

      await firebaseUser.reload();
      final refreshed = _firebaseService.auth.currentUser;
      if (refreshed == null) {
        await _recordAuthFailure(emailLower);
        return AuthResult(success: false, message: _genericLoginError);
      }

      // Get or create user data in Firestore
      final docRef = _firebaseService.usersCollection.doc(firebaseUser.uid);
      final userDoc = await docRef.get();

      Map<String, dynamic> userData;

      if (!userDoc.exists) {
        final now = DateTime.now().toIso8601String();

        String role;
        if (emailLower == AppConstants.adminEmail.toLowerCase()) {
          role = AppConstants.roleAdmin;
        } else {
          // All other accounts default to Site Manager role
          role = AppConstants.roleSiteManager;
        }

        userData = {
          'email': firebaseUser.email ?? email,
          'firstName': '',
          'lastName': '',
          'role': role,
          'profileImageUrl': null,
          'phoneNumber': null,
          'department': null,
          'assignedProjects': <String>[],
          'isActive': true,
          'otpVerified': false,
          'createdAt': now,
          'updatedAt': now,
          'permissions': null,
        };

        await docRef.set(userData);
      } else {
        userData = userDoc.data() as Map<String, dynamic>;

        // Ensure admin email always has correct role even if the
        // Firestore document was created before the email constant was fixed.
        String? updatedRole;
        if (emailLower == AppConstants.adminEmail.toLowerCase() &&
            userData['role'] != AppConstants.roleAdmin) {
          updatedRole = AppConstants.roleAdmin;
        }

        if (updatedRole != null) {
          final now = DateTime.now().toIso8601String();
          userData = {...userData, 'role': updatedRole, 'updatedAt': now};
          try {
            await docRef.update({'role': updatedRole, 'updatedAt': now});
          } catch (_) {
            // Role is server-controlled; continue with local view if rules block.
          }
        }
      }

      // Ensure assignedProjects matches projects where this user is the Site Manager
      userData = await _ensureAssignedProjectsSynced(
        firebaseUser.uid,
        userData,
      );

      // Create user model
      final userModel = UserModel.fromJson({
        'id': firebaseUser.uid,
        ...userData,
      });

      if (!userModel.isActive) {
        await signOut();
        return AuthResult(success: false, message: 'Account is deactivated');
      }

      await _hiveService.saveUser(userModel);

      await SessionTimeoutService.instance.beginSession(firebaseUser.uid);
      await _recordAuthSuccess(emailLower);
      try {
        await firebaseUser.getIdToken(true);
      } catch (_) {}

      // Every login: invalidate prior OTP so Firestore/Storage stay locked until
      // a fresh email code is entered (instructor / pen-test hardening).
      await _beginAuthenticatedSession();
      await clearOtpSession();

      await AuditLogService.instance.logLogin();

      unawaited(sendVerificationCode());
      return AuthResult(
        success: true,
        requiresEmailVerification: true,
        requiresOtp: true,
        user: userModel,
        message:
            'Two-factor step: enter the 6-digit code sent to your email.',
      );
    } on FirebaseAuthException catch (e) {
      await _recordAuthFailure(emailLower);
      await AuditLogService.instance.logAction(
        action: 'login_failed',
        details: {'errorCode': e.code},
      );
      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (_) {
      await _recordAuthFailure(emailLower);
      return AuthResult(success: false, message: _genericLoginError);
    }
  }

  // Register with email and password (self-service for non-admin roles)
  Future<AuthResult> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
  }) async {
    try {
      // Server rules also enforce this — payroll/materials are admin-assigned only.
      if (role != AppConstants.roleSiteManager) {
        return AuthResult(
          success: false,
          message:
              'Only Resident Engineers can self-register. Contact the administrator for other roles.',
        );
      }

      final passwordError = validatePassword(password);
      if (passwordError != null) {
        return AuthResult(success: false, message: passwordError);
      }

      final emailLower = email.trim().toLowerCase();
      if (emailLower == AppConstants.adminEmail.toLowerCase()) {
        return AuthResult(
          success: false,
          message: 'This account cannot be self-registered.',
        );
      }

      final credential = await _firebaseService.auth
          .createUserWithEmailAndPassword(
            email: emailLower,
            password: password,
          )
          .timeout(const Duration(seconds: 20));

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return AuthResult(success: false, message: 'Registration failed');
      }

      final now = DateTime.now().toIso8601String();
      final userData = <String, dynamic>{
        'email': emailLower,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'role': role,
        'profileImageUrl': null,
        'phoneNumber': null,
        'department': null,
        'assignedProjects': <String>[],
        'isActive': true,
        'otpVerified': false,
        'createdAt': now,
        'updatedAt': now,
        'permissions': null,
      };

      final userModel = UserModel.fromJson({
        'id': firebaseUser.uid,
        ...userData,
      });
      try {
        await _hiveService
            .saveUser(userModel)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await SessionTimeoutService.instance
            .beginSession(firebaseUser.uid)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      // Do not block Register on Firestore. OTP uses the signed-in Auth email.
      unawaited(
        _firebaseService.usersCollection
            .doc(firebaseUser.uid)
            .set(userData)
            .timeout(const Duration(seconds: 12))
            .catchError((Object e, StackTrace _) {
              developer.log(
                'user profile write failed: $e',
                name: 'AuthService',
              );
            }),
      );

      return AuthResult(
        success: true,
        requiresEmailVerification: true,
        requiresOtp: true,
        user: userModel,
        message:
            'Account created. Enter the 6-digit code sent to your email.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } on TimeoutException {
      final existing = _firebaseService.auth.currentUser;
      if (existing != null) {
        return AuthResult(
          success: true,
          requiresEmailVerification: true,
          requiresOtp: true,
          message: 'Account created. Continue to enter your verification code.',
        );
      }
      return AuthResult(
        success: false,
        message:
            'Registration timed out. If this email is already registered, sign in instead.',
      );
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Registration failed. Please try again.',
      );
    }
  }

  Future<AuthResult> sendVerificationCode() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendEmailOtp',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call(<String, dynamic>{});
      return AuthResult(
        success: true,
        requiresOtp: true,
        requiresEmailVerification: true,
        message: 'We sent a 6-digit verification code to your email.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return AuthResult(
          success: false,
          requiresOtp: true,
          message: e.message ?? 'Please wait before requesting another code.',
        );
      }
      return AuthResult(
        success: false,
        requiresOtp: true,
        message: e.message ?? 'Could not send the verification code.',
      );
    } catch (_) {
      return AuthResult(
        success: false,
        requiresOtp: true,
        message: 'Could not send the verification code. Try again.',
      );
    }
  }

  // Resend email verification for an existing account using email and password
  Future<AuthResult> resendEmailVerification({
    required String email,
    required String password,
  }) async {
    final result = await signInWithEmailAndPassword(email, password);
    if (!result.success) return result;
    if (result.requiresOtp || result.requiresEmailVerification) {
      return result;
    }
    return AuthResult(
      success: true,
      message: 'This email is already verified. You can sign in normally.',
      user: result.user,
    );
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Capture current user before clearing local state so we only log
      // real user sessions (not temporary auth flows).
      final user = currentUser;
      final uid = currentFirebaseUser?.uid;

      if (user != null) {
        await AuditLogService.instance.logLogout();
      }

      // Clear Firebase auth first
      await _firebaseService.signOut();
      await _hiveService.clearUser();
      await SessionTimeoutService.instance.clearSession();
      _otpSessionOk = false;
      if (uid != null) {
        await _secureStorage.clearOtpSession(uid);
        try {
          await _hiveService.settingsBox.delete('otp_verified_$uid');
        } catch (_) {}
      }

      // Force invalidate providers to ensure UI updates
      // This will trigger the router redirect to login
    } catch (e) {
      // Log error but don't throw
      developer.log('Error during sign out: $e', name: 'AuthService');
    }
  }

  // Check if user is authenticated
  bool get isAuthenticated =>
      currentFirebaseUser != null && currentUser != null;

  // Get user role
  String? get userRole => currentUser?.role;

  // Check user permissions
  bool hasRole(String role) {
    final user = currentUser;
    if (user == null) return false;
    return user.role == role;
  }

  // Check user roles

  bool get isSiteManager => hasRole(AppConstants.roleSiteManager);
  bool get isAdmin => hasRole(AppConstants.roleAdmin);
  bool get isPayroll => hasRole(AppConstants.rolePayroll);
  bool get isMaterials => hasRole(AppConstants.roleMaterials);

  // Check if user has access to project
  bool hasProjectAccess(String projectId) {
    final user = currentUser;
    if (user == null) return false;

    // Admin has access to all projects; materials/payroll monitors also see all
    if (user.isAdmin || user.isMaterials || user.isPayroll) return true;

    // Other roles need to be assigned to the project
    return user.assignedProjects.contains(projectId);
  }

  // Check specific permissions
  bool canCreateReports() => isSiteManager;
  bool canApproveReports() => isAdmin;
  bool canManageProjects() => isAdmin;
  bool canGeneratePayroll() => isAdmin || isPayroll;
  bool canViewAnalytics() => isAdmin;
  bool canViewAllData() => isAdmin;

  // Ensure that assignedProjects is in sync with projects where this user is
  // currently set as the Site Manager. This helps when Admin assigns a
  // project to a Site Manager from the Admin screens.
  Future<Map<String, dynamic>> _ensureAssignedProjectsSynced(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      final role = (userData['role'] ?? '').toString();
      if (role != AppConstants.roleSiteManager) {
        return userData;
      }

      final List<String> existingAssigned = List<String>.from(
        userData['assignedProjects'] ?? const <String>[],
      );

      final email = (userData['email'] ?? '').toString().trim();
      final emailLower = email.toLowerCase();

      final matchedIds = <String>{...existingAssigned};

      try {
        final byId = await _firebaseService.projectsCollection
            .where('siteManagerId', isEqualTo: userId)
            .get();
        for (final doc in byId.docs) {
          final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
          if (!ArchiveService.isArchived(data)) matchedIds.add(doc.id);
        }
      } catch (_) {}

      Future<void> addByEmail(String value) async {
        if (value.isEmpty) return;
        try {
          final byEmail = await _firebaseService.projectsCollection
              .where('projectEngineerEmail', isEqualTo: value)
              .get();
          for (final doc in byEmail.docs) {
            final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
            if (!ArchiveService.isArchived(data)) matchedIds.add(doc.id);
          }
        } catch (_) {}
      }

      await addByEmail(email);
      if (emailLower != email) await addByEmail(emailLower);

      final existingSet = existingAssigned.toSet();
      if (matchedIds.length == existingSet.length &&
          matchedIds.containsAll(existingSet)) {
        return {...userData, 'assignedProjects': existingAssigned};
      }

      final updatedAssigned = matchedIds.toList();
      final now = DateTime.now().toIso8601String();

      try {
        await _firebaseService.usersCollection.doc(userId).update({
          'assignedProjects': updatedAssigned,
          'updatedAt': now,
        });
      } catch (_) {
        // Resident Engineer cannot write assignedProjects; keep it local.
      }

      return {
        ...userData,
        'assignedProjects': updatedAssigned,
        'updatedAt': now,
      };
    } catch (_) {
      // On any failure, fall back to the original data so login/refresh
      // can still proceed.
      return userData;
    }
  }

  // Refresh user data
  Future<bool> refreshUserData() async {
    try {
      final firebaseUser = currentFirebaseUser;
      if (firebaseUser == null) return false;

      final userDoc = await _firebaseService.usersCollection
          .doc(firebaseUser.uid)
          .get();
      if (!userDoc.exists) return false;

      final rawUserData = userDoc.data() as Map<String, dynamic>;
      final userData = await _ensureAssignedProjectsSynced(
        firebaseUser.uid,
        rawUserData,
      );

      final userModel = UserModel.fromJson({
        'id': firebaseUser.uid,
        ...userData,
      });

      await _hiveService.saveUser(userModel);
      await hydrateOtpSession();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Update user profile
  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    try {
      final firebaseUser = currentFirebaseUser;
      final user = currentUser;

      if (firebaseUser == null || user == null) return false;

      const allowed = {
        'firstName',
        'lastName',
        'phoneNumber',
        'department',
        'profileImageUrl',
      };
      final safe = <String, dynamic>{
        for (final entry in updates.entries)
          if (allowed.contains(entry.key)) entry.key: entry.value,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (safe.length <= 1) return false;

      await _firebaseService.usersCollection
          .doc(firebaseUser.uid)
          .update(safe);

      final updatedUser = UserModel.fromJson({
        ...user.toJson(),
        ...safe,
      });

      await _hiveService.saveUser(updatedUser);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Change password
  Future<AuthResult> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final firebaseUser = currentFirebaseUser;
      if (firebaseUser == null) {
        return AuthResult(success: false, message: 'User not authenticated');
      }

      // Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: currentPassword,
      );

      final passwordError = validatePassword(newPassword);
      if (passwordError != null) {
        return AuthResult(success: false, message: passwordError);
      }

      await firebaseUser.reauthenticateWithCredential(credential);
      await firebaseUser.updatePassword(newPassword);

      await AuditLogService.instance.logAction(
        action: 'password_changed',
        details: {'userId': firebaseUser.uid},
      );

      return AuthResult(
        success: true,
        message: 'Password updated successfully',
      );
    } on FirebaseAuthException catch (e) {
      await AuditLogService.instance.logAction(
        action: 'password_change_failed',
        details: {'errorCode': e.code},
      );

      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Failed to update password. Please try again.',
      );
    }
  }

  // Reset password — server issues a time-limited link (1 hour) and rate-limits requests.
  Future<AuthResult> resetPassword(String email) async {
    final emailLower = email.trim().toLowerCase();
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('requestPasswordReset');
      await callable.call(<String, dynamic>{'email': emailLower});

      await AuditLogService.instance.logAction(
        action: 'password_reset_requested',
      );

      return AuthResult(
        success: true,
        message:
            'If that email is registered, a reset link was sent. It expires in 1 hour.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return AuthResult(
          success: false,
          message: 'Too many reset requests. Try again later.',
        );
      }
      return AuthResult(
        success: true,
        message:
            'If that email is registered, a reset link was sent. It expires in 1 hour.',
      );
    } catch (_) {
      return AuthResult(
        success: true,
        message:
            'If that email is registered, a reset link was sent. It expires in 1 hour.',
      );
    }
  }

  static const _genericLoginError = 'Invalid email or password';

  Future<AuthResult?> _assertLoginAllowed(String email) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkLoginAllowed');
      final result = await callable.call(<String, dynamic>{'email': email});
      final data = result.data;
      if (data is Map && data['challenge'] is String) {
        _loginChallenge = data['challenge'] as String;
      } else {
        _loginChallenge = null;
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return AuthResult(
          success: false,
          message: 'Too many failed sign-in attempts. Try again later.',
        );
      }
      // Fail closed: do not allow password attempt if lockout service is unreachable.
      return AuthResult(
        success: false,
        message: 'Unable to verify sign-in safety. Please try again.',
      );
    } catch (_) {
      return AuthResult(
        success: false,
        message: 'Unable to verify sign-in safety. Please try again.',
      );
    }
  }

  Future<void> _beginAuthenticatedSession() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('beginAuthenticatedSession')
          .call(<String, dynamic>{});
    } catch (_) {
      // If this fails, still force client OTP; rules will block data until verified.
    }
  }

  Future<void> _recordAuthFailure(String email) async {
    try {
      final challenge = _loginChallenge;
      if (challenge == null || challenge.isEmpty) return;
      await FirebaseFunctions.instance
          .httpsCallable('recordAuthFailure')
          .call(<String, dynamic>{
        'email': email,
        'challenge': challenge,
      });
    } catch (_) {}
  }

  Future<void> _recordAuthSuccess(String email) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('recordAuthSuccess')
          .call(<String, dynamic>{'email': email});
    } catch (_) {}
  }

  String _getAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return _genericLoginError;
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later';
      case 'weak-password':
        return 'Password is too weak. Use 8+ characters with upper, lower, number, and symbol.';
      case 'email-already-in-use':
        return 'This email is already registered. Sign in instead.';
      case 'requires-recent-login':
        return 'Please sign in again to continue';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

// Auth result class
class AuthResult {
  final bool success;
  final String message;
  final UserModel? user;
  final bool requiresEmailVerification;
  final bool requiresOtp;

  AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.requiresEmailVerification = false,
    this.requiresOtp = false,
  });
}

// Riverpod providers
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService.instance,
);

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authServiceProvider).currentUser;
});

final userRoleProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.role;
});
