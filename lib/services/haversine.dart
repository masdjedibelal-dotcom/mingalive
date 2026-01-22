import 'dart:math';

double haversineDistanceKm({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final sinHalfDLat = sin(dLat / 2);
  final sinHalfDLng = sin(dLng / 2);
  final a = sinHalfDLat * sinHalfDLat +
      cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sinHalfDLng * sinHalfDLng;
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double degrees) => degrees * (pi / 180.0);

