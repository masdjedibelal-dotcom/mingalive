enum AppLocationSource { gps, manual, fallback }

class AppLocation {
  final String label;
  final double lat;
  final double lng;
  final AppLocationSource source;

  const AppLocation({
    required this.label,
    required this.lat,
    required this.lng,
    required this.source,
  });
}

