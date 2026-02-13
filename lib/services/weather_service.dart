import 'package:dio/dio.dart';

class WeatherService {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  final Dio _dio = Dio();

  static const String _apiKey = '36d74affc54853e817cac837ebaf6d8a';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

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

    return WeatherNow(
      temperatureC: temperatureC,
      description: description,
      condition: condition,
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

      double? tempMin;
      double? tempMax;
      if (tempMinRaw is num) tempMin = tempMinRaw.toDouble();
      if (tempMaxRaw is num) tempMax = tempMaxRaw.toDouble();

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
        };
      });

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

      forecasts.add(
        WeatherDailyForecast(
          date: date,
          minTempC: min.isFinite ? min : 0.0,
          maxTempC: max.isFinite ? max : 0.0,
          condition: condition,
        ),
      );
    }

    return forecasts;
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

      result.add(
        WeatherHourlyForecast(
          dateTime: dt,
          tempC: tempC,
          condition: condition,
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

  WeatherNow({
    required this.temperatureC,
    required this.description,
    required this.condition,
  });
}

class WeatherDailyForecast {
  final DateTime date;
  final double minTempC;
  final double maxTempC;
  final String condition;

  WeatherDailyForecast({
    required this.date,
    required this.minTempC,
    required this.maxTempC,
    required this.condition,
  });
}

class WeatherHourlyForecast {
  final DateTime dateTime;
  final double tempC;
  final String condition;

  WeatherHourlyForecast({
    required this.dateTime,
    required this.tempC,
    required this.condition,
  });
}
