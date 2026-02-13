import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../core/constants/app_constants.dart';
import 'firebase_service.dart';
import 'hive_service.dart';
import 'audit_log_service.dart';

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  final FirebaseService _firebaseService = FirebaseService.instance;
  final HiveService _hiveService = HiveService.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _firebaseService.authStateChanges;

  // Get current Firebase user
  User? get currentFirebaseUser => _firebaseService.auth.currentUser;

  // Get current user model
  UserModel? get currentUser => _hiveService.getCurrentUser();

  // Sign in with email and password
  Future<AuthResult> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      // Sign in with Firebase
      final credential = await _firebaseService.signInWithEmailAndPassword(
        email,
        password,
      );
      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        await AuditLogService.instance.logAction(
          action: 'login_failed',
          details: {'email': email.toLowerCase(), 'reason': 'no_firebase_user'},
        );
        return AuthResult(success: false, message: 'Authentication failed');
      }

      // Refresh
      await firebaseUser.reload();
      final emailLower = (firebaseUser.email ?? email).toLowerCase();

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
          await docRef.update({'role': updatedRole, 'updatedAt': now});
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

      // Check if user is active
      if (!userModel.isActive) {
        await signOut();
        return AuthResult(success: false, message: 'Account is deactivated');
      }

      // Save user locally
      await _hiveService.saveUser(userModel);
      // Log successful login to audit trail (best-effort only)
      await AuditLogService.instance.logLogin();

      return AuthResult(
        success: true,
        message: 'Sign in successful',
        user: userModel,
      );
    } on FirebaseAuthException catch (e) {
      await AuditLogService.instance.logAction(
        action: 'login_failed',
        details: {'email': email.toLowerCase(), 'errorCode': e.code},
      );

      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (e) {
      await AuditLogService.instance.logAction(
        action: 'login_failed',
        details: {'email': email.toLowerCase(), 'error': e.toString()},
      );

      return AuthResult(
        success: false,
        message: 'An unexpected error occurred: $e',
      );
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
      // Only allow specific roles to self-register
      const allowedRoles = <String>{AppConstants.roleSiteManager};

      if (!allowedRoles.contains(role)) {
        return AuthResult(
          success: false,
          message:
              'This role cannot self-register. Please contact the administrator.',
        );
      }

      final credential = await _firebaseService.auth
          .createUserWithEmailAndPassword(email: email, password: password);

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return AuthResult(success: false, message: 'Registration failed');
      }

      final now = DateTime.now().toIso8601String();
      final emailLower = (firebaseUser.email ?? email).toLowerCase();

      final userData = <String, dynamic>{
        'email': emailLower,
        'firstName': firstName,
        'lastName': lastName,
        'role': role,
        'profileImageUrl': null,
        'phoneNumber': null,
        'department': null,
        'assignedProjects': <String>[],
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
        'permissions': null,
      };

      await _firebaseService.usersCollection
          .doc(firebaseUser.uid)
          .set(userData);

      // Send verification email
      if (!firebaseUser.emailVerified) {
        await firebaseUser.sendEmailVerification();
      }

      // Sign out so user must verify then sign in
      await signOut();

      return AuthResult(
        success: true,
        message:
            'Registration successful. Please check your email for a verification link before signing in.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'An unexpected error occurred during registration: $e',
      );
    }
  }

  // Resend email verification for an existing account using email and password
  Future<AuthResult> resendEmailVerification({
    required String email,
    required String password,
  }) async {
    try {
      // Sign in temporarily to get the user
      final credential = await _firebaseService.auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return AuthResult(
          success: false,
          message: 'Unable to find user for this email.',
        );
      }

      await firebaseUser.reload();
      final refreshedUser = _firebaseService.auth.currentUser;

      if (refreshedUser?.emailVerified == true) {
        await _firebaseService.signOut();
        return AuthResult(
          success: true,
          message: 'This email is already verified. You can sign in normally.',
        );
      }

      await refreshedUser?.sendEmailVerification();
      await _firebaseService.signOut();

      return AuthResult(
        success: true,
        message:
            'Verification email sent. Please check your inbox and spam folder, then sign in after verifying.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to resend verification email: $e',
      );
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Capture current user before clearing local state so we only log
      // real user sessions (not temporary auth flows).
      final user = currentUser;

      if (user != null) {
        await AuditLogService.instance.logLogout();
      }

      await _firebaseService.signOut();
      await _hiveService.clearUser();
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

  // Check if user has access to project
  bool hasProjectAccess(String projectId) {
    final user = currentUser;
    if (user == null) return false;

    // Admin has access to all projects
    if (user.isAdmin) return true;

    // Other roles need to be assigned to the project
    return user.assignedProjects.contains(projectId);
  }

  // Check specific permissions
  bool canCreateReports() => isSiteManager;
  bool canApproveReports() => isAdmin;
  bool canManageProjects() => isAdmin;
  bool canGeneratePayroll() => isAdmin;
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

      final projectsSnap = await _firebaseService.projectsCollection
          .where('siteManagerId', isEqualTo: userId)
          .get();

      final updatedAssignedSet = <String>{
        ...existingAssigned,
        for (final doc in projectsSnap.docs) doc.id,
      };

      final existingSet = existingAssigned.toSet();

      // If nothing changed, avoid an unnecessary write
      if (updatedAssignedSet.length == existingSet.length &&
          updatedAssignedSet.containsAll(existingSet)) {
        return {...userData, 'assignedProjects': existingAssigned};
      }

      final updatedAssigned = updatedAssignedSet.toList();
      final now = DateTime.now().toIso8601String();

      await _firebaseService.usersCollection.doc(userId).update({
        'assignedProjects': updatedAssigned,
        'updatedAt': now,
      });

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

      // Update in Firestore
      await _firebaseService.usersCollection
          .doc(firebaseUser.uid)
          .update(updates);

      // Update locally
      final updatedUser = UserModel.fromJson({
        ...user.toJson(),
        ...updates,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      await _hiveService.saveUser(updatedUser);
      return true;
    } catch (e) {
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

      await firebaseUser.reauthenticateWithCredential(credential);

      // Update password
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
    } catch (e) {
      await AuditLogService.instance.logAction(
        action: 'password_change_failed',
        details: {'error': e.toString()},
      );

      return AuthResult(
        success: false,
        message: 'Failed to update password: $e',
      );
    }
  }

  // Reset password
  Future<AuthResult> resetPassword(String email) async {
    try {
      await _firebaseService.auth.sendPasswordResetEmail(email: email);

      await AuditLogService.instance.logAction(
        action: 'password_reset_requested',
        details: {'email': email.toLowerCase()},
      );

      return AuthResult(success: true, message: 'Password reset email sent');
    } on FirebaseAuthException catch (e) {
      await AuditLogService.instance.logAction(
        action: 'password_reset_failed',
        details: {'email': email.toLowerCase(), 'errorCode': e.code},
      );

      return AuthResult(success: false, message: _getAuthErrorMessage(e.code));
    } catch (e) {
      await AuditLogService.instance.logAction(
        action: 'password_reset_failed',
        details: {'email': email.toLowerCase(), 'error': e.toString()},
      );

      return AuthResult(
        success: false,
        message: 'Failed to send reset email: $e',
      );
    }
  }

  // Get auth error message
  String _getAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
        return 'No user found with this email address';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later';
      case 'weak-password':
        return 'Password is too weak';
      case 'email-already-in-use':
        return 'Email is already registered';
      case 'requires-recent-login':
        return 'Please sign in again to continue';
      default:
        return 'Authentication error: $errorCode';
    }
  }
}

// Auth result class
class AuthResult {
  final bool success;
  final String message;
  final UserModel? user;

  AuthResult({required this.success, required this.message, this.user});
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
