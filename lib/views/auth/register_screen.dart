import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_button.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();


  String _selectedRole = AppConstants.roleSiteManager;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWideWebLayout = size.width >= 900;

    if (isWideWebLayout) {
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      const Color(0xFF051F36).withValues(alpha: 0.30),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Form(
                      key: _formKey,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildWebBrandPanel(),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            if (!mounted) return;
                                            context.go(RouteNames.login);
                                          },
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Back to Sign In'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildWebRegisterCard(context),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(RouteNames.login);
          },
        ),
        title: const Text(
          'Create Account',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppTheme.deepBlue,
        foregroundColor: AppTheme.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Register for CEO Construction Monitoring',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can self-register as Admin, Site Manager, Material Monitoring, or Payroll.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Admin and Site Manager accounts must verify the email OTP. Payroll and Material Monitoring accounts can continue immediately.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                    const SizedBox(height: 24),
                    _buildFormFields(context),
                    const SizedBox(height: 24),
                    AppButton(
                      text: 'Register',
                      onPressed: _isLoading ? null : _handleRegister,
                      isLoading: _isLoading,
                      width: double.infinity,
                      icon: Icons.person_add,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (!mounted) return;
                              context.go(RouteNames.login);
                            },
                      child: const Text('Already have an account? Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebRegisterCard(BuildContext context) {
    return Card(
      elevation: 10,
      color: AppTheme.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Create Account',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.deepBlue,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can self-register as Admin, Site Manager, Material Monitoring, or Payroll.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Site Manager accounts must verify OTP (Email or SMS). Payroll and Material Monitoring accounts can continue immediately.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            const SizedBox(height: 20),
            _buildFormFields(context),
            const SizedBox(height: 20),
            AppButton(
              text: 'Register',
              onPressed: _isLoading ? null : _handleRegister,
              isLoading: _isLoading,
              width: double.infinity,
              icon: Icons.person_add,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      if (!mounted) return;
                      context.go(RouteNames.login);
                    },
              child: const Text('Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebBrandPanel() {
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: AppTheme.white,
          letterSpacing: 0.6,
          height: 1.05,
        );
    final sub = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppTheme.white.withValues(alpha: 0.90),
          fontWeight: FontWeight.w700,
          height: 1.35,
        );
    const gold = Color(0xFFB79B4D);
    final taglineBase = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: AppTheme.white,
          height: 1.1,
        );
    final taglineAccent = taglineBase?.copyWith(color: gold);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/image.png',
                height: 92,
                width: 92,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'CITY ENGINEERING OFFICE',
                  style: headline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 2,
            width: 66,
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: taglineBase,
              children: [
                const TextSpan(text: 'Engineering '),
                TextSpan(text: 'Excellence.', style: taglineAccent),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Building Better Cities.',
            style: taglineBase,
          ),
          const SizedBox(height: 18),
          Text(
            'Register to access construction monitoring: projects, progress, materials, attendance, and AI insights.',
            style: sub,
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;

                final firstNameField = TextFormField(
                  controller: _firstNameController,
                  decoration: const InputDecoration(labelText: 'First Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter first name';
                    }
                    return null;
                  },
                );

                final lastNameField = TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter last name';
                    }
                    return null;
                  },
                );

                return isNarrow
                    ? Column(
                        children: [
                          firstNameField,
                          const SizedBox(height: 16),
                          lastNameField,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: firstNameField),
                          const SizedBox(width: 12),
                          Expanded(child: lastNameField),
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              items: const [
                DropdownMenuItem(
                  value: AppConstants.roleAdmin,
                  child: Text('Admin'),
                ),
                DropdownMenuItem(
                  value: AppConstants.roleSiteManager,
                  child: Text('Site Manager'),
                ),
                DropdownMenuItem(
                  value: AppConstants.roleMaterials,
                  child: Text('Material Monitoring'),
                ),
                DropdownMenuItem(
                  value: AppConstants.rolePayroll,
                  child: Text('Payroll Monitoring'),
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'Position',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedRole = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'OTP Delivery Method',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mediumGray,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Email',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Work Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) {
                  return 'Please enter email';
                }
                if (!v.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
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
                  return 'Please enter password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService
          .registerWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            role: _selectedRole,
          )
          .timeout(
            const Duration(seconds: 18),
            onTimeout: () {
              final signedIn = FirebaseAuth.instance.currentUser != null;
              return AuthResult(
                success: signedIn,
                requiresEmailVerification: signedIn,
                requiresOtp: signedIn,
                message: signedIn
                    ? 'Account created. Continue to enter your verification code.'
                    : 'Registration timed out. If this email is already registered, sign in instead.',
              );
            },
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

      if (result.success) {
        context.go(RouteNames.siteManagerOtp);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $e'),
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
}
