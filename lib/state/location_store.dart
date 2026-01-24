import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_location.dart';
import '../services/location_service.dart';
import '../utils/geo.dart';

class LocationStore extends ChangeNotifier {
  LocationStore({LocationService? service})
      : _service = service ?? LocationService();

  final LocationService _service;
  AppLocation? _currentLocation;
  bool _manualOverride = false;
  static const _keyLabel = 'location_label';
  static const _keyLat = 'location_lat';
  static const _keyLng = 'location_lng';
  static const _keyManual = 'location_manual';

  static const double _centerLat = 48.137154;
  static const double _centerLng = 11.576124;
  static const double _maxDistanceKm = 30;

  AppLocation get currentLocation {
    return _currentLocation ??
        const AppLocation(
          label: 'München Zentrum',
          lat: _centerLat,
          lng: _centerLng,
          source: AppLocationSource.fallback,
        );
  }

  Future<void> init() async {
    _currentLocation = const AppLocation(
      label: 'München Zentrum',
      lat: _centerLat,
      lng: _centerLng,
      source: AppLocationSource.fallback,
    );
    notifyListeners();

    await _loadPersistedLocation();
    if (!_manualOverride) {
      _service.getCurrentLocation().then((gpsLocation) {
        if (gpsLocation == null) return;
        if (_manualOverride) return;
        _currentLocation = gpsLocation;
        notifyListeners();
      });
    }
  }

  void setManualLocation(AppLocation location) {
    _manualOverride = true;
    if (_isWithinServiceArea(location.lat, location.lng)) {
      _currentLocation = location;
      _persistManualLocation(location);
    } else {
      _currentLocation = const AppLocation(
        label: 'München Zentrum',
        lat: _centerLat,
        lng: _centerLng,
        source: AppLocationSource.fallback,
      );
      _clearPersistedLocation();
    }
    notifyListeners();
  }

  Future<void> useMyLocation() async {
    _manualOverride = false;
    await _clearPersistedLocation();
    final gpsLocation = await _service.getCurrentLocation();
    if (gpsLocation != null &&
        _isWithinServiceArea(gpsLocation.lat, gpsLocation.lng)) {
      _currentLocation = gpsLocation;
    } else {
      _currentLocation = const AppLocation(
        label: 'München Zentrum',
        lat: _centerLat,
        lng: _centerLng,
        source: AppLocationSource.fallback,
      );
    }
    notifyListeners();
  }

  Future<void> _loadPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isManual = prefs.getBool(_keyManual) ?? false;
      if (!isManual) return;
      final label = prefs.getString(_keyLabel);
      final lat = prefs.getDouble(_keyLat);
      final lng = prefs.getDouble(_keyLng);
      if (label == null || lat == null || lng == null) return;
      _manualOverride = true;
      _currentLocation = AppLocation(
        label: label,
        lat: lat,
        lng: lng,
        source: AppLocationSource.manual,
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isManual = prefs.getBool(_keyManual) ?? false;
      if (isManual) {
        final label = prefs.getString(_keyLabel);
        final lat = prefs.getDouble(_keyLat);
        final lng = prefs.getDouble(_keyLng);
        if (label == null || lat == null || lng == null) return;
        final next = AppLocation(
          label: label,
          lat: lat,
          lng: lng,
          source: AppLocationSource.manual,
        );
        final current = _currentLocation;
        if (current == null ||
            current.lat != next.lat ||
            current.lng != next.lng ||
            current.label != next.label ||
            current.source != next.source) {
          _manualOverride = true;
          _currentLocation = next;
          notifyListeners();
        }
        return;
      }

      if (_manualOverride) {
        _manualOverride = false;
        final gpsLocation = await _service.getCurrentLocation();
        if (gpsLocation != null &&
            _isWithinServiceArea(gpsLocation.lat, gpsLocation.lng)) {
          _currentLocation = gpsLocation;
        } else {
          _currentLocation = const AppLocation(
            label: 'München Zentrum',
            lat: _centerLat,
            lng: _centerLng,
            source: AppLocationSource.fallback,
          );
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persistManualLocation(AppLocation location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyManual, true);
      await prefs.setString(_keyLabel, location.label);
      await prefs.setDouble(_keyLat, location.lat);
      await prefs.setDouble(_keyLng, location.lng);
    } catch (_) {}
  }

  Future<void> _clearPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyManual);
      await prefs.remove(_keyLabel);
      await prefs.remove(_keyLat);
      await prefs.remove(_keyLng);
    } catch (_) {}
  }

  bool _isWithinServiceArea(double lat, double lng) {
    final distance = haversineDistanceKm(lat, lng, _centerLat, _centerLng);
    return distance <= _maxDistanceKm;
  }
}

