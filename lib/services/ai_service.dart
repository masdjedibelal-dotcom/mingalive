import '../data/place_repository.dart';
import '../models/place.dart';

/// Action types that the AI service can determine
enum AIActionType {
  openList,
  openStream,
  openDetail,
  openChat,
  fallback,
}

/// Result of AI query processing
class AIActionResult {
  final AIActionType actionType;
  final String? categoryName;
  final String? placeId;
  final String suggestionText;

  const AIActionResult({
    required this.actionType,
    this.categoryName,
    this.placeId,
    required this.suggestionText,
  });
}

/// Local AI service for processing search queries (no external API)
class AIService {
  /// Process query and return action result with suggestion text
  static AIActionResult processQuery(String query, PlaceRepository repo) {
    final trimmedQuery = query.trim();
    
    if (trimmedQuery.isEmpty) {
      return const AIActionResult(
        actionType: AIActionType.fallback,
        suggestionText: 'Was suchst du heute in München?',
      );
    }

    final lowerQuery = trimmedQuery.toLowerCase();

    // 1. Check for stream intent
    if (_isStreamIntent(lowerQuery)) {
      return const AIActionResult(
        actionType: AIActionType.openStream,
        suggestionText: 'Öffne den Live-Stream für dich...',
      );
    }

    // 2. Check for category detection
    final category = _detectCategory(lowerQuery);
    if (category != null) {
      return AIActionResult(
        actionType: AIActionType.openList,
        categoryName: category,
        suggestionText: 'Zeige dir die besten $category-Spots in München!',
      );
    }

    // 3. Check for chat intent
    if (_isChatIntent(lowerQuery)) {
      final place = _findBestPlaceMatch(lowerQuery, repo);
      if (place != null) {
        return AIActionResult(
          actionType: AIActionType.openChat,
          placeId: place.id,
          suggestionText: 'Öffne den Chat für ${place.name}...',
        );
      }
      return const AIActionResult(
        actionType: AIActionType.fallback,
        suggestionText: 'Konnte keinen Ort für den Chat finden.',
      );
    }

    // 4. Try to find place match
    final place = _findBestPlaceMatch(lowerQuery, repo);
    if (place != null) {
      return AIActionResult(
        actionType: AIActionType.openDetail,
        placeId: place.id,
        suggestionText: 'Zeige dir Details zu ${place.name}...',
      );
    }

    // 5. Fallback
    return const AIActionResult(
      actionType: AIActionType.fallback,
      suggestionText: 'Hmm, konnte nichts Passendes finden. Versuche es mit einer Kategorie oder einem Ortnamen.',
    );
  }

  /// Check if query indicates stream intent
  static bool _isStreamIntent(String query) {
    final streamKeywords = [
      'live',
      'was geht',
      'stream',
      'was läuft',
      'was geht ab',
      'gerade angesagt',
      'trending',
      'was ist los',
    ];
    return streamKeywords.any((keyword) => query.contains(keyword));
  }

  /// Check if query indicates chat intent
  static bool _isChatIntent(String query) {
    final chatKeywords = [
      'chat',
      'nachricht',
      'kommentar',
      'schreiben',
      'schreib',
      'message',
    ];
    return chatKeywords.any((keyword) => query.contains(keyword));
  }

  /// Detect category from query using synonyms
  static String? _detectCategory(String query) {
    // RAMEN synonyms
    if (query.contains('ramen') ||
        query.contains('nudeln') ||
        query.contains('japanisch') ||
        query.contains('japan') ||
        query.contains('sushi') ||
        query.contains('udon') ||
        query.contains('soba')) {
      return 'RAMEN';
    }

    // BIERGARTEN synonyms
    if (query.contains('bier') ||
        query.contains('biergarten') ||
        query.contains('oktoberfest') ||
        query.contains('wiesn') ||
        query.contains('biergarten') ||
        query.contains('brauhaus') ||
        query.contains('bierhalle')) {
      return 'BIERGARTEN';
    }

    // EVENTS synonyms
    if (query.contains('event') ||
        query.contains('konzert') ||
        query.contains('festival') ||
        query.contains('party') ||
        query.contains('veranstaltung') ||
        query.contains('show') ||
        query.contains('konzert')) {
      return 'EVENTS';
    }

    // KAFFEE synonyms
    if (query.contains('kaffee') ||
        query.contains('cafe') ||
        query.contains('café') ||
        query.contains('coffee') ||
        query.contains('latte') ||
        query.contains('cappuccino') ||
        query.contains('espresso') ||
        query.contains('brunch')) {
      return 'KAFFEE';
    }

    return null;
  }

  /// Find best matching place for query
  static Place? _findBestPlaceMatch(String query, PlaceRepository repo) {
    final results = repo.searchLocal(query);
    if (results.isEmpty) return null;

    // Prefer exact name matches
    final exactMatch = results.firstWhere(
      (place) => place.name.toLowerCase() == query,
      orElse: () => results.first,
    );

    // If exact match found, return it
    if (exactMatch.name.toLowerCase() == query) {
      return exactMatch;
    }

    // Otherwise return first result (best match from searchLocal)
    return results.first;
  }
}

