import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/security/pinned_http_client.dart';

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  final Dio _dio = PinnedHttpClient.create();

  // Intentionally empty — never load provider keys into the client binary.
  static const String _apiKey = '';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  bool get hasOpenWeatherMapTiles => false;

  static const String _visualCrossingApiKey = '';
  static const String _visualCrossingBaseUrl =
      'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline';

  static const String _openMeteoForecastUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _openMeteoGeocodeUrl =
      'https://geocoding-api.open-meteo.com/v1/search';
  static const String _rainViewerMapsUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  String? _rainHost;
  String? _radarPath;
  String? _satellitePath;
  DateTime? _rainViewerFetchedAt;

  /// Overlay tile URL. Uses RainViewer radar/satellite (no API key).
  /// Returns null when that layer has no public tiles.
  String? getWeatherTileUrlTemplate(WeatherMapLayer layer) {
    if (_apiKey.isNotEmpty &&
        (layer == WeatherMapLayer.temperature ||
            layer == WeatherMapLayer.wind)) {
      final layerName = layer == WeatherMapLayer.temperature
          ? 'temp_new'
          : 'wind_new';
      return 'https://tile.openweathermap.org/map/$layerName/{z}/{x}/{y}.png?appid=$_apiKey';
    }
    return _cachedRainViewerTemplate(layer);
  }

  Future<String?> weatherOverlayTileUrl(WeatherMapLayer layer) async {
    if (_apiKey.isNotEmpty &&
        (layer == WeatherMapLayer.temperature ||
            layer == WeatherMapLayer.wind)) {
      return getWeatherTileUrlTemplate(layer);
    }
    await _refreshRainViewerIfNeeded();
    return _cachedRainViewerTemplate(layer);
  }

  String? _cachedRainViewerTemplate(WeatherMapLayer layer) {
    final host = _rainHost ?? 'https://tilecache.rainviewer.com';
    switch (layer) {
      case WeatherMapLayer.precipitation:
        if (_radarPath == null) return null;
        return '$host$_radarPath/256/{z}/{x}/{y}/2/1_1.png';
      case WeatherMapLayer.clouds:
      case WeatherMapLayer.satellite:
        if (_satellitePath == null) return null;
        return '$host$_satellitePath/256/{z}/{x}/{y}/0/0_0.png';
      case WeatherMapLayer.temperature:
      case WeatherMapLayer.wind:
        return null;
    }
  }

  Future<void> _refreshRainViewerIfNeeded() async {
    final fetched = _rainViewerFetchedAt;
    if (fetched != null &&
        DateTime.now().difference(fetched) < const Duration(minutes: 5) &&
        (_radarPath != null || _satellitePath != null)) {
      return;
    }
    try {
      final response = await http
          .get(Uri.parse(_rainViewerMapsUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _rainHost = (json['host'] ?? 'https://tilecache.rainviewer.com').toString();
      final radar = json['radar'] as Map<String, dynamic>? ?? {};
      final past = radar['past'] as List<dynamic>? ?? const [];
      if (past.isNotEmpty) {
        final last = past.last;
        if (last is Map) {
          _radarPath = (last['path'] ?? '').toString();
          if (_radarPath!.isEmpty) _radarPath = null;
        }
      }
      final satellite = json['satellite'] as Map<String, dynamic>? ?? {};
      final infrared = satellite['infrared'] as List<dynamic>? ?? const [];
      if (infrared.isNotEmpty) {
        final last = infrared.last;
        if (last is Map) {
          _satellitePath = (last['path'] ?? '').toString();
          if (_satellitePath!.isEmpty) _satellitePath = null;
        }
      }
      _rainViewerFetchedAt = DateTime.now();
    } catch (e) {
      debugPrint('RainViewer frames failed: $e');
    }
  }

  Future<String?> reverseGeocode({
    required double lat,
    required double lon,
  }) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
          .replace(queryParameters: <String, String>{
        'lat': lat.toString(),
        'lon': lon.toString(),
        'format': 'json',
        'zoom': '14',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'CEO-Construction-Monitoring/1.0 (admin map pins)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final label = (decoded['display_name'] ?? '').toString().trim();
      return label.isEmpty ? null : label;
    } catch (e) {
      debugPrint('Nominatim reverse geocode failed: $e');
      return null;
    }
  }

  Future<WeatherNow> getCurrentWeatherByCoordinates({
    required double lat,
    required double lon,
  }) async {
    if (kIsWeb || _apiKey.isEmpty) {
      return _openMeteoCurrentByCoords(lat: lat, lon: lon);
    }

    try {

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
    } catch (e) {
      debugPrint('OpenWeather current by coords failed, using Open-Meteo: $e');
      return _openMeteoCurrentByCoords(lat: lat, lon: lon);
    }
  }

  Future<WeatherNow> getCurrentWeatherByCity(String city) async {
    if (kIsWeb || _apiKey.isEmpty) {
      return _openMeteoCurrentByQuery(city);
    }

    try {

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
    } catch (e) {
      debugPrint('OpenWeather current by city failed, using Open-Meteo: $e');
      return _openMeteoCurrentByQuery(city);
    }
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
        'models': 'best_match',
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
    if (kIsWeb || _apiKey.isEmpty) {
      return _openMeteoDailyByQuery(city);
    }

    try {

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
    } catch (e) {
      debugPrint('OpenWeather 7-day failed, using Open-Meteo: $e');
      return _openMeteoDailyByQuery(city);
    }
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
    final shouldUseFunctions = true; // VC key only on Cloud Functions
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
    if (kIsWeb || _apiKey.isEmpty) {
      return _openMeteoHourlyByQuery(city, date);
    }

    try {

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
    } catch (e) {
      debugPrint('OpenWeather hourly by city failed, using Open-Meteo: $e');
      return _openMeteoHourlyByQuery(city, date);
    }
  }

  Future<List<WeatherHourlyForecast>> getHourlyForecastByCoordinatesAndDate({
    required double lat,
    required double lon,
    required DateTime date,
  }) async {
    if (kIsWeb || _apiKey.isEmpty) {
      return _openMeteoHourlyByCoords(lat: lat, lon: lon, date: date);
    }

    try {

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
    } catch (e) {
      debugPrint('OpenWeather hourly by coords failed, using Open-Meteo: $e');
      return _openMeteoHourlyByCoords(lat: lat, lon: lon, date: date);
    }
  }

  Future<WeatherNow> _openMeteoCurrentByQuery(String city) async {
    final geo = await resolveOpenMeteoCoordinates(city);
    if (geo == null) {
      throw StateError('Could not find location "$city"');
    }
    return _openMeteoCurrentByCoords(
      lat: geo.lat,
      lon: geo.lon,
      cityName: geo.label,
    );
  }

  Future<WeatherNow> _openMeteoCurrentByCoords({
    required double lat,
    required double lon,
    String? cityName,
  }) async {
    final uri = Uri.parse(_openMeteoForecastUrl).replace(
      queryParameters: <String, String>{
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,pressure_msl,visibility,is_day',
        'wind_speed_unit': 'ms',
        'models': 'best_match',
        'timezone': 'auto',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Open-Meteo HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current =
        json['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final code = (current['weather_code'] as num?)?.toInt() ?? 0;
    final visM = (current['visibility'] as num?)?.toDouble();
    return WeatherNow(
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      description: _wmoDescription(code),
      condition: _wmoCondition(code),
      cityName: cityName,
      lat: lat,
      lon: lon,
      feelsLikeC: (current['apparent_temperature'] as num?)?.toDouble(),
      humidity: (current['relative_humidity_2m'] as num?)?.toInt(),
      pressureMb: (current['pressure_msl'] as num?)?.round(),
      visibilityKm: visM != null ? visM / 1000 : null,
      windSpeedMs: (current['wind_speed_10m'] as num?)?.toDouble(),
      windDeg: (current['wind_direction_10m'] as num?)?.round(),
    );
  }

  Future<List<WeatherDailyForecast>> get7DayForecastByCoordinates({
    required double lat,
    required double lon,
  }) {
    return _openMeteoDailyByCoords(lat: lat, lon: lon);
  }

  Future<List<WeatherDailyForecast>> _openMeteoDailyByQuery(String city) async {
    final geo = await resolveOpenMeteoCoordinates(city);
    if (geo == null) {
      throw StateError('Could not find location "$city"');
    }
    return _openMeteoDailyByCoords(lat: geo.lat, lon: geo.lon);
  }

  Future<List<WeatherDailyForecast>> _openMeteoDailyByCoords({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse(_openMeteoForecastUrl).replace(
      queryParameters: <String, String>{
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,relative_humidity_2m_mean,wind_speed_10m_max',
        'wind_speed_unit': 'ms',
        'forecast_days': '7',
        'models': 'best_match',
        'timezone': 'auto',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Open-Meteo HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final times = (daily['time'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final codes = daily['weather_code'] as List<dynamic>? ?? <dynamic>[];
    final maxes = daily['temperature_2m_max'] as List<dynamic>? ?? <dynamic>[];
    final mins = daily['temperature_2m_min'] as List<dynamic>? ?? <dynamic>[];
    final pops =
        daily['precipitation_probability_max'] as List<dynamic>? ?? <dynamic>[];
    final humidity =
        daily['relative_humidity_2m_mean'] as List<dynamic>? ?? <dynamic>[];
    final wind =
        daily['wind_speed_10m_max'] as List<dynamic>? ?? <dynamic>[];

    final result = <WeatherDailyForecast>[];
    for (var i = 0; i < times.length && result.length < 7; i++) {
      DateTime date;
      try {
        date = DateTime.parse(times[i]);
      } catch (_) {
        continue;
      }
      final code = i < codes.length ? (codes[i] as num?)?.toInt() ?? 0 : 0;
      final popPct = i < pops.length ? (pops[i] as num?)?.toDouble() : null;
      result.add(
        WeatherDailyForecast(
          date: DateTime(date.year, date.month, date.day),
          minTempC: i < mins.length ? (mins[i] as num?)?.toDouble() ?? 0 : 0,
          maxTempC: i < maxes.length ? (maxes[i] as num?)?.toDouble() ?? 0 : 0,
          condition: _wmoCondition(code),
          pop: popPct != null ? (popPct / 100).clamp(0.0, 1.0) : null,
          humidity: i < humidity.length ? (humidity[i] as num?)?.round() : null,
          windSpeedMs: i < wind.length ? (wind[i] as num?)?.toDouble() : null,
        ),
      );
    }
    return result;
  }

  Future<List<WeatherHourlyForecast>> _openMeteoHourlyByQuery(
    String city,
    DateTime date,
  ) async {
    final geo = await resolveOpenMeteoCoordinates(city);
    if (geo == null) {
      throw StateError('Could not find location "$city"');
    }
    return _openMeteoHourlyByCoords(lat: geo.lat, lon: geo.lon, date: date);
  }

  Future<List<WeatherHourlyForecast>> _openMeteoHourlyByCoords({
    required double lat,
    required double lon,
    required DateTime date,
  }) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(_openMeteoForecastUrl).replace(
      queryParameters: <String, String>{
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'hourly':
            'temperature_2m,precipitation_probability,precipitation,weather_code',
        'start_date': day,
        'end_date': day,
        'models': 'best_match',
        'timezone': 'auto',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Open-Meteo HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final hourly =
        json['hourly'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final times = (hourly['time'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final temps = hourly['temperature_2m'] as List<dynamic>? ?? <dynamic>[];
    final pops =
        hourly['precipitation_probability'] as List<dynamic>? ?? <dynamic>[];
    final rain = hourly['precipitation'] as List<dynamic>? ?? <dynamic>[];
    final codes = hourly['weather_code'] as List<dynamic>? ?? <dynamic>[];

    final result = <WeatherHourlyForecast>[];
    for (var i = 0; i < times.length; i++) {
      DateTime dt;
      try {
        dt = DateTime.parse(times[i]);
      } catch (_) {
        continue;
      }
      final popPct = i < pops.length ? (pops[i] as num?)?.toDouble() : null;
      final code = i < codes.length ? (codes[i] as num?)?.toInt() ?? 0 : 0;
      result.add(
        WeatherHourlyForecast(
          dateTime: dt,
          tempC: i < temps.length ? (temps[i] as num?)?.toDouble() ?? 0 : 0,
          condition: _wmoCondition(code),
          pop: popPct != null ? (popPct / 100).clamp(0.0, 1.0) : null,
          rainMm: i < rain.length ? (rain[i] as num?)?.toDouble() : null,
        ),
      );
    }
    return result;
  }

  static String _wmoCondition(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Clouds';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain';
    if (code >= 85 && code <= 86) return 'Snow';
    if (code >= 95) return 'Thunderstorm';
    return 'Clouds';
  }

  static String _wmoDescription(int code) {
    const map = <int, String>{
      0: 'clear sky',
      1: 'mainly clear',
      2: 'partly cloudy',
      3: 'overcast',
      45: 'fog',
      48: 'rime fog',
      51: 'light drizzle',
      53: 'drizzle',
      55: 'dense drizzle',
      61: 'slight rain',
      63: 'moderate rain',
      65: 'heavy rain',
      71: 'slight snow',
      73: 'moderate snow',
      75: 'heavy snow',
      80: 'rain showers',
      81: 'rain showers',
      82: 'violent rain showers',
      95: 'thunderstorm',
      96: 'thunderstorm with hail',
      99: 'thunderstorm with hail',
    };
    return map[code] ?? _wmoCondition(code).toLowerCase();
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
  satellite,
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
