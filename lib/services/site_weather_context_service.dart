import 'weather_service.dart';

/// Current conditions + forecast bundle for site manager UI and GovTrack AI.
class SiteWeatherBundle {
  const SiteWeatherBundle({
    required this.locationLabel,
    required this.now,
    required this.forecastDays,
    required this.siteAdvice,
    required this.windLabel,
    required this.visibilityLabel,
    required this.fetchedAt,
    this.liveReport,
    this.fromProjectPin = false,
    this.latitude,
    this.longitude,
  });

  final String locationLabel;
  final WeatherNow now;
  final List<WeatherDailyForecast> forecastDays;
  final String siteAdvice;
  final String windLabel;
  final String visibilityLabel;
  final DateTime fetchedAt;
  final LiveWeatherReport? liveReport;
  final bool fromProjectPin;
  final double? latitude;
  final double? longitude;

  Map<String, dynamic> toAiJson() {
    return {
      'location': locationLabel,
      'fromProjectPin': fromProjectPin,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'fetchedAt': fetchedAt.toIso8601String(),
      if (liveReport != null) 'liveSiteContext': liveReport!.toMap(),
      'current': {
        'tempC': now.temperatureC,
        'feelsLikeC': now.feelsLikeC,
        'description': now.description,
        'condition': now.condition,
        'humidity': now.humidity,
        'windSpeedMs': now.windSpeedMs,
        'visibilityKm': now.visibilityKm,
      },
      'forecast': forecastDays.take(7).map((d) {
        return {
          'date': '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}',
          'minTempC': d.minTempC,
          'maxTempC': d.maxTempC,
          'condition': d.condition,
          'pop': d.pop,
          'humidity': d.humidity,
          'windSpeedMs': d.windSpeedMs,
        };
      }).toList(),
      'siteAdvice': siteAdvice,
    };
  }
}

class SiteWeatherContextService {
  SiteWeatherContextService._();
  static final instance = SiteWeatherContextService._();

  final _weather = WeatherService.instance;
  SiteWeatherBundle? _cache;
  String? _cacheKey;
  DateTime? _cacheTime;

  static const _cacheTtl = Duration(minutes: 20);

  String normalizeLocation(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    if (s.toLowerCase() == 'manila' || s.toLowerCase() == 'manila,ph') {
      return s;
    }
    if (!s.contains(',')) return '$s, Philippines';
    return s;
  }

  void clearCache() {
    _cache = null;
    _cacheKey = null;
    _cacheTime = null;
  }

  Future<SiteWeatherBundle> load({
    String? projectLocation,
    double? latitude,
    double? longitude,
    String? locationLabel,
    bool forceRefresh = false,
  }) async {
    final hasPin = _validPin(latitude, longitude);
    final named = normalizeLocation(projectLocation);
    if (!hasPin && named.isEmpty) {
      throw StateError(
        'No project location pin. Pin the site on the map so weather is for that barangay, not Manila.',
      );
    }

    final key = hasPin
        ? 'pin:${latitude!.toStringAsFixed(4)},${longitude!.toStringAsFixed(4)}'
        : named;
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cacheKey == key &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }

    late final WeatherNow current;
    late final List<WeatherDailyForecast> forecast;
    if (hasPin) {
      current = await _weather.getCurrentWeatherByCoordinates(
        lat: latitude!,
        lon: longitude!,
      );
      forecast = await _weather.get7DayForecastByCoordinates(
        lat: latitude,
        lon: longitude,
      );
    } else {
      current = await _weather.getCurrentWeatherByCity(named);
      forecast = await _weather.get7DayForecastByCity(named);
    }

    LiveWeatherReport liveReport;
    try {
      final openMeteoMap = await _weather.getProjectWeatherData(
        lat: current.lat,
        lon: current.lon,
        location: hasPin
            ? '${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)}'
            : named,
      );
      if (openMeteoMap['temperature'] == 'Unavailable') {
        liveReport = hasPin
            ? await _weather.getOpenMeteoLiveReport(
                lat: latitude!,
                lon: longitude!,
              )
            : await _weather.getLiveWeatherReportByCity(named);
      } else {
        liveReport = LiveWeatherReport(
          temperature: openMeteoMap['temperature']!,
          humidity: openMeteoMap['humidity']!,
          environmentLighting: openMeteoMap['lighting']!,
          rainForecast: openMeteoMap['rain_status']!,
          rainIsComing: openMeteoMap['rain_status']!.contains('ALERT'),
          rawTempC: current.temperatureC,
          rawHumidity: current.humidity,
          isDaylight: openMeteoMap['lighting']!.contains('Daylight'),
          provider: 'open-meteo',
        );
      }
    } catch (_) {
      try {
        liveReport = hasPin
            ? await _weather.getOpenMeteoLiveReport(
                lat: latitude!,
                lon: longitude!,
              )
            : await _weather.getLiveWeatherReportByCity(named);
      } catch (__) {
        liveReport = LiveWeatherReport(
          temperature: '${current.temperatureC.toStringAsFixed(0)}°C',
          humidity: current.humidity != null ? '${current.humidity}%' : 'Unavailable',
          environmentLighting: 'Daylight Operations',
          rainForecast: 'Clear skies.',
          rawTempC: current.temperatureC,
          rawHumidity: current.humidity,
        );
      }
    }

