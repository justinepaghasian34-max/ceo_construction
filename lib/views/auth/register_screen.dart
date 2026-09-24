import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../utils/password_validator.dart';

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

  final String _selectedRole = AppConstants.roleSiteManager;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  static const _gold = Color(0xFFE4C86A);
  static const _navy = Color(0xFF0A2A47);
  static const _navyDeep = Color(0xFF051F36);

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.deepBlue, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isWide = size.width >= 960;
    final isShort = size.height < 760;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _navyDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Image_Background.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.48),
                    Colors.black.withValues(alpha: 0.22),
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: isWide
                ? _buildWideLayout(compact: isShort || keyboardOpen)
                : _buildNarrowLayout(keyboardOpen: keyboardOpen),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout({required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 28 : 40,
        vertical: compact ? 12 : 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 11, child: _buildBrandSide(compact: compact)),
          SizedBox(width: compact ? 20 : 32),
          Expanded(
            flex: 9,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 460,
                  maxHeight: MediaQuery.sizeOf(context).height,
                ),
                child: _buildRegisterPanel(compact: compact),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout({required bool keyboardOpen}) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isLoading ? null : () => context.go(RouteNames.login),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Sign in'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildRegisterPanel(compact: true),
              ),
            ),
          ),
        ],
      ),
    );

    // Only scroll when the keyboard covers the form.
    if (!keyboardOpen) return body;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).vertical,
        child: body,
      ),
    );
  }

  Widget _buildBrandSide({required bool compact}) {
    return Padding(
      padding: EdgeInsets.only(right: compact ? 8 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.white.withValues(alpha: 0.92),
                    child: Image.asset(
                      'assets/images/image.png',
                      height: compact ? 64 : 78,
                      width: compact ? 64 : 78,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'CITY ENGINEERING OFFICE',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        height: 1.1,
                      ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 18 : 28),
          Container(
            width: 56,
            height: 3,
            decoration: BoxDecoration(
              color: _gold,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          SizedBox(height: compact ? 14 : 20),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
              children: const [
                TextSpan(text: 'Engineering '),
                TextSpan(
                  text: 'Excellence.',
                  style: TextStyle(color: _gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Building Better Cities.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          SizedBox(height: compact ? 12 : 18),
          Text(
            'Create your account to monitor projects, materials, attendance, and site progress.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterPanel({required bool compact}) {
    final gap = compact ? 8.0 : 10.0;

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 22,
          compact ? 16 : 20,
          compact ? 18 : 22,
          compact ? 14 : 18,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create Account',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _navy,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _isLoading ? null : () => context.go(RouteNames.login),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.deepBlue,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
              Text(
                'Self-register as Resident Engineer only · other roles are admin-assigned',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              SizedBox(height: compact ? 12 : 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'First name',
                        icon: Icons.person_outline,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'Last name',
                        icon: Icons.person_outline,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap),
              InputDecorator(
                decoration: _fieldDecoration(
                  label: 'Position',
                  icon: Icons.badge_outlined,
                ),
                child: const Text(
                  'Resident Engineer',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              SizedBox(height: gap),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  label: 'Work email',
                  icon: Icons.mail_outline,
                ),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return 'Enter email';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'Password',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: validatePassword,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isLoading) _handleRegister();
                      },
                      decoration: _fieldDecoration(
                        label: 'Confirm',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirm password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return validatePassword(value);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(
                    _isLoading ? 'Creating…' : 'Register',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

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
          backgroundColor:
              result.success ? AppTheme.softGreen : AppTheme.errorRed,
        ),
      );

      if (result.success) {
        _passwordController.clear();
        _confirmPasswordController.clear();
        context.go(RouteNames.siteManagerOtp);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration failed. Please try again.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
