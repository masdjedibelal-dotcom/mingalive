import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_location.dart';
import '../services/location_service.dart';
import '../utils/geo.dart';

class LocationStore extends ChangeNotifier {
  LocationStore({LocationService? service})
      : _service = service ?? LocationService();

  static final StreamController<AppLocation> _locationBus =
      StreamController<AppLocation>.broadcast();
  final LocationService _service;
  StreamSubscription<AppLocation>? _locationSubscription;
  StreamSubscription<AppLocation>? _busSubscription;
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
    _subscribeToBus();
    notifyListeners();

    await _loadPersistedLocation();
    if (!_manualOverride) {
      _service.getCurrentLocation().then((gpsLocation) {
        if (gpsLocation == null) return;
        if (_manualOverride) return;
        _applyLocation(gpsLocation, broadcast: true);
      });
    }
    _startLocationStream();
  }

  void setManualLocation(AppLocation location) {
    _manualOverride = true;
    if (_isWithinServiceArea(location.lat, location.lng)) {
      _currentLocation = location;
      _clearPersistedLocation();
    } else {
      _currentLocation = const AppLocation(
        label: 'München Zentrum',
        lat: _centerLat,
        lng: _centerLng,
        source: AppLocationSource.fallback,
      );
      _clearPersistedLocation();
    }
    _stopLocationStream();
    notifyListeners();
    _broadcastLocation(_currentLocation!);
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
    _broadcastLocation(_currentLocation!);
    _startLocationStream();
  }

  Future<void> _loadPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isManual = prefs.getBool(_keyManual) ?? false;
      if (!isManual) return;
      await _clearPersistedLocation();
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
          _stopLocationStream();
          _broadcastLocation(next);
        }
        return;
      }

      if (_manualOverride) {
        return;
      }
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
      _broadcastLocation(_currentLocation!);
      _startLocationStream();
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

  void _subscribeToBus() {
    _busSubscription ??= _locationBus.stream.listen((location) {
      final current = _currentLocation;
      if (current != null && _isSameLocation(current, location)) return;
      if (_manualOverride && location.source != AppLocationSource.manual) {
        return;
      }
      if (location.source == AppLocationSource.manual) {
        _manualOverride = true;
        _stopLocationStream();
      } else {
        if (_manualOverride) return;
        _manualOverride = false;
      }
      _currentLocation = location;
      notifyListeners();
    });
  }

  void _broadcastLocation(AppLocation location) {
    _locationBus.add(location);
  }

  void _startLocationStream() {
    if (_manualOverride) return;
    _locationSubscription?.cancel();
    _locationSubscription = _service
        .watchLocation(distanceFilterMeters: 80)
        .listen((gpsLocation) {
      if (_manualOverride) return;
      final next = _normalizeGpsLocation(gpsLocation);
      final current = _currentLocation;
      if (current != null && _isSameLocation(current, next)) return;
      if (current != null &&
          haversineDistanceKm(
                current.lat,
                current.lng,
                next.lat,
                next.lng,
              ) <
              0.05) {
        return;
      }
      _currentLocation = next;
      notifyListeners();
      _broadcastLocation(next);
    });
  }

  void _stopLocationStream() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  AppLocation _normalizeGpsLocation(AppLocation gpsLocation) {
    if (_isWithinServiceArea(gpsLocation.lat, gpsLocation.lng)) {
      return gpsLocation;
    }
    return const AppLocation(
      label: 'München Zentrum',
      lat: _centerLat,
      lng: _centerLng,
      source: AppLocationSource.fallback,
    );
  }

  AppLocation _applyLocation(AppLocation location, {bool broadcast = false}) {
    _currentLocation = location;
    notifyListeners();
    if (broadcast) {
      _broadcastLocation(location);
    }
    return location;
  }

  bool _isSameLocation(AppLocation a, AppLocation b) {
    return a.lat == b.lat &&
        a.lng == b.lng &&
        a.label == b.label &&
        a.source == b.source;
  }

  @override
  void dispose() {
    _stopLocationStream();
    _busSubscription?.cancel();
    super.dispose();
  }
}

