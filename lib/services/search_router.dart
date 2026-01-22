import '../data/place_repository.dart';
import 'gemini_service.dart';

/// Search action types
enum SearchActionType {
  openList,
  openStream,
  openDetail,
  openChat,
  planTrip,
  answerOnly,
}

/// Result of search routing
class SearchAction {
  final SearchActionType type;
  final String? categoryName;
  final String? placeId;
  final Map<String, dynamic> filters;
  final String assistantText;
  final Map<String, dynamic>? trip;
  final String? searchTerm;
  final String? cuisine;

  const SearchAction({
    required this.type,
    this.categoryName,
    this.placeId,
    this.filters = const {},
    required this.assistantText,
    this.trip,
    this.searchTerm,
    this.cuisine,
  });
}

/// Router that uses Gemini AI to determine search actions
class SearchRouter {
  final PlaceRepository repository;
  final GeminiService _geminiService;

  SearchRouter(this.repository) : _geminiService = GeminiService();

  /// Build lightweight place index for Gemini
  List<Map<String, String>> _buildPlaceIndex() {
    return repository.getAll().map((place) {
      return {
        'id': place.id,
        'name': place.name,
        'category': place.category,
      };
    }).toList();
  }

  /// Handle a search query using Gemini AI with fallback
  Future<SearchAction> handle(String query) async {
    if (query.trim().isEmpty) {
      return const SearchAction(
        type: SearchActionType.answerOnly,
        assistantText: 'Was suchst du heute in München?',
      );
    }

    try {
      final placeIndex = _buildPlaceIndex();
      final geminiResponse = await _geminiService.routeQuery(
        query: query,
        placeIndex: placeIndex,
      );

      return _parseGeminiResponse(geminiResponse, query);
    } catch (e) {
      // Fallback to local heuristic search
      return _fallbackToLocalSearch(query);
    }
  }

  /// Parse Gemini response into SearchAction
  SearchAction _parseGeminiResponse(
    Map<String, dynamic> json,
    String originalQuery,
  ) {
    // Normalize action string to enum
    final actionStr = (json['action'] as String? ?? 'answer_only').toLowerCase();
    SearchActionType actionType;
    switch (actionStr) {
      case 'open_list':
        actionType = SearchActionType.openList;
        break;
      case 'open_stream':
        actionType = SearchActionType.openStream;
        break;
      case 'open_detail':
        actionType = SearchActionType.openDetail;
        break;
      case 'open_chat':
        actionType = SearchActionType.openChat;
        break;
      case 'plan_trip':
        actionType = SearchActionType.planTrip;
        break;
      default:
        actionType = SearchActionType.answerOnly;
    }

    // Normalize category to uppercase String?
    String? categoryName;
    final categoryValue = json['category'];
    if (categoryValue != null && categoryValue != 'null') {
      final categoryStr = categoryValue.toString().toUpperCase();
      // Validate category
      if (['RAMEN', 'BIERGARTEN', 'EVENTS', 'KAFFEE'].contains(categoryStr)) {
        categoryName = categoryStr;
      }
    }

    // Get filters
    final filtersJson = json['filters'] as Map<String, dynamic>?;
    final filters = filtersJson ?? <String, dynamic>{};

    // Get trip data
    final tripJson = json['trip'] as Map<String, dynamic>?;
    Map<String, dynamic>? trip;
    if (tripJson != null && tripJson.isNotEmpty) {
      trip = tripJson;
    }

    // Get assistant text
    final assistantText = json['assistantText'] as String? ?? '';

    // Get searchTerm and cuisine
    final searchTerm = json['searchTerm'] as String?;
    final cuisine = json['cuisine'] as String?;

    // Handle place matching for open_detail and open_chat
    String? placeId;
    if ((actionType == SearchActionType.openDetail ||
            actionType == SearchActionType.openChat) &&
        json['placeQuery'] != null) {
      final placeQuery = json['placeQuery'].toString();
      if (placeQuery.isNotEmpty && placeQuery != 'null') {
        final results = repository.searchLocal(placeQuery);
        if (results.isNotEmpty) {
          placeId = results.first.id;
        }
      }
    }

    return SearchAction(
      type: actionType,
      categoryName: categoryName,
      placeId: placeId,
      filters: filters,
      assistantText: assistantText,
      trip: trip,
      searchTerm: searchTerm,
      cuisine: cuisine,
    );
  }

