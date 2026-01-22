import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_location.dart';

class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);
}

class LocationService {
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
      return AppLocation(
        label: 'In deiner Nähe',
        lat: position.latitude,
        lng: position.longitude,
        source: AppLocationSource.gps,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LatLng> getOriginOrFallback() async {
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

  Future<bool> _hasLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied || status.isRestricted || status.isLimited) {
      await Permission.location.request();
      status = await Permission.location.status;
    }

    if (status.isPermanentlyDenied) {
      return false;
    }

    return status.isGranted || status.isLimited;
  }
}

