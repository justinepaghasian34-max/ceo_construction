import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../core/constants/app_constants.dart';
import 'hive_service.dart';

/// Enforces idle timeout and absolute session lifetime.
/// Firebase ID tokens already expire in ~1 hour; this also expires the
/// refresh session so a stolen device is not usable indefinitely.
class SessionTimeoutService with WidgetsBindingObserver {
  SessionTimeoutService._();
  static final SessionTimeoutService instance = SessionTimeoutService._();

  static const _sessionKey = 'auth_session';

  Timer? _ticker;
  bool _started = false;

  Map<dynamic, dynamic>? _sessionMap() {
    final raw = HiveService.instance.settingsBox.get(_sessionKey);
    if (raw is Map) return raw;
    return null;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(enforce());
    });
    unawaited(enforce());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> beginSession(String uid) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await HiveService.instance.settingsBox.put(_sessionKey, <String, dynamic>{
      'uid': uid,
      'startedAtMs': now,
      'lastActivityMs': now,
    });
  }

  Future<void> clearSession() async {
    await HiveService.instance.settingsBox.delete(_sessionKey);
  }

  void recordActivity() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final current = _sessionMap() ?? <String, dynamic>{};
    HiveService.instance.settingsBox.put(_sessionKey, <String, dynamic>{
      ...Map<String, dynamic>.from(current),
      'uid': uid,
      'lastActivityMs': DateTime.now().millisecondsSinceEpoch,
      if (current['startedAtMs'] == null)
        'startedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  bool get isExpired {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final data = _sessionMap();
    if (data == null) return true;

    final storedUid = (data['uid'] ?? '').toString();
    if (storedUid.isNotEmpty && storedUid != uid) return true;

    final now = DateTime.now();
    final startedMs = data['startedAtMs'];
    final activityMs = data['lastActivityMs'];

    if (startedMs is int) {
      final started = DateTime.fromMillisecondsSinceEpoch(startedMs);
      if (now.difference(started) > AppConstants.sessionMaxLifetime) {
        return true;
      }
    } else {
      return true;
    }

    if (activityMs is int) {
      final last = DateTime.fromMillisecondsSinceEpoch(activityMs);
      if (now.difference(last) > AppConstants.sessionIdleTimeout) {
        return true;
      }
    }

    return false;
  }

  Future<void> enforce() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    if (!isExpired) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await HiveService.instance.clearUser();
    } catch (_) {}
    await clearSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(enforce());
    }
  }
}

/// Records pointer activity so idle timeout resets while the user is working.
class SessionActivityListener extends StatelessWidget {
  const SessionActivityListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SessionTimeoutService.instance.recordActivity(),
      child: child,
    );
  }
}
