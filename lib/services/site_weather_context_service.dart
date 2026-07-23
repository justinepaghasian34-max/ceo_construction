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
  });

  final String locationLabel;
  final WeatherNow now;
  final List<WeatherDailyForecast> forecastDays;
  final String siteAdvice;
  final String windLabel;
  final String visibilityLabel;
  final DateTime fetchedAt;
  final LiveWeatherReport? liveReport;

  Map<String, dynamic> toAiJson() {
    return {
      'location': locationLabel,
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
    if (s.isEmpty) return 'Manila,PH';
    if (!s.contains(',')) return '$s,PH';
    return s;
  }

  void clearCache() {
    _cache = null;
    _cacheKey = null;
    _cacheTime = null;
  }

  Future<SiteWeatherBundle> load({String? projectLocation, bool forceRefresh = false}) async {
    final key = normalizeLocation(projectLocation);
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cacheKey == key &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }

    final current = await _weather.getCurrentWeatherByCity(key);
    final forecast = await _weather.get7DayForecastByCity(key);

    LiveWeatherReport liveReport;
    try {
      final openMeteoMap = await _weather.getProjectWeatherData(
        lat: current.lat,
        lon: current.lon,
        location: key,
      );
      if (openMeteoMap['temperature'] == 'Unavailable') {
        liveReport = await _weather.getLiveWeatherReportByCity(key);
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
        liveReport = await _weather.getLiveWeatherReportByCity(key);
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

    final bundle = SiteWeatherBundle(
      locationLabel: current.cityName?.isNotEmpty == true ? current.cityName! : key,
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
