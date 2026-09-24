import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

class SiteManagerOtpScreen extends StatefulWidget {
  const SiteManagerOtpScreen({super.key});

  @override
  State<SiteManagerOtpScreen> createState() => _SiteManagerOtpScreenState();
}

class _SiteManagerOtpScreenState extends State<SiteManagerOtpScreen> with TickerProviderStateMixin {
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _codeFocus = List.generate(6, (_) => FocusNode());

  bool _isSending = false;
  bool _isVerifying = false;
  String? _error;

  Timer? _resendTimer;
  int _resendSeconds = 0;

  bool _autoSent = false;

  bool _entryVisible = false;
  int _focusedIndex = -1;

  late final AnimationController _shakeController;
  late final AnimationController _pulseController;
  late final List<AnimationController> _bounceControllers;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _bounceControllers = List.generate(
      6,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      ),
    );

    for (var i = 0; i < _codeFocus.length; i++) {
      _codeFocus[i].addListener(() {
        if (!mounted) return;
        if (_codeFocus[i].hasFocus) {
          setState(() {
            _focusedIndex = i;
          });
        } else if (_focusedIndex == i) {
          setState(() {
            _focusedIndex = -1;
          });
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _entryVisible = true;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoSent) {
      _autoSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sendEmailOtp();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocus) {
      f.dispose();
    }

    for (final b in _bounceControllers) {
      b.dispose();
    }
    _shakeController.dispose();
    _pulseController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String _readOtp() {
    return _codeControllers.map((c) => c.text.trim()).join();
  }

  bool get _isOtpComplete => _codeControllers.every((c) => c.text.trim().isNotEmpty);

  void _triggerError(String message) {
    setState(() {
      _error = message;
    });
    _shakeController.forward(from: 0);
  }

  void _setResendCooldown(int seconds) {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = seconds;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() {
          _resendSeconds = 0;
        });
        return;
      }
      setState(() {
        _resendSeconds -= 1;
      });
    });
  }

  Future<void> _sendEmailOtp() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendEmailOtp',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call(<String, dynamic>{});
      if (!mounted) return;
      _setResendCooldown(60);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A 6-digit code was sent to your email. Check Inbox and Spam.'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'resource-exhausted') {
        _setResendCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Code already sent. Wait a minute to resend.')),
        );
        return;
      }
      setState(() {
        if (e.code == 'failed-precondition') {
          _error =
              'The code could not be emailed yet. Gmail blocked the sender login. Create a Gmail App Password and send it here so sending can be turned on.';
        } else {
          final msg = e.message ?? 'Failed to send code.';
          _error = 'Failed to send code (${e.code}): $msg';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send OTP: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _verifyEmailOtp() async {
    final otp = _readOtp();
    if (otp.length != 6) {
      _triggerError('Enter the 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyEmailOtp');
      await callable.call(<String, dynamic>{'code': otp});
      await _markOtpVerifiedLocallyAndExit();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _triggerError(e.message ?? 'Invalid code.');
    } catch (e) {
      if (!mounted) return;
      _triggerError('Verification failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _markOtpVerifiedLocallyAndExit() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    await AuthService.instance.markOtpSessionVerified();

    try {
      await u.reload();
      await u.getIdToken(true);
    } catch (_) {}

    await AuthService.instance.refreshUserData();
    await AuthService.instance.hydrateOtpSession();
    await AuthService.instance.markOtpSessionVerified();

    if (!mounted) return;
    final role = AuthService.instance.userRole;
    switch (role) {
      case AppConstants.roleAdmin:
        context.go(RouteNames.adminHome);
        break;
      case AppConstants.rolePayroll:
        context.go(RouteNames.payrollHome);
        break;
      case AppConstants.roleMaterials:
        context.go(RouteNames.materialsHome);
        break;
      case AppConstants.roleCeo:
        context.go(RouteNames.ceoHome);
        break;
      default:
        context.go(RouteNames.siteManagerHome);
    }
  }

  Widget _buildOtpBoxes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final gap = 10.0;
        final raw = (w - 5 * gap) / 6;
        final boxW = raw.clamp(44.0, 54.0);
        final boxH = 58.0;

        return AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_shakeController.value);
            final dir = ((t * 8).floor().isEven) ? 1.0 : -1.0;
            final dx = (1 - t) * 14 * dir;
            return Transform.translate(
              offset: Offset(dx.toDouble(), 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final isFocused = _focusedIndex == i;
              final bounce = TweenSequence<double>([
                TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 55),
                TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 45),
              ]).animate(_bounceControllers[i]);

              return Padding(
                padding: EdgeInsets.only(right: i == 5 ? 0 : gap),
                child: SizedBox(
                  width: boxW,
                  height: boxH,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _pulseController,
                      _bounceControllers[i],
                    ]),
                    builder: (context, _) {
                      final pulse = isFocused
                          ? (0.35 + 0.65 * _pulseController.value)
                          : 0.0;
                      final glowOpacity = isFocused ? (0.10 + 0.22 * pulse) : 0.06;
                      final borderOpacity = isFocused ? (0.45 + 0.35 * pulse) : 0.12;
                      final borderWidth = isFocused ? (2.0 + 1.2 * pulse) : 1.0;

                      return AnimatedScale(
                        scale: isFocused ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Transform.scale(
                          scale: bounce.value,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (isFocused ? AppTheme.residentBlue : const Color(0xFFCBD5E1))
                                    .withValues(alpha: borderOpacity),
                                width: borderWidth,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isFocused ? AppTheme.residentBlue : Colors.black)
                                      .withValues(alpha: glowOpacity),
                                  blurRadius: isFocused ? (18 + 8 * pulse) : 10,
                                  spreadRadius: isFocused ? 1.5 : 0.0,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: TextField(
                              controller: _codeControllers[i],
                              focusNode: _codeFocus[i],
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              maxLength: 1,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) {
                                final value = v.trim();
                                if (value.isNotEmpty) {
                                  _bounceControllers[i].forward(from: 0);
                                }
                                if (value.isNotEmpty && i < 5) {
                                  _codeFocus[i + 1].requestFocus();
                                }
                                if (value.isEmpty && i > 0) {
                                  _codeFocus[i - 1].requestFocus();
                                }
                                if (mounted) {
                                  setState(() {
                                    _error = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final email = (firebaseUser?.email ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: AnimatedOpacity(
            opacity: _entryVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: _entryVisible ? Offset.zero : const Offset(0, 0.07),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Enter Code',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a 6-digit verification code to the email you registered. Enter it below. Check Inbox and Spam.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 22),
                      _buildOtpBoxes(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: ((_error ?? '').trim().isEmpty)
                            ? const SizedBox(height: 16)
                            : Padding(
                                key: ValueKey<String>(_error ?? ''),
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  _error!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: const Color(0xFFDC2626),
                                        fontWeight: FontWeight.w800,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      _AnimatedVerifyButton(
                        enabled: _isOtpComplete && !_isVerifying,
                        loading: _isVerifying,
                        label: 'Verify',
                        onPressed: _isVerifying
                            ? null
                            : () {
                                if (!_isOtpComplete) {
                                  _triggerError('Enter the 6-digit code.');
                                  return;
                                }
                                _verifyEmailOtp();
                              },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Didn\'t receive the code?',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: (_isSending || _resendSeconds > 0) ? null : _sendEmailOtp,
                            child: Text(
                              _resendSeconds > 0 ? 'Resend in $_resendSeconds s' : 'Resend',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedVerifyButton extends StatefulWidget {
  const _AnimatedVerifyButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
    this.label = 'Verify',
  });

  final bool enabled;
  final bool loading;
  final VoidCallback? onPressed;
  final String label;

  @override
  State<_AnimatedVerifyButton> createState() => _AnimatedVerifyButtonState();
}

class _AnimatedVerifyButtonState extends State<_AnimatedVerifyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.enabled ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedVerifyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _popController.forward(from: 0);
      } else {
        _popController.reverse(from: 1);
      }
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final bg = enabled ? AppTheme.residentBlue : const Color(0xFF94A3B8);
    final fg = Colors.white;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedBuilder(
        animation: _popController,
        builder: (context, child) {
          final t = Curves.easeOutBack.transform(_popController.value);
          final scale = enabled ? (0.98 + 0.06 * t) : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: 54,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: enabled ? 0.22 : 0.10),
                blurRadius: enabled ? 18 : 10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.loading ? null : widget.onPressed,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: widget.loading
                      ? const SizedBox(
                          key: ValueKey<String>('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.label,
                          key: const ValueKey<String>('text'),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
