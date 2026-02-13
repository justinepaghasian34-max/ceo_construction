import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../views/auth/login_screen.dart';
import '../../views/auth/register_screen.dart';
import '../../views/splash/splash_screen.dart';
import '../../views/site_manager/site_manager_home.dart';
import '../../views/site_manager/daily_report_screen.dart';
import '../../views/site_manager/attendance_screen.dart';
import '../../views/site_manager/material_usage_screen.dart';
import '../../views/site_manager/material_delivery_screen.dart';
import '../../views/site_manager/material_request_screen.dart';
import '../../views/site_manager/issues_screen.dart';
import '../../views/site_manager/sync_queue_screen.dart';
import '../../views/site_manager/site_manager_reports_screen.dart';
import '../../views/site_manager/project_progress_update_screen.dart';
import '../../views/admin/admin_home.dart';
import '../../views/admin/admin_dashboard.dart';
import '../../views/admin/admin_reports.dart';
import '../../views/admin/admin_projects.dart';
import '../../views/admin/admin_payroll.dart';
import '../../views/admin/admin_history.dart';
import '../../views/admin/admin_audit_trail.dart';
import '../../views/admin/admin_material_monitoring.dart';
import '../../views/admin/admin_financial_monitoring.dart';
import '../../views/ceo/ceo_home.dart';
import '../../views/ceo/ceo_dashboard.dart';
import '../../views/ceo/ceo_analytics.dart';
import '../../views/ceo/ceo_reports.dart';
import '../../views/common/profile_screen.dart';
import '../../views/common/settings_screen.dart';
import '../../views/common/notifications_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter createRouter(Ref ref) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: RouteNames.splash,
      redirect: (context, state) {
        final authService = ref.read(authServiceProvider);
        final isAuthenticated = authService.isAuthenticated;
        final userRole = authService.userRole;

        final location = state.uri.toString();

        // If not authenticated and not on login, register, or splash, redirect to login
        if (!isAuthenticated &&
            location != RouteNames.login &&
            location != RouteNames.register &&
            location != RouteNames.splash) {
          return RouteNames.login;
        }

        // If authenticated and on login, register, or splash, redirect to appropriate home
        if (isAuthenticated &&
            (location == RouteNames.login ||
                location == RouteNames.register ||
                location == RouteNames.splash)) {
          return _getHomeRouteForRole(userRole);
        }

        // Check role-based access
        if (isAuthenticated && !_hasAccessToRoute(location, userRole)) {
          return _getHomeRouteForRole(userRole);
        }

        return null;
      },
      routes: [
        // Splash Screen
        GoRoute(
          path: RouteNames.splash,
          builder: (context, state) => const SplashScreen(),
        ),

        // Auth Routes
        GoRoute(
          path: RouteNames.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: RouteNames.register,
          builder: (context, state) => const RegisterScreen(),
        ),

        // Site Manager Routes
        GoRoute(
          path: RouteNames.siteManagerHome,
          builder: (context, state) => const SiteManagerHome(),
          routes: [
            GoRoute(
              path: 'daily-report',
              builder: (context, state) => const DailyReportScreen(),
            ),
            GoRoute(
              path: 'reports',
              builder: (context, state) => const SiteManagerReportsScreen(),
            ),
            GoRoute(
              path: 'attendance',
              builder: (context, state) => const AttendanceScreen(),
            ),
            GoRoute(
              path: 'material-usage',
              builder: (context, state) => const MaterialUsageScreen(),
            ),
            GoRoute(
              path: 'material-delivery',
              builder: (context, state) => const MaterialDeliveryScreen(),
            ),
            GoRoute(
              path: 'material-request',
              builder: (context, state) => const MaterialRequestScreen(),
            ),
            GoRoute(
              path: 'issues',
              builder: (context, state) => const IssuesScreen(),
            ),
            GoRoute(
              path: 'project-progress-update',
              builder: (context, state) => const ProjectProgressUpdateScreen(),
            ),
            GoRoute(
              path: 'sync-queue',
              builder: (context, state) => const SyncQueueScreen(),
            ),
          ],
        ),

        // CEO Routes
        GoRoute(
          path: RouteNames.ceoHome,
          builder: (context, state) => const CeoHome(),
          routes: [
            GoRoute(
              path: 'dashboard',
              builder: (context, state) => const CeoDashboard(),
            ),
            GoRoute(
              path: 'analytics',
              builder: (context, state) => const CeoAnalytics(),
            ),
            GoRoute(
              path: 'reports',
              builder: (context, state) => const CeoReports(),
            ),
          ],
        ),

        // Admin Routes
        GoRoute(
          path: RouteNames.adminHome,
          builder: (context, state) => const AdminHome(),
          routes: [
            GoRoute(
              path: 'dashboard',
              builder: (context, state) => const AdminDashboard(),
            ),
            GoRoute(
              path: 'reports',
              builder: (context, state) => const AdminReports(),
            ),
            GoRoute(
              path: 'projects',
              builder: (context, state) => const AdminProjects(),
            ),
            GoRoute(
              path: 'payroll',
              builder: (context, state) => const AdminPayroll(),
            ),
            GoRoute(
              path: 'material-monitoring',
              builder: (context, state) => const AdminMaterialMonitoring(),
            ),
            GoRoute(
              path: 'financial-monitoring',
              builder: (context, state) => const AdminFinancialMonitoring(),
            ),
            GoRoute(
              path: 'history',
              builder: (context, state) => const AdminHistory(),
            ),
            GoRoute(
              path: 'audit-trail',
              builder: (context, state) => const AdminAuditTrail(),
            ),
          ],
        ),

        // Common Routes
        GoRoute(
          path: RouteNames.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: RouteNames.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: RouteNames.notifications,
          builder: (context, state) => const NotificationsScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text(
            'Error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'The page "${state.uri.toString()}" could not be found.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(RouteNames.splash),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _getHomeRouteForRole(String? role) {
    switch (role) {
      case AppConstants.roleSiteManager:
        return RouteNames.siteManagerHome;
      case AppConstants.roleAdmin:
        return RouteNames.adminHome;
      case AppConstants.roleCeo:
        return RouteNames.ceoHome;
      default:
        return RouteNames.login;
    }
  }

  static bool _hasAccessToRoute(String route, String? userRole) {
    if (userRole == null) return false;

    // Common routes accessible to all authenticated users
    if (route.startsWith(RouteNames.profile) ||
        route.startsWith(RouteNames.settings) ||
        route.startsWith(RouteNames.notifications)) {
      return true;
    }

    // Role-specific route access
    switch (userRole) {
      case AppConstants.roleSiteManager:
        return route.startsWith(RouteNames.siteManagerHome);
      case AppConstants.roleAdmin:
        return route.startsWith(RouteNames.adminHome);
      case AppConstants.roleCeo:
        return route.startsWith(RouteNames.ceoHome);
      default:
        return false;
    }
  }
}

// Router provider
final goRouterProvider = Provider<GoRouter>((ref) {
  return AppRouter.createRouter(ref);
});

// Navigation helper methods
extension AppNavigation on BuildContext {
  void goToLogin() => go(RouteNames.login);
  void goToHome() {
    final authService = AuthService.instance;
    final homeRoute = AppRouter._getHomeRouteForRole(authService.userRole);
    go(homeRoute);
  }

  void goToProfile() => go(RouteNames.profile);
  void goToSettings() => go(RouteNames.settings);
  void goToNotifications() => go(RouteNames.notifications);

  // Site Manager Navigation
  void goToDailyReport() => go(RouteNames.dailyReport);
  void goToAttendance() => go(RouteNames.attendance);
  void goToMaterialUsage() => go(RouteNames.materialUsage);
  void goToMaterialDelivery() => go(RouteNames.materialDelivery);
  void goToMaterialRequest() => go(RouteNames.materialRequest);
  void goToIssues() => go(RouteNames.issues);
  void goToSyncQueue() => go(RouteNames.syncQueue);

  // Admin Navigation
  void goToAdminDashboard() => go(RouteNames.adminDashboard);
  void goToAdminReports() => go(RouteNames.adminReports);
  void goToAdminProjects() => go(RouteNames.adminProjects);
  void goToAdminPayroll() => go(RouteNames.adminPayroll);
  void goToAdminHistory() => go(RouteNames.adminHistory);
  void goToAdminAuditTrail() => go(RouteNames.adminAuditTrail);
  void goToAdminMaterialMonitoring() => go(RouteNames.adminMaterialMonitoring);
  void goToAdminFinancialMonitoring() =>
      go(RouteNames.adminFinancialMonitoring);
}
