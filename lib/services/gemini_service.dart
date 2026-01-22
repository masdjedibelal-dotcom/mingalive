import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Service for interacting with Google Gemini AI
class GeminiService {
  /// Route a user query using Gemini AI
  /// Returns a Map with action, category, filters, placeQuery, searchTerm, cuisine, trip, and assistantText
  Future<Map<String, dynamic>> routeQuery({
    required String query,
    required List<Map<String, String>> placeIndex,
  }) async {
    // Read API key from environment
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      throw Exception(
        'Gemini API key missing. Use --dart-define=GEMINI_API_KEY=...',
      );
    }

    // Initialize model
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 1024,
      ),
    );

    // Build place index text for prompt
    final placeIndexText = placeIndex
        .map((p) => '${p['id']}: ${p['name']} (${p['category']})')
        .join('\n');

    // Build prompt
    final prompt = '''
You are a routing engine for a Munich discovery app.
Return STRICT JSON output only. No markdown. No extra text. No explanations.

Schema:
{
  "action": "open_list|open_stream|open_detail|open_chat|plan_trip|answer_only",
  "category": "RAMEN|BIERGARTEN|EVENTS|KAFFEE|null",
  "filters": {
    "spicy": true/false,
    "openNow": true/false,
    "vibe": "date|solo|group|null"
  },
  "placeQuery": "string|null",
  "searchTerm": "string|null",
  "cuisine": "string|null",
  "trip": {
    "durationMinutes": number|null,
    "startArea": "string|null",
    "themes": ["string"]
  },
  "assistantText": "string"
}

Rules:
- If user asks to plan a trip/route (trip/plan/route/stunden), always use action=plan_trip.
  - If duration is missing, default durationMinutes=180.
- If user expresses a general need ("ich will ...", "ich möchte ...", "suche ...", "wo gibt es ..."):
  - Use action=open_list even if category is null.
  - Put the key intent into searchTerm (e.g. "scharf essen", "vietnamesisch", "date idee", "ruhig cafe").
  - If cuisine is detectable, set cuisine (thai/indian/korean/mexican/vietnamese/italian/etc).
- If user mentions "scharf/spicy", set filters.spicy=true.
- If user mentions "live/was geht/stream/gerade", set action=open_stream.
- If user mentions a specific place name, set action=open_detail and set placeQuery.
- assistantText: exactly 1 short German sentence.
- If uncertain, use answer_only with a helpful suggestion.

Available places (id, name, category):
$placeIndexText

User query: "$query"
''';

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final text = response.text ?? '{}';

      // Trim output
      final cleanedText = text.trim();

      // Parse JSON
      try {
        final jsonMap = jsonDecode(cleanedText) as Map<String, dynamic>;
        return jsonMap;
      } catch (e) {
        throw FormatException(
          'Failed to parse Gemini response as JSON: $e\nRaw response: $cleanedText',
          cleanedText,
        );
      }
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw Exception('Failed to get response from Gemini: $e');
    }
  }
}
