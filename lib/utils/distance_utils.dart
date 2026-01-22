import 'dart:math';

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double degrees) => degrees * (pi / 180.0);

class DistanceCache {
  final Map<String, double> _cache = {};

  void clear() {
    _cache.clear();
  }

  double? getOrCompute({
    required String placeId,
    required double userLat,
    required double userLng,
    double? placeLat,
    double? placeLng,
  }) {
    if (placeLat == null || placeLng == null) return null;

    final cached = _cache[placeId];
    if (cached != null) return cached;

    final distanceKm = haversineKm(userLat, userLng, placeLat, placeLng);
    _cache[placeId] = distanceKm;
    return distanceKm;
  }
}

