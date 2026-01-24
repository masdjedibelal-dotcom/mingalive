import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_location.dart';

class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);
}

class LocationService {
  static const String _geocodeBaseUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';
  final String _apiKey = 'AIzaSyAFKjeD3q01MzDBWdubuhtFRhi3u4QbCfs';
  static const String _keyLat = 'location_lat';
  static const String _keyLng = 'location_lng';
  static const String _keyManual = 'location_manual';

  Future<AppLocation?> getCurrentLocation() async {
    final hasPermission = await _hasLocationPermission();
    if (!hasPermission) return null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 3));
      final label = await _reverseGeocodeLabel(
            position.latitude,
            position.longitude,
          ) ??
          'In deiner Nähe';
      return AppLocation(
        label: label,
        lat: position.latitude,
        lng: position.longitude,
        source: AppLocationSource.gps,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<AppLocation> watchLocation({int distanceFilterMeters = 80}) async* {
    final hasPermission = await _hasLocationPermission();
    if (!hasPermission) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final settings = LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: distanceFilterMeters,
    );
    yield* Geolocator.getPositionStream(locationSettings: settings)
        .map((position) {
      return AppLocation(
        label: 'In deiner Nähe',
        lat: position.latitude,
        lng: position.longitude,
        source: AppLocationSource.gps,
      );
    });
  }

  Future<LatLng> getOriginOrFallback() async {
    final manual = await _readManualOrigin();
    if (manual != null) {
      debugPrint('ORIGIN: manual');
      return manual;
    }

    final hasPermission = await _hasLocationPermission();
    if (hasPermission) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 3));
          debugPrint('ORIGIN: gps');
          return LatLng(position.latitude, position.longitude);
        } catch (_) {
          // Fall through to fallback.
        }
      }
    }

    debugPrint('ORIGIN: fallback');
    return const LatLng(48.137154, 11.576124);
  }

  Future<LatLng?> _readManualOrigin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isManual = prefs.getBool(_keyManual) ?? false;
      if (!isManual) return null;
      final lat = prefs.getDouble(_keyLat);
      final lng = prefs.getDouble(_keyLng);
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasLocationPermission() async {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied ||
        status == LocationPermission.deniedForever) {
      status = await Geolocator.requestPermission();
    }
    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }

  Future<String?> _reverseGeocodeLabel(double lat, double lng) async {
    if (_apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse(_geocodeBaseUrl).replace(
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': _apiKey,
          'language': 'de',
          'result_type':
              'locality|sublocality|sublocality_level_1|neighborhood',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (decoded['results'] as List?) ?? [];
      if (results.isEmpty) return null;
      final components =
          (results.first as Map<String, dynamic>)['address_components'] as List?;
      if (components == null) return null;
      String? city;
      String? district;
      for (final raw in components) {
        if (raw is! Map) continue;
        final types = (raw['types'] as List? ?? [])
            .map((value) => value.toString())
            .toList();
        final name = raw['long_name']?.toString().trim();
        if (name == null || name.isEmpty) continue;
        if (types.contains('locality') ||
            types.contains('postal_town') ||
            types.contains('administrative_area_level_3')) {
          city ??= name;
        }
        if (types.contains('sublocality') ||
            types.contains('sublocality_level_1') ||
            types.contains('neighborhood')) {
          district ??= name;
        }
      }
      if (city != null && district != null && district != city) {
        return '$city $district';
      }
      return city ?? district;
    } catch (_) {
      return null;
    }
  }
}

