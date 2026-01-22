import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

class PlacesAutocompleteService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  final String _apiKey = const String.fromEnvironment('GOOGLE_PLACES_KEY');

  String newSessionToken() => _randomToken(16);

  Future<List<PlaceSuggestion>> fetchSuggestions({
    required String input,
    required String sessionToken,
  }) async {
    if (_apiKey.isEmpty || input.trim().isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/autocomplete/json').replace(
      queryParameters: {
        'input': input,
        'key': _apiKey,
        'sessiontoken': sessionToken,
        'language': 'de',
        'components': 'country:de',
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) return [];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final predictions = decoded['predictions'] as List? ?? [];
    return predictions
        .map((item) => Map<String, dynamic>.from(item))
        .map(
          (item) => PlaceSuggestion(
            placeId: item['place_id'] as String? ?? '',
            mainText: (item['structured_formatting']?['main_text'] as String?) ??
                (item['description'] as String? ?? ''),
            secondaryText:
                (item['structured_formatting']?['secondary_text'] as String?) ??
                    '',
          ),
        )
        .where((item) => item.placeId.isNotEmpty)
        .toList();
  }

  Future<LatLng?> fetchLatLng({
    required String placeId,
    required String sessionToken,
  }) async {
    if (_apiKey.isEmpty || placeId.isEmpty) return null;
    final uri = Uri.parse('$_baseUrl/details/json').replace(
      queryParameters: {
        'place_id': placeId,
        'fields': 'geometry',
        'key': _apiKey,
        'sessiontoken': sessionToken,
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final location =
        decoded['result']?['geometry']?['location'] as Map<String, dynamic>?;
    if (location == null) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat: lat, lng: lng);
  }

  String _randomToken(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }
}

class LatLng {
  final double lat;
  final double lng;

  const LatLng({required this.lat, required this.lng});
}

