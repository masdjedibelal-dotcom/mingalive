import 'haversine.dart';

class DistanceCacheService {
  double? _originLat;
  double? _originLng;
  final Map<String, double> _cache = {};

  void setOrigin(double lat, double lng) {
    final roundedLat = _round4(lat);
    final roundedLng = _round4(lng);

    final originChanged =
        _originLat != roundedLat || _originLng != roundedLng;
    if (originChanged) {
      _originLat = roundedLat;
      _originLng = roundedLng;
      _cache.clear();
    }
  }

  double? getDistanceKm(String placeId) => _cache[placeId];

  double? computeAndCache({
    required String placeId,
    required double? lat,
    required double? lng,
  }) {
    if (lat == null || lng == null) return null;
    final originLat = _originLat;
    final originLng = _originLng;
    if (originLat == null || originLng == null) return null;

    final distanceKm = haversineDistanceKm(
      lat1: originLat,
      lng1: originLng,
      lat2: lat,
      lng2: lng,
    );
    _cache[placeId] = distanceKm;
    return distanceKm;
  }

  double _round4(double value) {
    return (value * 10000).roundToDouble() / 10000;
  }
}