  /// Fallback to local heuristic search if Gemini fails
  SearchAction _fallbackToLocalSearch(String query) {
    final lowerQuery = query.toLowerCase().trim();

    // 1) Check for stream intent
    if (isStreamIntent(lowerQuery)) {
      return const SearchAction(
        type: SearchActionType.openStream,
        assistantText: 'Öffne den Live-Stream für dich...',
      );
    }

    // 2) Check for trip intent
    if (isTripIntent(lowerQuery)) {
      final duration = parseDurationMinutes(lowerQuery);
      return SearchAction(
        type: SearchActionType.planTrip,
        assistantText: 'Ich plane dir eine Route durch München!',
        trip: {
          'durationMinutes': duration,
        },
      );
    }

    // 3) Try to find place match (strong match = exact name match or very close)
    final results = repository.searchLocal(query);
    if (results.isNotEmpty) {
      // Find best match (exact name match or very close)
      final bestMatch = results.firstWhere(
        (place) {
          final placeNameLower = place.name.toLowerCase();
          return placeNameLower == lowerQuery ||
              placeNameLower.startsWith(lowerQuery) ||
              lowerQuery.startsWith(placeNameLower) ||
              placeNameLower.contains(lowerQuery) ||
              lowerQuery.contains(placeNameLower);
        },
        orElse: () => results.first,
      );
      
      // Check if it's a strong match
      final bestNameLower = bestMatch.name.toLowerCase();
      final isStrongMatch = bestNameLower == lowerQuery ||
          bestNameLower.startsWith(lowerQuery) ||
          lowerQuery.startsWith(bestNameLower) ||
          (bestNameLower.contains(lowerQuery) && lowerQuery.length >= 3);
      
      if (isStrongMatch) {
        return SearchAction(
          type: SearchActionType.openDetail,
          placeId: bestMatch.id,
          assistantText: 'Zeige dir Details zu ${bestMatch.name}...',
        );
      }
    }

    // 4) Extract search term from general need phrases
    final searchTerm = extractSearchTerm(lowerQuery);
    if (searchTerm != null && searchTerm.isNotEmpty) {
      return SearchAction(
        type: SearchActionType.openList,
        categoryName: null,
        searchTerm: searchTerm,
        assistantText: 'Zeige dir passende Orte in München!',
      );
    }

    // 5) Fallback answer with helpful suggestion
    return SearchAction(
      type: SearchActionType.answerOnly,
      assistantText: _generateHelpfulFollowUp(),
    );
  }

  /// Check if query indicates stream intent
  bool isStreamIntent(String q) {
    final streamKeywords = [
      'live',
      'was geht',
      'gerade',
      'stream',
      'party jetzt',
    ];
    return streamKeywords.any((keyword) => q.contains(keyword));
  }

  /// Check if query indicates trip intent
  bool isTripIntent(String q) {
    final tripKeywords = [
      'trip',
      'route',
      'plan',
      'tour',
      'spaziergang',
      'stunden',
      '3h',
      '3 h',
    ];
    
    // Check for trip keywords
    if (tripKeywords.any((keyword) => q.contains(keyword))) {
      return true;
    }
    
    // Check for time patterns like "3 stunden", "2h", "3 h", "90 min"
    final timePattern = RegExp(r'(\d+)\s*(stunden|h|hour|min|minuten)');
    return timePattern.hasMatch(q);
  }

  /// Parse duration in minutes from query
  /// Returns 180 (default) if trip intent without duration, null otherwise
  int parseDurationMinutes(String q) {
    // Pattern for hours: "3 stunden", "2h", "3 h", "2 hours"
    final hourPattern = RegExp(r'(\d+)\s*(stunden|h|hour)');
    final hourMatch = hourPattern.firstMatch(q);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? '');
      if (hours != null) {
        return hours * 60; // Convert to minutes
      }
    }
    
    // Pattern for minutes: "90 min", "120 minuten", "90min"
    final minPattern = RegExp(r'(\d+)\s*(min|minuten)');
    final minMatch = minPattern.firstMatch(q);
    if (minMatch != null) {
      final minutes = int.tryParse(minMatch.group(1) ?? '');
      if (minutes != null) {
        return minutes;
      }
    }
    
    // Default to 180 minutes if trip intent detected but no duration specified
    if (isTripIntent(q)) {
      return 180;
    }
    
    return 180; // Default fallback
  }

  /// Extract search term from general need phrases
  /// Returns null if no search term can be extracted
  String? extractSearchTerm(String q) {
    final needPhrases = [
      'ich will',
      'ich möchte',
      'suche',
      'wo gibt es',
    ];

    final hasNeedPhrase = needPhrases.any((phrase) => q.contains(phrase));
    if (!hasNeedPhrase) {
      return null;
    }

    // Extract remaining intent after removing common phrases
    String searchTerm = q;
    final removePhrases = [
      ...needPhrases,
      'essen',
      'hunger',
      'restaurant',
      'essen gehen',
      'was essen',
      'suchen',
      'finden',
      'in münchen',
      'münchen',
      'mir',
      'bitte',
    ];
    
    for (final phrase in removePhrases) {
      searchTerm = searchTerm.replaceAll(phrase, '');
    }
    searchTerm = searchTerm.trim();

    // Return null if search term is empty or too short
    if (searchTerm.isEmpty || searchTerm.length < 2) {
      return null;
    }

    return searchTerm;
  }


  /// Generate a helpful follow-up question in German (1 short sentence)
  String _generateHelpfulFollowUp() {
    final suggestions = [
      'Versuch z.B. "ramen", "biergarten" oder "3 stunden spaziergang".',
      'Probiere "ich will scharf essen" oder "plan eine route".',
      'Versuch "live", "kaffee" oder "events".',
      'Z.B. "ich möchte vietnamesisch essen" oder "was geht gerade".',
    ];
    return suggestions[DateTime.now().millisecond % suggestions.length];
  }
}
