class AppConstants {
  // App Info
  static const String appName = 'CEO Construction Monitoring';
  static const String appVersion = '1.0.0';

  // User Roles
  static const String roleSiteManager = 'site_manager';
  static const String roleAdmin = 'admin';
  static const String roleCeo = 'ceo';

  // Privileged account emails
  static const String adminEmail = 'cherryantipuesto23@gmail.com';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String projectsCollection = 'projects';
  static const String notificationsCollection = 'notifications';
  static const String aiAnalysisCollection = 'ai_analysis';
  static const String auditLogsCollection = 'audit_logs';
  static const String disbursementsCollection = 'disbursements';

  // Firestore Sub-collections
  static const String dailyReportsSubCollection = 'daily_reports';
  static const String attendanceSubCollection = 'attendance';
  static const String materialUsageSubCollection = 'material_usage';
  static const String deliveriesSubCollection = 'deliveries';
  static const String payrollSubCollection = 'payroll';
  static const String payrollItemsSubCollection = 'items';
  static const String historySubCollection = 'history';

  // Hive Boxes
  static const String userBox = 'user_box';
  static const String dailyReportsBox = 'daily_reports_box';
  static const String attendanceBox = 'attendance_box';
  static const String materialUsageBox = 'material_usage_box';
  static const String materialInventoryBox = 'material_inventory_box';
  static const String deliveriesBox = 'deliveries_box';
  static const String syncQueueBox = 'sync_queue_box';
  static const String settingsBox = 'settings_box';

  // Sync Status
  static const String syncStatusPending = 'pending';
  static const String syncStatusSyncing = 'syncing';
  static const String syncStatusCompleted = 'completed';
  static const String syncStatusFailed = 'failed';

  // Report Status
  static const String reportStatusDraft = 'draft';
  static const String reportStatusSubmitted = 'submitted';
  static const String reportStatusApproved = 'approved';
  static const String reportStatusRejected = 'rejected';

  // Payroll Status
  static const String payrollStatusGenerated = 'generated';
  static const String payrollStatusValidated = 'validated';
  static const String payrollStatusPaid = 'paid';
  static const String payrollStatusReturned = 'returned';

  // Material Request Status
  static const String materialRequestPending = 'pending';
  static const String materialRequestApproved = 'approved';
  static const String materialRequestRejected = 'rejected';

  // Notification Types
  static const String notificationDailyReport = 'daily_report_submitted';
  static const String notificationOfflineSync = 'offline_data_synced';
  static const String notificationMaterialRequest = 'material_request';
  static const String notificationMDRSubmission = 'mdr_submission';
  static const String notificationLowMaterials = 'low_materials';
  static const String notificationPayrollValidated = 'payroll_validated';
  static const String notificationPayrollPaid = 'payroll_paid';
  static const String notificationAIDelay = 'ai_delay_detected';

  // File Upload Limits
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> allowedDocumentTypes = ['pdf', 'doc', 'docx'];

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Cache Duration
  static const Duration cacheExpiration = Duration(hours: 24);
  static const Duration syncRetryDelay = Duration(minutes: 5);

  // API Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
}

class RouteNames {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';

  // CEO Routes
  static const String ceoHome = '/ceo';
  static const String ceoDashboard = '/ceo/dashboard';
  static const String ceoAnalytics = '/ceo/analytics';
  static const String ceoReports = '/ceo/reports';

  // Site Manager Routes
  static const String siteManagerHome = '/site-manager';
  static const String dailyReport = '/site-manager/daily-report';
  static const String attendance = '/site-manager/attendance';
  static const String materialUsage = '/site-manager/material-usage';
  static const String materialDelivery = '/site-manager/material-delivery';
  static const String materialRequest = '/site-manager/material-request';
  static const String issues = '/site-manager/issues';
  static const String projectProgressUpdate =
      '/site-manager/project-progress-update';
  static const String syncQueue = '/site-manager/sync-queue';

  // Admin Routes
  static const String adminHome = '/admin';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminReports = '/admin/reports';
  static const String adminProjects = '/admin/projects';
  static const String adminPayroll = '/admin/payroll';
  static const String adminHistory = '/admin/history';
  static const String adminAuditTrail = '/admin/audit-trail';
  static const String adminMaterialMonitoring = '/admin/material-monitoring';
  static const String adminFinancialMonitoring = '/admin/financial-monitoring';

  // Common Routes
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String notifications = '/notifications';
}
