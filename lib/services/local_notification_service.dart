import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);

    if (!kIsWeb) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _initialized = true;
  }

  Future<void> scheduleRainAlert({
    required int id,
    required DateTime dateTime,
    required String title,
    required String body,
  }) async {
    await initialize();

    final scheduled = tz.TZDateTime.from(dateTime, tz.local);

    const android = AndroidNotificationDetails(
      'weather_alerts',
      'Weather Alerts',
      channelDescription: 'Rain forecast alerts for site managers',
      importance: Importance.high,
      priority: Priority.high,
    );

    const ios = DarwinNotificationDetails();

    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  Future<void> showMaterialRequestAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();

    const android = AndroidNotificationDetails(
      'material_requests',
      'Material Requests',
      channelDescription: 'Popup alerts when a resident engineer requests materials',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);
    await _plugin.show(id, title, body, details);
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();

    const android = AndroidNotificationDetails(
      'sync_updates',
      'Sync Updates',
      channelDescription: 'Notifications about queued or completed sync items',
      importance: Importance.high,
      priority: Priority.high,
    );

    const ios = DarwinNotificationDetails();

    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.show(id, title, body, details);
  }
}
