import 'package:intl/intl.dart';

import 'geo_tag_service.dart';
import 'local_notification_service.dart';
import 'weather_service.dart';

class WeatherAlertService {
  WeatherAlertService._();

  static final WeatherAlertService instance = WeatherAlertService._();

  static const int _rainAlertNotificationId = 2201;

  Future<DateTime?> scheduleNextRainAlertForCurrentLocation() async {
    final now = DateTime.now();

    final geoTag = await GeoTagService.instance.captureGeoTag();
    final lat = (geoTag?['lat'] as num?)?.toDouble();
    final lon = (geoTag?['lng'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      return null;
    }

    final hourly = await WeatherService.instance.getHourlyForecastByCoordinatesAndDate(
      lat: lat,
      lon: lon,
      date: DateTime(now.year, now.month, now.day),
    );

    // Forecast endpoint returns 3-hour increments for the next ~5 days.
    // We'll look for the earliest upcoming entry that indicates rain.
    DateTime? nextRain;

    for (final h in hourly) {
      if (!h.dateTime.isAfter(now)) continue;
      final cond = h.condition.toLowerCase();
      if (cond.contains('rain') || cond.contains('drizzle') || cond.contains('thunderstorm')) {
        nextRain = h.dateTime;
        break;
      }
    }

    if (nextRain == null) {
      return null;
    }

    final timeLabel = DateFormat('h:mm a').format(nextRain);

    await LocalNotificationService.instance.scheduleRainAlert(
      id: _rainAlertNotificationId,
      dateTime: nextRain,
      title: 'Rain forecast',
      body: 'Expected rain around $timeLabel. Plan site activities accordingly.',
    );

    return nextRain;
  }
}
