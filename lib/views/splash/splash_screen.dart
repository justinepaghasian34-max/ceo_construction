import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../services/session_timeout_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
      ),
    );

    _animationController.forward();
  }

  Future<void> _initializeApp() async {
    // Wait for animation to complete
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    var nextRoute = RouteNames.login;

    try {
      final authService = ref.read(authServiceProvider);
      var isAuthenticated = authService.isAuthenticated;
      final hasFirebaseUser = authService.currentFirebaseUser != null;

      if (hasFirebaseUser && SessionTimeoutService.instance.isExpired) {
        await authService.signOut();
      } else {
        if (!isAuthenticated && hasFirebaseUser) {
          final ok = await authService
              .refreshUserData()
              .timeout(const Duration(seconds: 12), onTimeout: () => false);
          if (!ok) {
            await authService.signOut();
          } else {
            isAuthenticated = authService.isAuthenticated;
          }
        }

        if (isAuthenticated) {
          final user = authService.currentUser;
          final userRole = user?.role;
          final email = user?.email.toLowerCase();

          if (email != AppConstants.adminEmail.toLowerCase() &&
              !authService.isOtpVerified) {
            nextRoute = RouteNames.siteManagerOtp;
          } else {
            switch (userRole) {
              case AppConstants.roleSiteManager:
                nextRoute = RouteNames.siteManagerHome;
                break;
              case AppConstants.roleAdmin:
                nextRoute = RouteNames.adminHome;
                break;
              case AppConstants.rolePayroll:
                nextRoute = RouteNames.payrollHome;
                break;
              case AppConstants.roleMaterials:
                nextRoute = RouteNames.materialsHome;
                break;
              case AppConstants.roleCeo:
                nextRoute = RouteNames.ceoHome;
                break;
              default:
                nextRoute = RouteNames.login;
            }
          }
        }
      }
    } catch (_) {
      nextRoute = RouteNames.login;
    }

    if (!mounted) return;
    context.go(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepBlue,
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Logo
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.white.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/image.png',
                          height: 80,
                          width: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.construction,
                              size: 80,
                              color: AppTheme.white,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // App Name
                    Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppTheme.white,
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      'City Engineering Office (LGU)',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.white.withValues(alpha: 0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Loading Indicator
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.softGreen,
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Loading Text
                    Text(
                      'Initializing...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
