import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  final Dio _dio = Dio();

  static const String _apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const String _geoBaseUrl = 'https://api.openweathermap.org/geo/1.0';

  bool get hasOpenWeatherMapTiles => _apiKey.isNotEmpty;

  static const String _visualCrossingApiKey =
      String.fromEnvironment('VISUAL_CROSSING_API_KEY');
  static const String _visualCrossingBaseUrl =
      'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline';

  static const String _openMeteoForecastUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _openMeteoGeocodeUrl =
      'https://geocoding-api.open-meteo.com/v1/search';

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

  /// Resolves a city/location string to coordinates via Open-Meteo, then Nominatim.
  Future<({double lat, double lon, String label})?> resolveOpenMeteoCoordinates(
    String location,
  ) async {
    final raw = location.trim();
    if (raw.isEmpty) return null;

    final candidates = <String>{
      raw,
      raw.split(',').first.trim(),
      if (!raw.toLowerCase().contains('philippine') &&
          !raw.toLowerCase().endsWith(', ph') &&
          !raw.toLowerCase().endsWith(',ph'))
        '$raw, Philippines',
    }.where((s) => s.isNotEmpty).toList();

    for (final query in candidates) {
      final hit = await _geocodeOpenMeteoOnce(query, countryCode: 'PH');
      if (hit != null) return hit;
    }
    for (final query in candidates) {
      final hit = await _geocodeOpenMeteoOnce(query);
      if (hit != null) return hit;
    }
    for (final query in candidates) {
      final hit = await _geocodeNominatim(query);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<({double lat, double lon, String label})?> _geocodeOpenMeteoOnce(
    String query, {
    String? countryCode,
  }) async {
    final params = <String, String>{
      'name': query,
      'count': '1',
      'language': 'en',
      'format': 'json',
    };
    if (countryCode != null && countryCode.isNotEmpty) {
      params['countryCode'] = countryCode;
    }
    final uri = Uri.parse(_openMeteoGeocodeUrl).replace(queryParameters: params);

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as List<dynamic>? ?? <dynamic>[];
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final lat = (first['latitude'] as num?)?.toDouble();
    final lon = (first['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final name = (first['name'] ?? query).toString();
    final admin1 = (first['admin1'] ?? '').toString().trim();
    final country = (first['country'] ?? '').toString().trim();
    final labelParts = <String>[name];
    if (admin1.isNotEmpty) labelParts.add(admin1);
    if (country.isNotEmpty) labelParts.add(country);

    return (lat: lat, lon: lon, label: labelParts.join(', '));
  }

  Future<({double lat, double lon, String label})?> _geocodeNominatim(
    String query,
  ) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/search').replace(
      queryParameters: <String, String>{
        'q': query,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'ph',
      },
    );
    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'CEO-Construction-Monitoring/1.0 (admin map pins)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = double.tryParse((first['lat'] ?? '').toString());
      final lon = double.tryParse((first['lon'] ?? '').toString());
      if (lat == null || lon == null) return null;
      final label = (first['display_name'] ?? query).toString().trim();
      return (lat: lat, lon: lon, label: label.isEmpty ? query : label);
    } catch (e) {
      debugPrint('_geocodeNominatim failed: $e');
      return null;
    }
  }

  /// Firestore pin fields from the Admin "Project Location" text.
  Future<Map<String, dynamic>> pinFieldsFromLocation(String? location) async {
    final query = (location ?? '').trim();
    if (query.isEmpty) return const {};
    try {
      final geo = await resolveOpenMeteoCoordinates(query);
      if (geo == null) return const {};
      return {
        'latitude': geo.lat,
        'longitude': geo.lon,
        'geoAddress': geo.label,
      };
    } catch (e) {
      debugPrint('pinFieldsFromLocation failed: $e');
      return const {};
    }
  }

  /// Live site metrics from [Open-Meteo Forecast API](https://api.open-meteo.com/v1/forecast) (no API key).
  Future<LiveWeatherReport> getOpenMeteoLiveReport({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse(_openMeteoForecastUrl).replace(
      queryParameters: <String, String>{
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'current': 'temperature_2m,relative_humidity_2m,is_day',
        'hourly': 'precipitation_probability',
        'forecast_days': '2',
        'timezone': 'auto',
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Open-Meteo HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final hourly = json['hourly'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0.0;
    final humidity = (current['relative_humidity_2m'] as num?)?.toInt() ?? 0;
    final isDay = (current['is_day'] as num?)?.toInt() ?? 1;

    final times = (hourly['time'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final rainProbs =
        (hourly['precipitation_probability'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => (e as num?)?.toInt() ?? 0)
            .toList();

    var rainIsComing = false;
    var startIdx = 0;
    final now = DateTime.now();
    for (var i = 0; i < times.length; i++) {
      try {
        final t = DateTime.parse(times[i]);
        if (!t.isBefore(now)) {
          startIdx = i;
          break;
        }
      } catch (_) {
        continue;
      }
    }
    for (var i = startIdx + 1; i <= startIdx + 3 && i < rainProbs.length; i++) {
      if (rainProbs[i] > 40) {
        rainIsComing = true;
        break;
      }
    }

    final rainForecast = rainIsComing
        ? '🚨 ALERT: Rain approaching within 3 hours!'
        : 'Clear skies.';

    return LiveWeatherReport(
      temperature: '${temp.toStringAsFixed(0)}°C',
      humidity: '$humidity%',
      environmentLighting: isDay == 1
          ? 'Daylight Operations'
          : 'Night Work / Low Visibility',
      rainForecast: rainForecast,
      rainIsComing: rainIsComing,
      hoursUntilRain: rainIsComing ? 1 : 0,
      rawTempC: temp,
      rawHumidity: humidity,
      isDaylight: isDay == 1,
      provider: 'open-meteo',
    );
  }

  /// GovTrack prompt injection map (Open-Meteo).
  Future<Map<String, String>> getProjectWeatherData({
    double? lat,
    double? lon,
    String? location,
  }) async {
    try {
      double? useLat = lat;
      double? useLon = lon;
      if ((useLat == null || useLon == null) && location != null && location.trim().isNotEmpty) {
        final coords = await resolveOpenMeteoCoordinates(location);
        if (coords != null) {
          useLat = coords.lat;
          useLon = coords.lon;
        }
      }
      if (useLat == null || useLon == null) {
        throw StateError('No coordinates for weather');
      }

      final report = await getOpenMeteoLiveReport(lat: useLat, lon: useLon);
      return {
        'temperature': report.temperature,
        'humidity': report.humidity,
        'lighting': report.environmentLighting,
        'rain_status': report.rainForecast,
      };
    } catch (e) {
      debugPrint('Open-Meteo project weather error: $e');
    }

    return {
      'temperature': 'Unavailable',
      'humidity': 'Unavailable',
      'lighting': 'Unavailable',
      'rain_status': 'Offline',
    };
  }

  /// Live on-site report: Open-Meteo first; then OpenWeather One Call / forecast fallback.
  Future<LiveWeatherReport> getLiveWeatherReport({
    required double lat,
    required double lon,
  }) async {
    try {
      return await getOpenMeteoLiveReport(lat: lat, lon: lon);
    } catch (e) {
      debugPrint('Open-Meteo live report failed, trying OpenWeather: $e');
    }

    if (_apiKey.isEmpty) {
      return LiveWeatherReport.error(
        'I cannot retrieve live weather data right now. Please check your system network connection.',
      );
    }

    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/data/3.0/onecall',
      ).replace(
        queryParameters: <String, String>{
          'lat': lat.toString(),
          'lon': lon.toString(),
          'units': 'metric',
          'appid': _apiKey,
          'exclude': 'minutely,daily,alerts',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseOneCallLiveReport(data);
      }
    } catch (e) {
      debugPrint('One Call 3.0 unavailable, using forecast fallback: $e');
    }

    return _liveReportFallback(lat: lat, lon: lon);
  }

  Future<LiveWeatherReport> getLiveWeatherReportByCity(String city) async {
    try {
      final coords = await resolveOpenMeteoCoordinates(city);
      if (coords != null) {
        return await getOpenMeteoLiveReport(lat: coords.lat, lon: coords.lon);
      }
    } catch (e) {
      debugPrint('Open-Meteo by city failed for $city: $e');
    }

    if (_apiKey.isEmpty) {
      return LiveWeatherReport.error(
        'I cannot retrieve live weather data right now. Please check your system network connection.',
      );
    }

    final current = await getCurrentWeatherByCity(city);
    final lat = current.lat;
    final lon = current.lon;
    if (lat != null && lon != null) {
      try {
        return await getLiveWeatherReport(lat: lat, lon: lon);
      } catch (_) {
        return _liveReportFromCurrentAndForecastList(current, city);
      }
    }
    return _liveReportFromCurrentAndForecastList(current, city);
  }

  LiveWeatherReport _parseOneCallLiveReport(Map<String, dynamic> data) {
    final current = data['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final temp = (current['temp'] as num?)?.toDouble() ?? 0.0;
    final humidity = (current['humidity'] as num?)?.toInt() ?? 0;

    final currentTime = (current['dt'] as num?)?.toInt() ?? 0;
    final sunrise = (current['sunrise'] as num?)?.toInt() ?? 0;
    final sunset = (current['sunset'] as num?)?.toInt() ?? 0;
    final isDaylight =
        sunrise > 0 && sunset > 0 && currentTime >= sunrise && currentTime < sunset;

    final hourlyForecast = data['hourly'] as List<dynamic>? ?? <dynamic>[];
    final rainScan = _scanHourlyForRain(hourlyForecast);

    return LiveWeatherReport(
      temperature: '${temp.toStringAsFixed(0)}°C',
      humidity: '$humidity%',
      environmentLighting:
          isDaylight ? 'Daytime Operations' : 'Night Work / Low Visibility',
      rainForecast: rainScan.message,
      rainIsComing: rainScan.isComing,
      hoursUntilRain: rainScan.hoursUntilRain,
      rawTempC: temp,
      rawHumidity: humidity,
      isDaylight: isDaylight,
    );
  }

  ({bool isComing, int hoursUntilRain, String message}) _scanHourlyForRain(
    List<dynamic> hourlyForecast,
  ) {
    const defaultMsg =
        'No rain detected in the immediate forecast windows.';
    for (var i = 1; i <= 4; i++) {
      if (i >= hourlyForecast.length) break;
      final hourData = hourlyForecast[i];
      if (hourData is! Map<String, dynamic>) continue;

      final weatherList = hourData['weather'] as List<dynamic>? ?? <dynamic>[];
      final mainCondition = weatherList.isNotEmpty
          ? (weatherList.first as Map<String, dynamic>)['main']?.toString().toLowerCase() ?? ''
          : '';

      if (mainCondition.contains('rain') || hourData.containsKey('rain')) {
        return (
          isComing: true,
          hoursUntilRain: i,
          message:
              '🚨 WARNING: Rain is approaching! Precipitation expected on-site within $i hour(s). Protect exposed materials immediately.',
        );
      }
    }
    return (isComing: false, hoursUntilRain: 0, message: defaultMsg);
  }

  Future<LiveWeatherReport> _liveReportFallback({
    required double lat,
    required double lon,
  }) async {
    final current = await getCurrentWeatherByCoordinates(lat: lat, lon: lon);
    return _liveReportFromCurrentAndForecastList(current, current.cityName ?? '');
  }

  Future<LiveWeatherReport> _liveReportFromCurrentAndForecastList(
    WeatherNow current,
    String city,
  ) async {
    final now = DateTime.now().toUtc();
    var isDaylight = true;
    if (current.sunrise != null && current.sunset != null) {
      isDaylight = now.isAfter(current.sunrise!) && now.isBefore(current.sunset!);
    }

    final hourly = await getHourlyForecastByCoordinatesAndDate(
      lat: current.lat ?? 14.5995,
      lon: current.lon ?? 120.9842,
      date: DateTime.now(),
    );

    final upcoming = hourly
        .where((h) => h.dateTime.isAfter(DateTime.now()))
        .take(4)
        .toList();

    var rainMsg = 'No rain detected in the immediate forecast windows.';
    var rainComing = false;
    var hoursUntil = 0;

    for (var i = 0; i < upcoming.length; i++) {
      final h = upcoming[i];
      final c = h.condition.toLowerCase();
      if (c.contains('rain') || (h.pop ?? 0) > 0.5 || (h.rainMm ?? 0) > 0) {
        rainComing = true;
        hoursUntil = i + 1;
        rainMsg =
            '🚨 WARNING: Rain is approaching! Precipitation expected on-site within $hoursUntil hour(s). Protect exposed materials immediately.';
        break;
      }
    }

    return LiveWeatherReport(
      temperature: '${current.temperatureC.toStringAsFixed(0)}°C',
      humidity: current.humidity != null ? '${current.humidity}%' : '—',
      environmentLighting:
          isDaylight ? 'Daytime Operations' : 'Night Work / Low Visibility',
      rainForecast: rainMsg,
      rainIsComing: rainComing,
      hoursUntilRain: hoursUntil,
      rawTempC: current.temperatureC,
      rawHumidity: current.humidity,
      isDaylight: isDaylight,
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

/// Native Dart weather layer output for GovTrack AI site coordinator context.
class LiveWeatherReport {
  const LiveWeatherReport({
    required this.temperature,
    required this.humidity,
    required this.environmentLighting,
    required this.rainForecast,
    this.rainIsComing = false,
    this.hoursUntilRain = 0,
    this.rawTempC,
    this.rawHumidity,
    this.isDaylight = true,
    this.error,
    this.provider,
  });

  final String temperature;
  final String humidity;
  final String environmentLighting;
  final String rainForecast;
  final bool rainIsComing;
  final int hoursUntilRain;
  final double? rawTempC;
  final int? rawHumidity;
  final bool isDaylight;
  final String? error;
  final String? provider;

  bool get hasError => error != null && error!.isNotEmpty;

  bool get isOffline =>
      temperature == 'Unavailable' ||
      humidity == 'Unavailable' ||
      hasError;

  Map<String, dynamic> toMap() => {
        'temperature': temperature,
        'humidity': humidity,
        'environment_lighting': environmentLighting,
        'rain_forecast': rainForecast,
        'rain_is_coming': rainIsComing,
        'hours_until_rain': hoursUntilRain,
        if (rawTempC != null) 'raw_temp_c': rawTempC,
        if (rawHumidity != null) 'raw_humidity': rawHumidity,
        'is_daylight': isDaylight,
        if (provider != null) 'provider': provider,
        if (error != null) 'error': error,
      };

  factory LiveWeatherReport.error(String message) => LiveWeatherReport(
        temperature: '—',
        humidity: '—',
        environmentLighting: '—',
        rainForecast: message,
        error: message,
      );
}