    final windLabel = _windLabel(current.windSpeedMs);
    final visibilityLabel = _visibilityLabel(current.visibilityKm);
    final advice = _siteAdvice(
      condition: current.condition,
      description: current.description,
      tempC: current.temperatureC,
      humidity: current.humidity,
      windMs: current.windSpeedMs,
      popToday: forecast.isNotEmpty ? forecast.first.pop : null,
      liveReport: liveReport,
    );

    final label = (locationLabel ?? '').trim().isNotEmpty
        ? locationLabel!.trim()
        : (current.cityName?.isNotEmpty == true ? current.cityName! : named);
    final bundle = SiteWeatherBundle(
      locationLabel: label,
      fromProjectPin: hasPin,
      latitude: hasPin ? latitude : current.lat,
      longitude: hasPin ? longitude : current.lon,
      now: current,
      forecastDays: forecast,
      siteAdvice: advice,
      windLabel: windLabel,
      visibilityLabel: visibilityLabel,
      fetchedAt: now,
      liveReport: liveReport,
    );

    _cache = bundle;
    _cacheKey = key;
    _cacheTime = now;
    return bundle;
  }

  static bool _validPin(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    if (lat.abs() > 90 || lon.abs() > 180) return false;
    if (lat == 0 && lon == 0) return false;
    return true;
  }

  static String _windLabel(double? ms) {
    if (ms == null) return '—';
    if (ms < 2) return 'Light';
    if (ms < 6) return 'Moderate';
    if (ms < 10) return 'Fresh';
    return 'Strong';
  }

  static String _visibilityLabel(double? km) {
    if (km == null) return '—';
    if (km >= 10) return 'Excellent';
    if (km >= 5) return 'Good';
    if (km >= 2) return 'Fair';
    return 'Poor';
  }

  static String _siteAdvice({
    required String condition,
    required String description,
    required double tempC,
    required int? humidity,
    required double? windMs,
    required double? popToday,
    LiveWeatherReport? liveReport,
  }) {
    if (liveReport != null && liveReport.rainIsComing) {
      return liveReport.rainForecast;
    }
    if (liveReport != null && !liveReport.isDaylight) {
      return 'Night work — verify site lighting and use Class 3 high-visibility PPE.';
    }

    final c = condition.toLowerCase();
    final pop = popToday ?? 0;

    if (c.contains('thunder') || pop > 0.6) {
      return 'Heavy rain risk — postpone concrete pours and electrical roof work.';
    }
    if (c.contains('rain') || c.contains('drizzle') || pop > 0.35) {
      return 'Wet conditions — use covered curing and non-slip walkways.';
    }
    if (tempC >= 35) {
      return 'Extreme heat — schedule hydration breaks and avoid midday pours.';
    }
    if (tempC >= 32 && (humidity ?? 0) > 70) {
      return 'Hot and humid — rotate crews and monitor heat stress.';
    }
    if (windMs != null && windMs > 10) {
      return 'High winds — secure scaffolding and suspend crane lifts.';
    }
    if ((c.contains('clear') || c.contains('cloud')) && tempC >= 20 && tempC <= 32) {
      return 'Good conditions for concrete work and general site activities.';
    }
    if (description.isNotEmpty) {
      return 'Review schedule for $description — plan outdoor work accordingly.';
    }
    return 'Monitor conditions and adjust outdoor work as needed.';
  }

  static IconKind iconForCondition(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) return IconKind.storm;
    if (c.contains('rain') || c.contains('drizzle')) return IconKind.rain;
    if (c.contains('cloud')) return IconKind.cloud;
    return IconKind.sun;
  }
}

enum IconKind { sun, cloud, rain, storm }
