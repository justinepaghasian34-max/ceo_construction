import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/site_weather_provider.dart';
import '../services/firebase_service.dart';
import '../services/local_notification_service.dart';

/// Pushes weather snapshots to Firestore and writes admin notification records
/// so that any admin device sees a real-time weather alert for every site.
class WeatherNotificationService {
  WeatherNotificationService._();
  static final WeatherNotificationService instance =
      WeatherNotificationService._();

  static const int _baseNotificationId = 7700;

  /// Call this from the RE home screen after weather loads.
  /// Writes / updates a snapshot doc in `site_weather_snapshots` and,
  /// when rain is detected, also creates a notification in `notifications`
  /// (the same collection already used by the app's NotificationsScreen).
  Future<void> publishSiteWeather(ProjectSiteWeather siteWeather) async {
    final fs = FirebaseService.instance.firestore;

    // 1. Upsert the snapshot so the admin map sees fresh data.
    await fs
        .collection('site_weather_snapshots')
        .doc(siteWeather.projectId)
        .set({
      'projectId': siteWeather.projectId,
      'projectName': siteWeather.projectName,
      'location': siteWeather.location,
      'lat': siteWeather.lat,
      'lon': siteWeather.lon,
      'tempC': siteWeather.weather.temperatureC,
      'condition': siteWeather.weather.condition,
      'description': siteWeather.weather.description,
      'humidity': siteWeather.weather.humidity,
      'windSpeedMs': siteWeather.weather.windSpeedMs,
      'fetchedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. If it is raining (or thunderstorm / drizzle), write an admin
    //    notification and fire a local push on the RE device as well.
    if (siteWeather.isRaining) {
      await _writeAdminRainNotification(siteWeather);
      await _showLocalRainAlert(siteWeather);
    }
  }

  Future<void> _writeAdminRainNotification(
      ProjectSiteWeather siteWeather) async {
    final fs = FirebaseService.instance.firestore;

    // Deduplicate: only write once per hour per project to avoid spam.
    final windowStart =
        DateTime.now().subtract(const Duration(hours: 1));
    final existing = await fs
        .collection('notifications')
        .where('type', isEqualTo: 'weather_rain_alert')
        .where('projectId', isEqualTo: siteWeather.projectId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return; // already notified this hour

    final tempStr =
        siteWeather.weather.temperatureC.toStringAsFixed(0);
    final conditionStr = siteWeather.weather.condition;

    await fs.collection('notifications').add({
      'type': 'weather_rain_alert',
      'title': '🌧 Rain Alert — ${siteWeather.projectName}',
      'message':
          '${siteWeather.location} is currently reporting $conditionStr '
          'at $tempStr°C. '
          'Consider pausing outdoor work at this site.',
      'projectId': siteWeather.projectId,
      'projectName': siteWeather.projectName,
      'condition': conditionStr,
      'tempC': siteWeather.weather.temperatureC,
      'lat': siteWeather.lat,
      'lon': siteWeather.lon,
      'isRead': false,
      'audienceRole': 'admin',
      'targetRole': 'admin',
      'userId': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _showLocalRainAlert(ProjectSiteWeather siteWeather) async {
    // Use a stable ID derived from projectId so duplicate alerts collapse.
    final id = _baseNotificationId +
        siteWeather.projectId.hashCode.abs() % 1000;
    final tempStr =
        siteWeather.weather.temperatureC.toStringAsFixed(0);
    await LocalNotificationService.instance.showNotification(
      id: id,
      title: '🌧 Rain at ${siteWeather.projectName}',
      body:
          '${siteWeather.weather.condition} · $tempStr°C  '
          '— Plan site activities accordingly.',
    );
  }

  /// Convenience helper: publish weather for every site in a list.
  Future<void> publishAll(List<ProjectSiteWeather> sites) async {
    for (final site in sites) {
      await publishSiteWeather(site);
    }
  }
}
