import 'dart:ui';

import 'package:flutter/material.dart';
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

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _signInButtonKey = GlobalKey();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late final AnimationController _pageController;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _logoFade;
  late final Animation<double> _brandFade;

  static const _gold = Color(0xFFE4C86A);
  static const _navy = Color(0xFF0A2A47);
  static const _navyDeep = Color(0xFF051F36);

  @override
  void initState() {
    super.initState();

    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _cardFade = CurvedAnimation(
      parent: _pageController,
      curve: const Interval(0.15, 1.00, curve: Curves.easeOutCubic),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0.07, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageController,
        curve: const Interval(0.15, 1.00, curve: Curves.easeOutCubic),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _pageController,
      curve: const Interval(0.30, 1.00, curve: Curves.easeOut),
    );
    _brandFade = CurvedAnimation(
      parent: _pageController,
      curve: const Interval(0.05, 0.85, curve: Curves.easeOutCubic),
    );

    _emailFocusNode.addListener(_onFocusChanged);
    _passwordFocusNode.addListener(_onFocusChanged);
    _pageController.forward();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {});

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!keyboardOpen) return;
    if (!_emailFocusNode.hasFocus && !_passwordFocusNode.hasFocus) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final signInContext = _signInButtonKey.currentContext;
      if (signInContext == null) return;
      Scrollable.ensureVisible(
        signInContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.9,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isShort = size.height < 740;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = isShort || keyboardOpen;
    final isWideWebLayout = size.width >= 900;

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
          // Subtle cinematic scrim — photo stays vivid like the reference
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.08),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.22),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: keyboardOpen
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width < 480 ? 18 : 24,
                  vertical: size.height < 700 ? 16 : 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isWideWebLayout ? 1100 : 480,
                      minHeight: keyboardOpen
                          ? 0
                          : (size.height - MediaQuery.paddingOf(context).vertical),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final targetCardWidth = 440.0;
                        final cardWidth = constraints.maxWidth < targetCardWidth
                            ? constraints.maxWidth
                            : targetCardWidth;

                        final card = SizedBox(
                          width: cardWidth,
                          child: FadeTransition(
                            opacity: _cardFade,
                            child: SlideTransition(
                              position: _cardSlide,
                              child: _buildSignInCard(
                                compact: compact,
                                showResendVerification: true,
                              ),
                            ),
                          ),
                        );

                        final child = isWideWebLayout
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: _buildWebBrandPanel(compact: compact),
                                  ),
                                  const SizedBox(width: 28),
                                  Expanded(
                                    flex: 4,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: card,
                                    ),
                                  ),
                                ],
                              )
                            : Align(
                                alignment: keyboardOpen
                                    ? Alignment.topCenter
                                    : Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!keyboardOpen) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 20),
                                        child: _buildMobileBrandHeader(compact: compact),
                                      ),
                                    ],
                                    card,
                                  ],
                                ),
                              );

                        return Form(
                          key: _formKey,
                          child: child,
                        );
                      },
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

  Widget _buildWebBrandPanel({required bool compact}) {
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.8,
          height: 1.05,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
          ],
        );
    final sub = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.92),
          fontWeight: FontWeight.w600,
          height: 1.45,
          shadows: const [
            Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 1)),
          ],
        );
    final tagline = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.15,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
          ],
        );

    return FadeTransition(
      opacity: _brandFade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.05, 0),
          end: Offset.zero,
        ).animate(_brandFade),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/image.png',
                      height: compact ? 76 : 96,
                      width: compact ? 76 : 96,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text('CITY ENGINEERING\nOFFICE', style: headline)),
                ],
              ),
              SizedBox(height: compact ? 14 : 20),
              Container(
                height: 3,
                width: compact ? 56 : 68,
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 14 : 18),
              RichText(
                text: TextSpan(
                  style: tagline,
                  children: [
                    const TextSpan(text: 'Engineering '),
                    TextSpan(text: 'Excellence.', style: TextStyle(color: _gold)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('Building Better Cities.', style: tagline),
              SizedBox(height: compact ? 14 : 20),
              Text(
                'Construction monitoring dashboard for progress, materials, attendance, and AI-powered insights.',
                style: sub,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBrandHeader({required bool compact}) {
    return FadeTransition(
      opacity: _brandFade,
      child: Column(
        children: [
          Image.asset(
            'assets/images/image.png',
            height: compact ? 56 : 72,
            width: compact ? 56 : 72,
          ),
          const SizedBox(height: 10),
          Text(
            'CITY ENGINEERING OFFICE',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.6,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInCard({
    required bool compact,
    required bool showResendVerification,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoSize = screenWidth >= 900 ? 72.0 : (screenWidth >= 420 ? 64.0 : 56.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(19),
            ),
            padding: compact
                ? const EdgeInsets.fromLTRB(18, 20, 18, 16)
                : const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/image.png',
                        height: logoSize,
                        width: logoSize,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Text(
                        'SIGN IN',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 16 : 22),
                _buildNewFields(compact: compact),
                SizedBox(height: compact ? 12 : 16),
                KeyedSubtree(
                  key: _signInButtonKey,
                  child: _GoldSignInButton(
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _handleLogin,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                if (showResendVerification)
                  TextButton(
                    onPressed: _isLoading ? null : _handleResendVerification,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text(
                      "Didn't receive verification code?",
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                _buildBottomSignUpLink(compact: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewFields({required bool compact}) {
    Widget buildField({
      required String label,
      required String hint,
      required IconData icon,
      required FocusNode focusNode,
      required TextEditingController controller,
      required TextInputType keyboardType,
      required String? Function(String?) validator,
      bool obscureText = false,
      Widget? suffix,
    }) {
      final focused = focusNode.hasFocus;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? _gold : Colors.white.withValues(alpha: 0.95),
                width: focused ? 1.8 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              obscureText: obscureText,
              style: const TextStyle(
                color: Color(0xFF0B2B4A),
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: AppTheme.mediumGray.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(icon, color: const Color(0xFF4B6076)),
                suffixIcon: suffix,
                filled: false,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: compact ? 12 : 14,
                ),
              ),
              validator: validator,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildField(
          label: 'Email address',
          hint: 'Enter your email',
          icon: Icons.email_outlined,
          focusNode: _emailFocusNode,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your email';
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value.trim())) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        SizedBox(height: compact ? 14 : 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Password',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
              ),
            ),
            TextButton(
              onPressed: _isLoading ? null : _handleForgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Forgot Password?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        buildField(
          label: '',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          focusNode: _passwordFocusNode,
          controller: _passwordController,
          keyboardType: TextInputType.visiblePassword,
          obscureText: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: const Color(0xFF4B6076),
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildBottomSignUpLink({required bool compact}) {
    return TextButton(
      onPressed: _isLoading ? null : () => context.go(RouteNames.register),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: compact ? 12 : 14,
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
            'Enter your email and password first to resend the 6-digit code.',
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

      if (result.success &&
          (result.requiresOtp || result.requiresEmailVerification)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppTheme.softGreen,
          ),
        );
        context.go(RouteNames.siteManagerOtp);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor:
              result.success ? AppTheme.softGreen : AppTheme.errorRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend verification code: $e'),
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

        if (result.requiresOtp || result.requiresEmailVerification) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.message),
                backgroundColor: AppTheme.softGreen,
              ),
            );
            context.go(RouteNames.siteManagerOtp);
          }
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
          case AppConstants.rolePayroll:
            homeRoute = RouteNames.payrollHome;
            break;
          case AppConstants.roleMaterials:
            homeRoute = RouteNames.materialsHome;
            break;
          case AppConstants.roleCeo:
            homeRoute = RouteNames.ceoHome;
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
    _pageController.dispose();
    _emailFocusNode.removeListener(_onFocusChanged);
    _passwordFocusNode.removeListener(_onFocusChanged);
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class _GoldSignInButton extends StatefulWidget {
  const _GoldSignInButton({
    required this.onPressed,
    required this.isLoading,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<_GoldSignInButton> createState() => _GoldSignInButtonState();
}

class _GoldSignInButtonState extends State<_GoldSignInButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE4C86A);
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : (_hovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled
                    ? [
                        _hovered ? const Color(0xFFEFD98A) : gold,
                        const Color(0xFFC9A84C),
                      ]
                    : [gold.withValues(alpha: 0.5), gold.withValues(alpha: 0.4)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: gold.withValues(alpha: _hovered ? 0.45 : 0.32),
                        blurRadius: _hovered ? 18 : 12,
                        offset: Offset(0, _hovered ? 8 : 6),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF0B2B4A),
                      ),
                    )
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                        color: Color(0xFF0B2B4A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 700;
    final insetH = isWide ? (width * 0.22).clamp(24.0, 340.0) : 24.0;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: insetH, vertical: 24),
      title: const Text('Reset Password'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email. If an account exists, we will send a reset link that expires in 1 hour.',
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
