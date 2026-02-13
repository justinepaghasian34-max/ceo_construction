import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();
  FirebaseService._();

  // Firebase instances
  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get firestore => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;
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
  CollectionReference get disbursementsCollection =>
      firestore.collection('disbursements');

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

  // Project sub-collections
  CollectionReference dailyReportsCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('daily_reports');

  CollectionReference attendanceCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('attendance');

  CollectionReference deliveriesCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('deliveries');

  CollectionReference payrollCollection(String projectId) =>
      projectsCollection.doc(projectId).collection('payroll');

  CollectionReference payrollItemsCollection(
    String projectId,
    String payrollId,
  ) => payrollCollection(projectId).doc(payrollId).collection('items');

  CollectionReference materialUsageCollection(
    String projectId,
    String reportId,
  ) => dailyReportsCollection(
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
