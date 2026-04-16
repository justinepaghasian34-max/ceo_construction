import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class GeoTagService {
  GeoTagService._();

  static final GeoTagService instance = GeoTagService._();

  Future<Map<String, dynamic>?> captureGeoTag() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String? address;
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').trim().isNotEmpty) (p.street ?? '').trim(),
            if ((p.locality ?? '').trim().isNotEmpty) (p.locality ?? '').trim(),
            if ((p.administrativeArea ?? '').trim().isNotEmpty)
              (p.administrativeArea ?? '').trim(),
            if ((p.country ?? '').trim().isNotEmpty) (p.country ?? '').trim(),
          ];
          address = parts.join(', ');
        }
      } catch (_) {
        address = null;
      }

      return <String, dynamic>{
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'address': address,
        'capturedAt': DateTime.now().toIso8601String(),
      };
    } catch (_) {
      return null;
    }
  }
}
