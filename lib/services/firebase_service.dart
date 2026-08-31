import 'dart:typed_data';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();
  FirebaseService._();

  // Firebase instances
  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get firestore => FirebaseFirestore.instance;
  FirebaseStorage get storage {
    final bucket = Firebase.app().options.storageBucket;
    if (bucket == null || bucket.isEmpty) {
      return FirebaseStorage.instance;
    }
    final normalized = bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
    return FirebaseStorage.instanceFor(bucket: normalized);
  }

  FirebaseMessaging get messaging => FirebaseMessaging.instance;

  // Initialize Firebase
  static Future<void> initialize() async {
    // Configure Firestore settings (Firebase is already initialized in main.dart)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Auth methods
  Future<User?> getCurrentUser() async {
    return auth.currentUser;
  }

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    return await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await auth.signOut();
  }

  Stream<User?> get authStateChanges => auth.authStateChanges();

  // Firestore methods
  CollectionReference get usersCollection => firestore.collection('users');
  CollectionReference get projectsCollection =>
      firestore.collection('projects');
  CollectionReference get notificationsCollection =>
      firestore.collection('notifications');
  CollectionReference get aiAnalysisCollection =>
      firestore.collection('ai_analysis');
  CollectionReference get auditLogsCollection =>
      firestore.collection('audit_logs');
  CollectionReference get obligationsCollection =>
      firestore.collection('obligations');
  CollectionReference get suppliersCollection =>
      firestore.collection('suppliers');
  CollectionReference get disbursementsCollection =>
      firestore.collection('disbursements');
  CollectionReference get budgetsCollection => firestore.collection('budgets');
  CollectionReference get activityLogsCollection =>
      firestore.collection('activity_logs');
  CollectionReference get materialTemplatesCollection =>
      firestore.collection('material_templates');

  Future<String> generateProjectCode() async {
    final now = DateTime.now();
    final year = now.year.toString();
    final String lowerBound = year;
    final String upperBound = (now.year + 1).toString();

    final query = await projectsCollection
        .where('projectCode', isGreaterThanOrEqualTo: lowerBound)
        .where('projectCode', isLessThan: upperBound)
        .orderBy('projectCode', descending: true)
        .limit(1)
        .get();

    int nextSequence = 1;
    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data() as Map<String, dynamic>;
      final lastCode = (data['projectCode'] ?? '').toString();
      if (lastCode.length > 4) {
        final seqStr = lastCode.substring(4);
        final parsed = int.tryParse(seqStr);
        if (parsed != null && parsed >= 0) {
          nextSequence = parsed + 1;
        }
      }
    }

    final sequenceStr = nextSequence.toString().padLeft(3, '0');
    return '$year$sequenceStr';
  }

  Future<DocumentSnapshot?> findUserByEmail(String email) async {
    final needle = email.trim().toLowerCase();
    if (needle.isEmpty) return null;

    Future<DocumentSnapshot?> matchIn(QuerySnapshot snap) async {
      for (final doc in snap.docs) {
        final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
        if ((data['email'] ?? '').toString().trim().toLowerCase() == needle) {
          return doc;
        }
      }
      return null;
    }

    try {
      final exact = await usersCollection
          .where('email', isEqualTo: email.trim())
          .limit(8)
          .get();
      final hit = await matchIn(exact);
      if (hit != null) return hit;
    } catch (_) {}

    try {
      final lower = await usersCollection
          .where('email', isEqualTo: needle)
          .limit(8)
          .get();
      final hit = await matchIn(lower);
      if (hit != null) return hit;
    } catch (_) {}

    try {
      final byRole = await usersCollection
          .where('role', isEqualTo: 'site_manager')
          .limit(80)
          .get();
      final hit = await matchIn(byRole);
      if (hit != null) return hit;
    } catch (_) {}

    return null;
  }

  Future<void> addProjectToUserAssignments({
    required String userId,
    required String projectId,
  }) async {
    if (userId.isEmpty || projectId.isEmpty) return;
    final ref = usersCollection.doc(userId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
    final assigned = List<dynamic>.from(data['assignedProjects'] ?? []);
    if (assigned.contains(projectId)) return;
    assigned.add(projectId);
    await ref.update({
      'assignedProjects': assigned,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // Project sub-collections
  CollectionReference dailyReportsCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('daily_reports');

  CollectionReference materialInventoryCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('material_inventory');

  CollectionReference materialAllocationsCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('material_allocations');

  CollectionReference attendanceCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('attendance');

  CollectionReference deliveriesCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('deliveries');

  CollectionReference payrollCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('payroll');

  CollectionReference payrollItemsCollection(
    String projectId,
    String payrollId,
  ) =>
      payrollCollection(projectId).doc(payrollId).collection('items');

  CollectionReference materialUsageCollection(
    String projectId,
    String reportId,
  ) =>
      dailyReportsCollection(
        projectId,
      ).doc(reportId).collection('material_usage');

  CollectionReference historyCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('history');

  CollectionReference documentsCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('documents');

  // Storage methods
  Reference storageRef(String path) => storage.ref(path);

  Future<String> uploadFile(
    String path,
    Uint8List data, {
    String? contentType,
  }) async {
    final ref = storage.ref(path);
    final uploadTask = ref.putData(
      data,
      SettableMetadata(contentType: contentType),
    );
    final snapshot = await uploadTask;

    FirebaseException? lastErr;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        return await snapshot.ref.getDownloadURL();
      } on FirebaseException catch (e) {
        lastErr = e;
        if (e.code != 'object-not-found') {
          rethrow;
        }
        final delayMs = (300 * (1 << attempt)).clamp(300, 5000);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    if (lastErr != null) {
      throw lastErr;
    }
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> deleteFile(String path) async {
    final ref = storage.ref(path);
    await ref.delete();
  }

  // Messaging methods
  Future<String?> getFCMToken() async {
    return await messaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    await messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await messaging.unsubscribeFromTopic(topic);
  }

  // Batch operations
  WriteBatch batch() => firestore.batch();

  Future<void> commitBatch(WriteBatch batch) async {
    await batch.commit();
  }

  // Transaction operations
  Future<T> runTransaction<T>(TransactionHandler<T> updateFunction) async {
    return await firestore.runTransaction(updateFunction);
  }

  // Enable/Disable network
  Future<void> enableNetwork() async {
    await firestore.enableNetwork();
  }

  Future<void> disableNetwork() async {
    await firestore.disableNetwork();
  }

  // Clear persistence
  Future<void> clearPersistence() async {
    await firestore.clearPersistence();
  }

  // Terminate Firestore
  Future<void> terminate() async {
    await firestore.terminate();
  }
}
