import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Image_Background.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A2A47).withValues(alpha: 0.18),
                    const Color(0xFF051F36).withValues(alpha: 0.28),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 860;

                      final content = isNarrow
                          ? Align(
                              alignment: Alignment.center,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: _buildSignInCard(),
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 560),
                                      child: _buildLeftCopy(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 70),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: 560,
                                    child: _buildSignInCard(),
                                  ),
                                ),
                              ],
                            );

                      return Form(key: _formKey, child: content);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftCopy() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/City Engineering Office logo design.png',
              height: 54,
              width: 54,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 16),
            Text(
              'CITY ENGINEERING\nOFFICERS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    height: 1.05,
                    fontSize: 18,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: AppTheme.white,
                  fontWeight: FontWeight.w800,
                  height: 1.02,
                  fontSize: 58,
                ),
            children: [
              const TextSpan(text: 'Engineering\n'),
              TextSpan(
                text: 'Excellence.',
                style: TextStyle(
                  color: const Color(0xFFE4C86A),
                  fontWeight: FontWeight.w900,
                  fontSize: 60,
                ),
              ),
              const TextSpan(text: '\nBuilding Better Cities.'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: 110,
          height: 2,
          color: const Color(0xFFE4C86A).withValues(alpha: 0.70),
        ),
        const SizedBox(height: 14),
        Text(
          'CEO Construction Monitoring for\nadvanced project oversight.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.white.withValues(alpha: 0.82),
                height: 1.4,
              ),
        ),
      ],
    );
  }

  Widget _buildSignInCard() {
    const borderColor = Color(0xFFB79B4D);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor.withValues(alpha: 0.85), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A2A47).withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/City Engineering Office logo design.png',
                      height: 120,
                      width: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'CITY ENGINEERING\nOFFICERS',
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.white,
                            letterSpacing: 0.4,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Sign In',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.white,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your credentials to continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.white.withValues(alpha: 0.80),
                      ),
                ),
                const SizedBox(height: 14),
                _buildNewFields(),
                const SizedBox(height: 14),
                _buildGoldSignInButton(),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _isLoading ? null : _handleResendVerification,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppTheme.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text("Didn't receive verification email?"),
                ),
                const SizedBox(height: 10),
                _buildBottomSignUpLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewFields() {
    final labelColor = AppTheme.white.withValues(alpha: 0.92);
    final fieldFill = AppTheme.white;

    InputDecoration decoration({
      required String hint,
      required IconData icon,
      Widget? suffix,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppTheme.mediumGray.withValues(alpha: 0.95),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF4B6076)),
        suffixIcon: suffix,
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.darkGray.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0B2B4A), width: 1.3),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Email Address', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: labelColor, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Color(0xFF0B2B4A), fontWeight: FontWeight.w700),
          decoration: decoration(hint: 'Enter your email', icon: Icons.email_outlined),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Password',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: labelColor, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: _isLoading ? null : _handleForgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text('Forgot Password?'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Color(0xFF0B2B4A), fontWeight: FontWeight.w700),
          decoration: decoration(
            hint: 'Enter your password',
            icon: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF4B6076),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildGoldSignInButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE4C86A),
          foregroundColor: const Color(0xFF0B2B4A),
          disabledBackgroundColor: const Color(0xFFE4C86A).withValues(alpha: 0.65),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(double.infinity, 48),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      ),
    );
  }

  Widget _buildBottomSignUpLink() {
    return TextButton(
      onPressed: _isLoading ? null : () => context.go(RouteNames.register),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.white.withValues(alpha: 0.90),
                fontWeight: FontWeight.w700,
              ),
          children: const [
            TextSpan(text: "Don't have an account? "),
            TextSpan(
              text: 'Sign Up',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleResendVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter your email and password first to resend the verification email.',
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.resendEmailVerification(
        email: email,
        password: password,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success
              ? AppTheme.softGreen
              : AppTheme.errorRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend verification email: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result.success && mounted) {
        final user = result.user;
        final userRole = user?.role;
        final email = user?.email.toLowerCase();

        // Enforce privileged emails for Admin only
        if (userRole == AppConstants.roleAdmin &&
            email != AppConstants.adminEmail.toLowerCase()) {
          await authService.signOut();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This account is not allowed to access the Admin dashboard.',
              ),
              backgroundColor: AppTheme.errorRed,
            ),
          );
          return;
        }

        // Navigate to appropriate home screen based on role
        String homeRoute;

        switch (userRole) {
          case AppConstants.roleSiteManager:
            homeRoute = RouteNames.siteManagerHome;
            break;
          case AppConstants.roleAdmin:
            homeRoute = RouteNames.adminHome;
            break;
          default:
            homeRoute = RouteNames.login;
        }

        context.go(homeRoute);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleForgotPassword() {
    showDialog(context: context, builder: (context) => _ForgotPasswordDialog());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your email address to receive a password reset link.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AppButton(
          text: 'Send Reset Link',
          onPressed: _isLoading ? null : _handleResetPassword,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Future<void> _handleResetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.resetPassword(
        _emailController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success
                ? AppTheme.softGreen
                : AppTheme.errorRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
