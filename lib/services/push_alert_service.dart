import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

class PushAlertService {
  PushAlertService._();

  static final PushAlertService instance = PushAlertService._();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _started = false;

  Future<void> ensureRegistered() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final role = user.role;
      if (role == AppConstants.roleMaterials ||
          role == AppConstants.roleAdmin) {
        try {
          await messaging.subscribeToTopic('role-materials');
        } catch (_) {}
      }
    } catch (_) {}

    if (_started) return;
    _started = true;

    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      final title = message.notification?.title ??
          (message.data['title'] ?? 'CEO Construction').toString();
      final body = message.notification?.body ??
          (message.data['body'] ?? message.data['message'] ?? '').toString();
      if (title.isEmpty && body.isEmpty) return;
      if (kIsWeb) return;
      try {
        await LocalNotificationService.instance.showMaterialRequestAlert(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: title,
          body: body,
        );
      } catch (_) {}
    });
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    _foregroundSub = null;
    _started = false;
  }
}
