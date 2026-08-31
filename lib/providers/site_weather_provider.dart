import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../services/weather_service.dart';

/// A bundle of weather data for a single project site.
class ProjectSiteWeather {
  const ProjectSiteWeather({
    required this.projectId,
    required this.projectName,
    required this.location,
    required this.lat,
    required this.lon,
    required this.weather,
  });

  final String projectId;
  final String projectName;
  final String location;
  final double lat;
  final double lon;
  final WeatherNow weather;

  bool get isRaining {
    final c = weather.condition.toLowerCase();
    return c.contains('rain') ||
        c.contains('drizzle') ||
        c.contains('thunderstorm');
  }

  bool get isCloudy {
    final c = weather.condition.toLowerCase();
    return c.contains('cloud');
  }

  String get conditionLabel {
    if (isRaining) return 'Raining';
    if (isCloudy) return 'Cloudy';
    return 'Sunny';
  }

  String get tempLabel => '${weather.temperatureC.toStringAsFixed(0)}°C';

  String get summaryLine => '$conditionLabel · $tempLabel';
}

/// Fetches weather for a single project by its Firestore document.
/// Returns null if the project has no coordinates stored yet.
Future<ProjectSiteWeather?> _fetchForProject(
    Map<String, dynamic> data, String docId) async {
  final lat = (data['latitude'] as num?)?.toDouble();
  final lon = (data['longitude'] as num?)?.toDouble();
  if (lat == null || lon == null) return null;

  final name = (data['name'] ?? data['projectName'] ?? 'Untitled').toString();
  final location = (data['geoAddress'] ?? data['location'] ?? '').toString();

  try {
    final weather = await WeatherService.instance.getCurrentWeatherByCoordinates(
      lat: lat,
      lon: lon,
    );
    return ProjectSiteWeather(
      projectId: docId,
      projectName: name,
      location: location.isNotEmpty ? location : '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
      lat: lat,
      lon: lon,
      weather: weather,
    );
  } catch (_) {
    return null;
  }
}

/// Provider that loads live weather for ALL project sites that have coordinates.
final allSitesWeatherProvider =
    FutureProvider<List<ProjectSiteWeather>>((ref) async {
  final snapshot =
      await FirebaseService.instance.projectsCollection.get();

  final futures = snapshot.docs.map((doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return _fetchForProject(data, doc.id);
  });

  final results = await Future.wait(futures);
  return results.whereType<ProjectSiteWeather>().toList();
});

/// Provider that loads live weather for a SINGLE project (used by RE home).
final singleSiteWeatherProvider = FutureProvider.family<ProjectSiteWeather?,
    String>((ref, projectId) async {
  final doc = await FirebaseService.instance.projectsCollection
      .doc(projectId)
      .get();
  if (!doc.exists) return null;
  final data = doc.data() as Map<String, dynamic>? ?? {};
  return _fetchForProject(data, projectId);
});

/// Lightweight weather snapshot stored in Firestore so that the admin
/// receives persisted notifications even when RE is offline.
class SiteWeatherSnapshot {
  const SiteWeatherSnapshot({
    required this.projectId,
    required this.projectName,
    required this.location,
    required this.lat,
    required this.lon,
    required this.tempC,
    required this.condition,
    required this.description,
    required this.fetchedAt,
  });

  final String projectId;
  final String projectName;
  final String location;
  final double lat;
  final double lon;
  final double tempC;
  final String condition;
  final String description;
  final DateTime fetchedAt;

  bool get isRaining {
    final c = condition.toLowerCase();
    return c.contains('rain') ||
        c.contains('drizzle') ||
        c.contains('thunderstorm');
  }

