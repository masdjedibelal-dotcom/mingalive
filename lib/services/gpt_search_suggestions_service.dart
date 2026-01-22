import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/place_repository.dart';
import '../models/place.dart';
import '../services/supabase_gate.dart';

class GptSearchSuggestion {
  final String title;
  final String query;
  final String reason;

  const GptSearchSuggestion({
    required this.title,
    required this.query,
    required this.reason,
  });
}

class GptSearchSuggestionsService {
  final PlaceRepository _repository;

  GptSearchSuggestionsService(this._repository);

  static const _model = 'gpt-4o-mini';
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _maxSuggestions = 6;
  static const _placesLimit = 80;

  String get _apiKey => const String.fromEnvironment('OPENAI_API_KEY');

  Future<List<GptSearchSuggestion>> fetchSuggestions({
    required String kind,
  }) async {
    if (_apiKey.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('GPT suggestions skipped: OPENAI_API_KEY missing.');
      }
      return const [];
    }

    final places = await _fetchPlacesSample(kind: kind, limit: _placesLimit);
    if (places.isEmpty) return const [];

    final prompt = _buildPrompt(kind: kind, places: places);
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'temperature': 0.4,
        'response_format': {'type': 'json_object'},
        'messages': [
          {
            'role': 'system',
            'content': 'Du bist ein Assistent für Suchvorschläge. '
                'Gib ausschließlich JSON zurück, keine Erklärtexte.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('GPT suggestions failed: ${response.statusCode}');
      }
      return const [];
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) return const [];
    final content =
        (choices.first as Map<String, dynamic>)['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) return const [];

    return _parseSuggestions(content);
  }

  Future<List<Map<String, dynamic>>> _fetchPlacesSample({
    required String kind,
    required int limit,
  }) async {
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        final response = await supabase
            .from('places')
            .select('id,name,category,kind,price,address')
            .order('review_count', ascending: false)
            .limit(limit);
        final rows = (response as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        return rows;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('GPT suggestions: Supabase fetch failed: $e');
        }
      }
    }

    // Fallback to local mock data
    final local = _repository.getAllPlaces();
    return local
        .where((place) => kind.isEmpty || place.kind == kind)
        .take(limit)
        .map((place) => _placeToMap(place))
        .toList();
  }

  Map<String, dynamic> _placeToMap(Place place) {
    return {
      'id': place.id,
      'name': place.name,
      'category': place.category,
      'kind': place.kind,
      'price': place.price,
      'address': place.address,
    };
  }

  String _buildPrompt({
    required String kind,
    required List<Map<String, dynamic>> places,
  }) {
    return '''
Erstelle $_maxSuggestions kurze, intelligente Suchvorschläge für eine App-Suche.
WICHTIG: Nutze ausschließlich die gelieferten Places-Daten. Keine externen Infos.

Aktiver Kind-Filter: "$kind"
Places-Daten (JSON Array):
${jsonEncode(places)}

Antwortformat (JSON):
{
  "suggestions": [
    {"title": "...", "query": "...", "reason": "..."}
  ]
}

Regeln:
- Maximal $_maxSuggestions Einträge
- "title" ist kurz (1-4 Wörter)
- "query" ist die tatsächliche Suche
- "reason" ist 1 kurzer Satz
- Nur Vorschläge aus den vorhandenen Places ableiten
''';
  }

  List<GptSearchSuggestion> _parseSuggestions(String content) {
    try {
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final list = decoded['suggestions'] as List<dynamic>? ?? const [];
      return list.take(_maxSuggestions).map((entry) {
        final map = entry as Map<String, dynamic>;
        return GptSearchSuggestion(
          title: (map['title'] ?? '').toString().trim(),
          query: (map['query'] ?? '').toString().trim(),
          reason: (map['reason'] ?? '').toString().trim(),
        );
      }).where((item) => item.title.isNotEmpty && item.query.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}



