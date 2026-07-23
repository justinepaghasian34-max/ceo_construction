import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
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
import '../../views/site_manager/material_inventory_screen.dart';
import '../../views/site_manager/material_request_screen.dart';
import '../../views/site_manager/materials_hub_screen.dart';
import '../../views/site_manager/issues_screen.dart';
import '../../views/site_manager/sync_queue_screen.dart';
import '../../views/site_manager/site_manager_reports_screen.dart';
import '../../views/site_manager/project_progress_update_screen.dart';
import '../../views/site_manager/site_manager_govtrack_screen.dart';
import '../../views/site_manager/site_manager_otp_screen.dart';
import '../../views/admin/admin_home.dart';
import '../../views/admin/admin_dashboard.dart';
import '../../views/admin/admin_reports.dart';
import '../../views/admin/admin_progress_reports.dart';
import '../../views/admin/admin_projects.dart';
import '../../views/admin/admin_payroll.dart';
import '../../views/admin/admin_history.dart';
import '../../views/admin/admin_audit_trail.dart';
import '../../views/admin/admin_material_monitoring.dart';
import '../../views/admin/admin_financial_monitoring.dart';
import '../../views/admin/admin_weather_forecast.dart';
import '../../views/admin/admin_demo_script.dart';
import '../../views/payroll/payroll_home.dart';
import '../../views/payroll/payroll_monitoring_screen.dart';
import '../../views/materials/materials_home.dart';
import '../../views/materials/materials_monitoring_screen.dart';
import '../../views/ceo/ceo_home.dart';
import '../../views/ceo/ceo_dashboard.dart';
import '../../views/ceo/ceo_analytics.dart';
import '../../views/ceo/ceo_reports.dart';
import '../../views/common/profile_screen.dart';
import '../../views/common/settings_screen.dart';
import '../../views/common/notifications_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static CustomTransitionPage<void> _authPage(
    GoRouterState state, {
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0.00, 0.03),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
    );
  }

  static CustomTransitionPage<void> _adminPage(
    GoRouterState state, {
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        final slide = Tween<Offset>(
          begin: const Offset(0.02, 0.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
    );
  }

  static GoRouter createRouter(Ref ref) {
    final authService = ref.read(authServiceProvider);
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: RouteNames.splash,
      refreshListenable: GoRouterRefreshStream(authService.authStateChanges),
      redirect: (context, state) {
        final firebaseUser = authService.currentFirebaseUser;
        final hasFirebaseUser = firebaseUser != null;
        final isAuthenticated = authService.isAuthenticated;
        final userRole = authService.userRole;

        final location = state.uri.toString();

        // If not authenticated and not on login, register, or splash, redirect to login
        if (!hasFirebaseUser &&
            location != RouteNames.login &&
            location != RouteNames.register &&
            location != RouteNames.splash) {
          return RouteNames.login;
        }

        // If FirebaseAuth still has a user but our local role/user model isn't ready yet,
        // avoid bouncing to login. Send the user to splash so the app can rehydrate.
        if (hasFirebaseUser &&
            userRole == null &&
            location != RouteNames.splash &&
            location != RouteNames.login &&
            location != RouteNames.register) {
          return RouteNames.splash;
        }

        // REMOVED: Auto-redirect from login/register/splash to home
        // Users must now explicitly log in after logout
        // This prevents automatic login/shortcut behavior

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
          pageBuilder: (context, state) =>
              _authPage(state, child: const SplashScreen()),
        ),

        // Auth Routes
        GoRoute(
          path: RouteNames.login,
          pageBuilder: (context, state) =>
              _authPage(state, child: const LoginScreen()),
        ),
        GoRoute(
          path: RouteNames.register,
          pageBuilder: (context, state) =>
              _authPage(state, child: const RegisterScreen()),
        ),

        // Site Manager OTP
        GoRoute(
          path: RouteNames.siteManagerOtp,
          builder: (context, state) => const SiteManagerOtpScreen(),
        ),

        // Site Manager Routes
        GoRoute(
          path: RouteNames.siteManagerHome,
          builder: (context, state) => const SiteManagerHome(
            showBottomNav: true,
            showBack: false,
          ),
          routes: [
            GoRoute(
              path: 'tasks',
              builder: (context, state) => const AdminReports(
                showBottomNav: true,
                dashboardRoute: RouteNames.siteManagerHome,
              ),
            ),
            GoRoute(
              path: 'materials',
              builder: (context, state) => const MaterialsHubScreen(
                showBottomNav: true,
                showBack: false,
              ),
            ),
            GoRoute(
              path: 'govtrack-ai',
              builder: (context, state) => const SiteManagerGovtrackScreen(
                showBottomNav: true,
              ),
            ),
            GoRoute(
              path: 'ai-assistant-chat',
              builder: (context, state) => const SiteManagerGovtrackScreen(
                initialTab: 0,
                showBottomNav: false,
              ),
            ),
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
              builder: (context, state) => const AttendanceScreen(
                showBottomNav: true,
                showBack: false,
              ),
            ),
            GoRoute(
              path: 'fingerprint-attendance',
              redirect: (context, state) => RouteNames.attendance,
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
              path: 'material-inventory',
              builder: (context, state) => const MaterialInventoryScreen(),
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
          pageBuilder: (context, state) =>
              _adminPage(state, child: const AdminHome()),
          routes: [
            GoRoute(
              path: 'dashboard',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminDashboard()),
            ),
            GoRoute(
              path: 'weather-forecast',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminWeatherForecastScreen()),
            ),
            GoRoute(
              path: 'progress-reports',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminProgressReportsScreen()),
            ),
            GoRoute(
              path: 'projects',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminProjects()),
            ),
            GoRoute(
              path: 'payroll',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminPayroll()),
            ),
            GoRoute(
              path: 'material-monitoring',
              pageBuilder: (context, state) {
                final qp = state.uri.queryParameters;
                return _adminPage(
                  state,
                  child: AdminMaterialMonitoring(
                    initialProjectId: qp['projectId'],
                    initialProjectName: qp['projectName'],
                  ),
                );
              },
            ),
            GoRoute(
              path: 'financial-monitoring',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminFinancialMonitoring()),
            ),
            GoRoute(
              path: 'history',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminHistory()),
            ),
            GoRoute(
              path: 'audit-trail',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminAuditTrail()),
            ),
            GoRoute(
              path: 'demo-script',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const AdminDemoScriptScreen()),
            ),
          ],
        ),

        // Payroll Routes
        GoRoute(
          path: RouteNames.payrollHome,
          pageBuilder: (context, state) =>
              _adminPage(state, child: const PayrollHome()),
          routes: [
            GoRoute(
              path: 'monitoring',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const PayrollMonitoringScreen()),
            ),
          ],
        ),

        // Materials Routes
        GoRoute(
          path: RouteNames.materialsHome,
          pageBuilder: (context, state) =>
              _adminPage(state, child: const MaterialsHome()),
          routes: [
            GoRoute(
              path: 'monitoring',
              pageBuilder: (context, state) =>
                  _adminPage(state, child: const MaterialsMonitoringScreen()),
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
      case AppConstants.rolePayroll:
        return RouteNames.payrollHome;
      case AppConstants.roleMaterials:
        return RouteNames.materialsHome;
      default:
        return RouteNames.login;
    }
  }

  static bool _hasAccessToRoute(String route, String? userRole) {
    if (userRole == null) return false;

    if (route.startsWith(RouteNames.profile) ||
        route.startsWith(RouteNames.settings) ||
        route.startsWith(RouteNames.notifications)) {
      return true;
    }

    if (userRole == AppConstants.roleAdmin) {
      return route.startsWith(RouteNames.adminHome) ||
          route.startsWith(RouteNames.payrollHome) ||
          route.startsWith(RouteNames.materialsHome);
    }

    if (userRole == AppConstants.roleCeo) {
      return route.startsWith(RouteNames.ceoHome);
    }

    if (userRole == AppConstants.rolePayroll) {
      return route.startsWith(RouteNames.payrollHome);
    }

    if (userRole == AppConstants.roleMaterials) {
      return route.startsWith(RouteNames.materialsHome);
    }

    if (userRole == AppConstants.roleSiteManager) {
      return route.startsWith(RouteNames.siteManagerHome);
    }

    return false;
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  StreamSubscription<dynamic>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return AppRouter.createRouter(ref);
});

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

  void goToDailyReport() => go(RouteNames.dailyReport);
  void goToAttendance() => go(RouteNames.attendance);
  void goToMaterialUsage() => go(RouteNames.materialUsage);
  void goToMaterialDelivery() => go(RouteNames.materialDelivery);
  void goToMaterialRequest() => go(RouteNames.materialRequest);
  void goToIssues() => go(RouteNames.issues);
  void goToSyncQueue() => go(RouteNames.syncQueue);

  void goToAdminDashboard() => go(RouteNames.adminDashboard);
  void goToAdminProjects() => go(RouteNames.adminProjects);
  void goToAdminPayroll() => go(RouteNames.adminPayroll);
  void goToAdminHistory() => go(RouteNames.adminHistory);
  void goToAdminAuditTrail() => go(RouteNames.adminAuditTrail);
  void goToAdminMaterialMonitoring() => go(RouteNames.adminMaterialMonitoring);
  void goToAdminFinancialMonitoring() => go(RouteNames.adminFinancialMonitoring);
}