  factory SiteWeatherSnapshot.fromFirestore(Map<String, dynamic> data) {
    final ts = data['fetchedAt'];
    return SiteWeatherSnapshot(
      projectId: (data['projectId'] ?? '').toString(),
      projectName: (data['projectName'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lon: (data['lon'] as num?)?.toDouble() ?? 0,
      tempC: (data['tempC'] as num?)?.toDouble() ?? 0,
      condition: (data['condition'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      fetchedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'projectId': projectId,
        'projectName': projectName,
        'location': location,
        'lat': lat,
        'lon': lon,
        'tempC': tempC,
        'condition': condition,
        'description': description,
        'fetchedAt': Timestamp.fromDate(fetchedAt),
      };
}

/// Stream provider for admin — watches real-time weather snapshots from Firestore.
/// Permission errors return an empty list so the map can still load from projects.
final adminSiteWeatherSnapshotsProvider =
    StreamProvider<List<SiteWeatherSnapshot>>((ref) async* {
  try {
    final stream = FirebaseService.instance.firestore
        .collection('site_weather_snapshots')
        .orderBy('fetchedAt', descending: true)
        .snapshots();
    await for (final snap in stream) {
      yield snap.docs
          .map((d) => SiteWeatherSnapshot.fromFirestore(d.data()))
          .toList();
    }
  } catch (_) {
    yield const <SiteWeatherSnapshot>[];
  }
});

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool _isValidLatLon(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  if (lat.abs() > 90 || lon.abs() > 180) return false;
  return true;
}

String _placeName(Map<String, dynamic> data) {
  final geo = (data['geoAddress'] ?? '').toString().trim();
  if (geo.isNotEmpty) return geo;
  final location = (data['location'] ?? '').toString().trim();
  if (location.isNotEmpty) return location;
  final city = (data['city'] ?? data['municipality'] ?? '').toString().trim();
  return city;
}

/// Live-loads every active admin project onto the map, with a pin and place name.
/// New projects appear automatically. Geocodes the stored location when
/// latitude/longitude are missing, then saves the pin on the project.
final adminProjectMapSitesProvider =
    StreamProvider<List<SiteWeatherSnapshot>>((ref) async* {
  final weather = WeatherService.instance;
  final stream = FirebaseService.instance.projectsCollection.snapshots();

  await for (final snapshot in stream) {
    Future<SiteWeatherSnapshot?> mapDoc(QueryDocumentSnapshot doc) async {
    final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if (data['isArchived'] == true) return null;
    if (data['isActive'] == false) return null;

    final name =
        (data['name'] ?? data['projectName'] ?? 'Untitled project').toString();
    var place = _placeName(data);
    var lat = _asDouble(data['latitude']);
    var lon = _asDouble(data['longitude']);

    if (!_isValidLatLon(lat, lon)) {
      final query = place.isNotEmpty ? place : name;
      final geo = await weather.resolveOpenMeteoCoordinates(query);
      if (geo == null || !_isValidLatLon(geo.lat, geo.lon)) return null;
      lat = geo.lat;
      lon = geo.lon;
      if (place.isEmpty) place = geo.label;
      try {
        await doc.reference.set(
          <String, dynamic>{
            'latitude': lat,
            'longitude': lon,
            if ((data['geoAddress'] ?? '').toString().trim().isEmpty)
              'geoAddress': geo.label,
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }

    if (!_isValidLatLon(lat, lon)) return null;
    final pinLat = lat!;
    final pinLon = lon!;

    var tempC = 0.0;
    var condition = 'Clear';
    var description = '';
    try {
      final live =
          await weather.getOpenMeteoLiveReport(lat: pinLat, lon: pinLon);
      tempC = live.rawTempC ?? 0;
      condition = live.rainIsComing ? 'Rain' : 'Clear';
      description = live.rainForecast;
    } catch (_) {}

    return SiteWeatherSnapshot(
      projectId: doc.id,
      projectName: name,
      location: place.isNotEmpty
          ? place
          : '${pinLat.toStringAsFixed(4)}, ${pinLon.toStringAsFixed(4)}',
      lat: pinLat,
      lon: pinLon,
      tempC: tempC,
      condition: condition,
      description: description,
      fetchedAt: DateTime.now(),
    );
  }

    final mapped = await Future.wait(snapshot.docs.map(mapDoc));
    yield mapped.whereType<SiteWeatherSnapshot>().toList();
  }
});
