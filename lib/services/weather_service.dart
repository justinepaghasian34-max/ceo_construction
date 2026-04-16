import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  final Dio _dio = Dio();

  static const String _apiKey = '36d74affc54853e817cac837ebaf6d8a';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const String _geoBaseUrl = 'https://api.openweathermap.org/geo/1.0';

  static const String _visualCrossingApiKey =
      String.fromEnvironment('VISUAL_CROSSING_API_KEY');
  static const String _visualCrossingBaseUrl =
      'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline';

  String getWeatherTileUrlTemplate(WeatherMapLayer layer) {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final layerName = switch (layer) {
      WeatherMapLayer.temperature => 'temp_new',
      WeatherMapLayer.precipitation => 'precipitation_new',
      WeatherMapLayer.wind => 'wind_new',
      WeatherMapLayer.clouds => 'clouds_new',
    };

    return 'https://tile.openweathermap.org/map/$layerName/{z}/{x}/{y}.png?appid=$_apiKey';
  }

  Future<String?> reverseGeocode({
    required double lat,
    required double lon,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_geoBaseUrl/reverse',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'limit': 1,
        'appid': _apiKey,
      },
    );

    final data = response.data;
    if (data is! List) return null;
    if (data.isEmpty) return null;

    final first = data.first;
    if (first is! Map<String, dynamic>) return null;

    final name = (first['name'] ?? '').toString().trim();
    final state = (first['state'] ?? '').toString().trim();
    final country = (first['country'] ?? '').toString().trim();

    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (state.isNotEmpty) parts.add(state);
    if (country.isNotEmpty) parts.add(country);

    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  Future<WeatherNow> getCurrentWeatherByCoordinates({
    required double lat,
    required double lon,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_baseUrl/weather',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'appid': _apiKey,
        'units': 'metric',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final main = data['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final coord = data['coord'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final wind = data['wind'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final sys = data['sys'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final weatherList = data['weather'] as List<dynamic>? ?? <dynamic>[];
    final weather = weatherList.isNotEmpty
        ? weatherList.first as Map<String, dynamic>
        : <String, dynamic>{};

    final tempValue = main['temp'];
    double temperatureC;
    if (tempValue is num) {
      temperatureC = tempValue.toDouble();
    } else {
      temperatureC = 0.0;
    }

    final description = (weather['description'] ?? '').toString();
    final condition = (weather['main'] ?? '').toString();

    final feelsLikeRaw = main['feels_like'];
    final humidityRaw = main['humidity'];
    final pressureRaw = main['pressure'];
    final visibilityRaw = data['visibility'];
    final windSpeedRaw = wind['speed'];
    final windDegRaw = wind['deg'];
    final sunriseRaw = sys['sunrise'];
    final sunsetRaw = sys['sunset'];
    final cityName = (data['name'] ?? '').toString();

    final latRaw = coord['lat'];
    final lonRaw = coord['lon'];

    return WeatherNow(
      temperatureC: temperatureC,
      description: description,
      condition: condition,
      cityName: cityName,
      lat: latRaw is num ? latRaw.toDouble() : null,
      lon: lonRaw is num ? lonRaw.toDouble() : null,
      feelsLikeC: feelsLikeRaw is num ? feelsLikeRaw.toDouble() : null,
      humidity: humidityRaw is num ? humidityRaw.toInt() : null,
      pressureMb: pressureRaw is num ? pressureRaw.toInt() : null,
      visibilityKm: visibilityRaw is num ? (visibilityRaw.toDouble() / 1000) : null,
      windSpeedMs: windSpeedRaw is num ? windSpeedRaw.toDouble() : null,
      windDeg: windDegRaw is num ? windDegRaw.toInt() : null,
      sunrise: sunriseRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(sunriseRaw.toInt() * 1000,
              isUtc: true)
          : null,
      sunset: sunsetRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(sunsetRaw.toInt() * 1000,
              isUtc: true)
          : null,
    );
  }

  Future<WeatherNow> getCurrentWeatherByCity(String city) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_baseUrl/weather',
      queryParameters: <String, dynamic>{
        'q': city,
        'appid': _apiKey,
        'units': 'metric',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final main = data['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final coord = data['coord'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final wind = data['wind'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final sys = data['sys'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final weatherList = data['weather'] as List<dynamic>? ?? <dynamic>[];
    final weather = weatherList.isNotEmpty
        ? weatherList.first as Map<String, dynamic>
        : <String, dynamic>{};

    final tempValue = main['temp'];
    double temperatureC;
    if (tempValue is num) {
      temperatureC = tempValue.toDouble();
    } else {
      temperatureC = 0.0;
    }

    final description = (weather['description'] ?? '').toString();
    final condition = (weather['main'] ?? '').toString();

    final feelsLikeRaw = main['feels_like'];
    final humidityRaw = main['humidity'];
    final pressureRaw = main['pressure'];
    final visibilityRaw = data['visibility'];
    final windSpeedRaw = wind['speed'];
    final windDegRaw = wind['deg'];
    final sunriseRaw = sys['sunrise'];
    final sunsetRaw = sys['sunset'];
    final cityName = (data['name'] ?? city).toString();

    final latRaw = coord['lat'];
    final lonRaw = coord['lon'];

    return WeatherNow(
      temperatureC: temperatureC,
      description: description,
      condition: condition,
      cityName: cityName,
      lat: latRaw is num ? latRaw.toDouble() : null,
      lon: lonRaw is num ? lonRaw.toDouble() : null,
      feelsLikeC: feelsLikeRaw is num ? feelsLikeRaw.toDouble() : null,
      humidity: humidityRaw is num ? humidityRaw.toInt() : null,
      pressureMb: pressureRaw is num ? pressureRaw.toInt() : null,
      visibilityKm:
          visibilityRaw is num ? (visibilityRaw.toDouble() / 1000) : null,
      windSpeedMs: windSpeedRaw is num ? windSpeedRaw.toDouble() : null,
      windDeg: windDegRaw is num ? windDegRaw.toInt() : null,
      sunrise: sunriseRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(sunriseRaw.toInt() * 1000,
              isUtc: true)
          : null,
      sunset: sunsetRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(sunsetRaw.toInt() * 1000,
              isUtc: true)
          : null,
    );
  }

  Future<List<WeatherDailyForecast>> get7DayForecastByCity(String city) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_baseUrl/forecast',
      queryParameters: <String, dynamic>{
        'q': city,
        'appid': _apiKey,
        'units': 'metric',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final list = data['list'] as List<dynamic>? ?? <dynamic>[];

    final Map<DateTime, Map<String, dynamic>> byDate = {};

    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final dtText = (map['dt_txt'] ?? '').toString();
      if (dtText.isEmpty) continue;

      DateTime dt;
      try {
        dt = DateTime.parse(dtText);
      } catch (_) {
        continue;
      }

      final dateKey = DateTime(dt.year, dt.month, dt.day);
      final main = map['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final tempMinRaw = main['temp_min'] ?? main['temp'];
      final tempMaxRaw = main['temp_max'] ?? main['temp'];

      final humidityRaw = main['humidity'];
      final popRaw = map['pop'];
      final wind = map['wind'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final windSpeedRaw = wind['speed'];

      double? tempMin;
      double? tempMax;
      if (tempMinRaw is num) tempMin = tempMinRaw.toDouble();
      if (tempMaxRaw is num) tempMax = tempMaxRaw.toDouble();

      final humidity = humidityRaw is num ? humidityRaw.toInt() : null;
      final pop = popRaw is num ? popRaw.toDouble() : null;
      final windSpeedMs = windSpeedRaw is num ? windSpeedRaw.toDouble() : null;

      final weatherList = map['weather'] as List<dynamic>? ?? <dynamic>[];
      final weather = weatherList.isNotEmpty
          ? weatherList.first as Map<String, dynamic>
          : <String, dynamic>{};
      final condition = (weather['main'] ?? '').toString();

      final entry = byDate.putIfAbsent(dateKey, () {
        return <String, dynamic>{
          'min': tempMin ?? double.infinity,
          'max': tempMax ?? -double.infinity,
          'condition': condition,
          'popMax': 0.0,
          'hasPop': false,
          'humiditySum': 0,
          'humidityCount': 0,
          'windSum': 0.0,
          'windCount': 0,
        };
      });

      if (pop != null) {
        final current = entry['popMax'] as double;
        entry['popMax'] = pop > current ? pop : current;
        entry['hasPop'] = true;
      }
      if (humidity != null) {
        entry['humiditySum'] = (entry['humiditySum'] as int) + humidity;
        entry['humidityCount'] = (entry['humidityCount'] as int) + 1;
      }
      if (windSpeedMs != null) {
        entry['windSum'] = (entry['windSum'] as double) + windSpeedMs;
        entry['windCount'] = (entry['windCount'] as int) + 1;
      }

      if (tempMin != null) {
        final currentMin = entry['min'] as double;
        entry['min'] = currentMin.isFinite
            ? (tempMin < currentMin ? tempMin : currentMin)
            : tempMin;
      }

      if (tempMax != null) {
        final currentMax = entry['max'] as double;
        entry['max'] = currentMax.isFinite
            ? (tempMax > currentMax ? tempMax : currentMax)
            : tempMax;
      }

      if ((entry['condition'] as String).isEmpty && condition.isNotEmpty) {
        entry['condition'] = condition;
      }
    }

    final dates = byDate.keys.toList()..sort();
    final List<WeatherDailyForecast> forecasts = [];

    for (final date in dates) {
      if (forecasts.length >= 7) break;
      final entry = byDate[date]!;
      final min = entry['min'] as double;
      final max = entry['max'] as double;
      final condition = (entry['condition'] as String?) ?? '';

      final hasPop = entry['hasPop'] == true;
      final pop = hasPop ? (entry['popMax'] as double) : null;

      final humidityCount = entry['humidityCount'] as int;
      final humidity = humidityCount == 0
          ? null
          : ((entry['humiditySum'] as int) / humidityCount).round();

      final windCount = entry['windCount'] as int;
      final windSpeedMs = windCount == 0
          ? null
          : (entry['windSum'] as double) / windCount;

      forecasts.add(
        WeatherDailyForecast(
          date: date,
          minTempC: min.isFinite ? min : 0.0,
          maxTempC: max.isFinite ? max : 0.0,
          condition: condition,
          pop: pop,
          humidity: humidity,
          windSpeedMs: windSpeedMs,
        ),
      );
    }

    return forecasts;
  }

  Future<List<WeatherDailyForecast>> getMonthlyForecastByCity({
    required String city,
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);

    final startStr =
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    // Web requests can fail due to CORS. Use a callable Cloud Function proxy on web.
    // Also use it as a fallback on mobile/desktop when the API key isn't passed.
    final shouldUseFunctions = kIsWeb || _visualCrossingApiKey.isEmpty;
    if (shouldUseFunctions) {
      try {
        final callable = FirebaseFunctions.instance
            .httpsCallable('visualCrossingMonthlyForecast');
        final res = await callable.call(<String, dynamic>{
          'city': city,
          'start': startStr,
          'end': endStr,
        });

        final payload = res.data;
        final map = payload is Map
            ? payload.cast<String, dynamic>()
            : <String, dynamic>{};
        final days = map['days'] as List<dynamic>? ?? <dynamic>[];

        final result = <WeatherDailyForecast>[];
        for (final item in days) {
          if (item is! Map) continue;
          final m = item.cast<String, dynamic>();
          final dtRaw = m['datetime'];
          if (dtRaw == null) continue;

          DateTime date;
          try {
            date = DateTime.parse(dtRaw.toString());
          } catch (_) {
            continue;
          }

          final minRaw = m['tempmin'];
          final maxRaw = m['tempmax'];
          final humidityRaw = m['humidity'];
          final windKphRaw = m['windspeed'];
          final popPctRaw = m['precipprob'];
          final condition = (m['conditions'] ?? '').toString();

          final min = minRaw is num ? minRaw.toDouble() : 0.0;
          final max = maxRaw is num ? maxRaw.toDouble() : 0.0;
          final humidity = humidityRaw is num ? humidityRaw.round() : null;

          final windKph = windKphRaw is num ? windKphRaw.toDouble() : null;
          final windMs = windKph != null ? (windKph / 3.6) : null;

          final popPct = popPctRaw is num ? popPctRaw.toDouble() : null;
          final pop = popPct != null ? (popPct / 100.0).clamp(0.0, 1.0) : null;

          result.add(
            WeatherDailyForecast(
              date: date,
              minTempC: min,
              maxTempC: max,
              condition: condition,
              pop: pop,
              humidity: humidity,
              windSpeedMs: windMs,
            ),
          );
        }

        result.sort((a, b) => a.date.compareTo(b.date));
        return result;
      } on FirebaseFunctionsException catch (e) {
        final code = e.code;
        if (code == 'unauthenticated') {
          throw StateError('Monthly forecast unavailable (please sign in again).');
        }
        if (code == 'failed-precondition') {
          throw StateError(
            'Monthly forecast unavailable (server API key not configured).',
          );
        }
        throw StateError('Monthly forecast unavailable.');
      } catch (_) {
        throw StateError('Monthly forecast unavailable.');
      }
    }

    late final Response<dynamic> response;
    try {
      response = await _dio.get(
        '$_visualCrossingBaseUrl/${Uri.encodeComponent(city)}/$startStr/$endStr',
        queryParameters: <String, dynamic>{
          'unitGroup': 'metric',
          'include': 'days',
          'key': _visualCrossingApiKey,
          'contentType': 'json',
        },
      );
    } on DioException catch (e) {
      final msg = (e.message ?? '').toLowerCase();

      // Common on Flutter Web when the API does not allow browser CORS requests.
      if (kIsWeb && msg.contains('xmlhttprequest')) {
        throw StateError(
          'Monthly forecast unavailable in web preview (CORS blocked). Run on Android/iOS or use a backend proxy.',
        );
      }

      // Network/DNS issues.
      if (msg.contains('failed host lookup') ||
          msg.contains('socketexception') ||
          msg.contains('network is unreachable')) {
        throw StateError(
          'Monthly forecast unavailable (network/DNS error).',
        );
      }

      // Invalid API key / forbidden.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw StateError(
          'Monthly forecast unavailable (invalid Visual Crossing API key).',
        );
      }

      throw StateError('Monthly forecast unavailable.');
    }

    final data = response.data as Map<String, dynamic>;
    final days = data['days'] as List<dynamic>? ?? <dynamic>[];

    final result = <WeatherDailyForecast>[];
    for (final item in days) {
      final map = item as Map<String, dynamic>;
      final dtRaw = map['datetime'];
      if (dtRaw == null) continue;

      DateTime date;
      try {
        date = DateTime.parse(dtRaw.toString());
      } catch (_) {
        continue;
      }

      final minRaw = map['tempmin'];
      final maxRaw = map['tempmax'];
      final humidityRaw = map['humidity'];
      final windKphRaw = map['windspeed'];
      final popPctRaw = map['precipprob'];
      final condition = (map['conditions'] ?? '').toString();

      final min = minRaw is num ? minRaw.toDouble() : 0.0;
      final max = maxRaw is num ? maxRaw.toDouble() : 0.0;
      final humidity = humidityRaw is num ? humidityRaw.round() : null;

      final windKph = windKphRaw is num ? windKphRaw.toDouble() : null;
      final windMs = windKph != null ? (windKph / 3.6) : null;

      final popPct = popPctRaw is num ? popPctRaw.toDouble() : null;
      final pop = popPct != null ? (popPct / 100.0).clamp(0.0, 1.0) : null;

      result.add(
        WeatherDailyForecast(
          date: date,
          minTempC: min,
          maxTempC: max,
          condition: condition,
          pop: pop,
          humidity: humidity,
          windSpeedMs: windMs,
        ),
      );
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }
  
  Future<List<WeatherHourlyForecast>> getHourlyForecastByCityAndDate(
    String city,
    DateTime date,
  ) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_baseUrl/forecast',
      queryParameters: <String, dynamic>{
        'q': city,
        'appid': _apiKey,
        'units': 'metric',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final list = data['list'] as List<dynamic>? ?? <dynamic>[];

    final List<WeatherHourlyForecast> result = [];

    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final dtText = (map['dt_txt'] ?? '').toString();
      if (dtText.isEmpty) continue;

      DateTime dt;
      try {
        dt = DateTime.parse(dtText);
      } catch (_) {
        continue;
      }

      final sameDay =
          dt.year == date.year && dt.month == date.month && dt.day == date.day;
      if (!sameDay) continue;

      final main = map['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final tempRaw = main['temp'];
      double tempC;
      if (tempRaw is num) {
        tempC = tempRaw.toDouble();
      } else {
        tempC = 0.0;
      }

      final weatherList = map['weather'] as List<dynamic>? ?? <dynamic>[];
      final weather = weatherList.isNotEmpty
          ? weatherList.first as Map<String, dynamic>
          : <String, dynamic>{};
      final condition = (weather['main'] ?? '').toString();

      final popRaw = map['pop'];
      final rain = map['rain'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final rainMmRaw = rain['3h'];

      result.add(
        WeatherHourlyForecast(
          dateTime: dt,
          tempC: tempC,
          condition: condition,
          pop: popRaw is num ? popRaw.toDouble() : null,
          rainMm: rainMmRaw is num ? rainMmRaw.toDouble() : null,
        ),
      );
    }

    result.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return result;
  }

  Future<List<WeatherHourlyForecast>> getHourlyForecastByCoordinatesAndDate({
    required double lat,
    required double lon,
    required DateTime date,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('Weather API key not configured');
    }

    final response = await _dio.get(
      '$_baseUrl/forecast',
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'appid': _apiKey,
        'units': 'metric',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final list = data['list'] as List<dynamic>? ?? <dynamic>[];

    final List<WeatherHourlyForecast> result = [];

    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final dtText = (map['dt_txt'] ?? '').toString();
      if (dtText.isEmpty) continue;

      DateTime dt;
      try {
        dt = DateTime.parse(dtText);
      } catch (_) {
        continue;
      }

      final sameDay =
          dt.year == date.year && dt.month == date.month && dt.day == date.day;
      if (!sameDay) continue;

      final main = map['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final tempRaw = main['temp'];
      double tempC;
      if (tempRaw is num) {
        tempC = tempRaw.toDouble();
      } else {
        tempC = 0.0;
      }

      final weatherList = map['weather'] as List<dynamic>? ?? <dynamic>[];
      final weather = weatherList.isNotEmpty
          ? weatherList.first as Map<String, dynamic>
          : <String, dynamic>{};
      final condition = (weather['main'] ?? '').toString();

      final popRaw = map['pop'];
      final rain = map['rain'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final rainMmRaw = rain['3h'];

      result.add(
        WeatherHourlyForecast(
          dateTime: dt,
          tempC: tempC,
          condition: condition,
          pop: popRaw is num ? popRaw.toDouble() : null,
          rainMm: rainMmRaw is num ? rainMmRaw.toDouble() : null,
        ),
      );
    }

    result.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return result;
  }
}

class WeatherNow {
  final double temperatureC;
  final String description;
  final String condition;
  final String? cityName;
  final double? lat;
  final double? lon;
  final double? feelsLikeC;
  final int? humidity;
  final int? pressureMb;
  final double? visibilityKm;
  final double? windSpeedMs;
  final int? windDeg;
  final DateTime? sunrise;
  final DateTime? sunset;

  WeatherNow({
    required this.temperatureC,
    required this.description,
    required this.condition,
    this.cityName,
    this.lat,
    this.lon,
    this.feelsLikeC,
    this.humidity,
    this.pressureMb,
    this.visibilityKm,
    this.windSpeedMs,
    this.windDeg,
    this.sunrise,
    this.sunset,
  });
}

class WeatherDailyForecast {
  final DateTime date;
  final double minTempC;
  final double maxTempC;
  final String condition;
  final double? pop;
  final int? humidity;
  final double? windSpeedMs;

  WeatherDailyForecast({
    required this.date,
    required this.minTempC,
    required this.maxTempC,
    required this.condition,
    this.pop,
    this.humidity,
    this.windSpeedMs,
  });
}

class WeatherHourlyForecast {
  final DateTime dateTime;
  final double tempC;
  final String condition;
  final double? pop;
  final double? rainMm;

  WeatherHourlyForecast({
    required this.dateTime,
    required this.tempC,
    required this.condition,
    this.pop,
    this.rainMm,
  });
}

enum WeatherMapLayer {
  temperature,
  precipitation,
  wind,
  clouds,
}
