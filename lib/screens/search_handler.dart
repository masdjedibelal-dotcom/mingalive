import '../data/place_repository.dart';
import '../models/place.dart';

/// Search action types
enum SearchActionType {
  openList,
  openStream,
  openDetail,
  openChat,
}

/// Result of a search query parse
class SearchActionResult {
  final SearchActionType type;
  final String? categoryName;
  final String? placeId;

  const SearchActionResult({
    required this.type,
    this.categoryName,
    this.placeId,
  });
}

/// Lightweight search handler for parsing queries and determining actions
class SearchHandler {
  final PlaceRepository _repository = PlaceRepository();

  /// Parse query and return appropriate action
  SearchActionResult parseQuery(String query) {
    if (query.trim().isEmpty) {
      // Empty query - no action
      return const SearchActionResult(type: SearchActionType.openList);
    }

    final lowerQuery = query.toLowerCase().trim();

    // 1. Check for stream keywords
    if (_isStreamQuery(lowerQuery)) {
      return const SearchActionResult(type: SearchActionType.openStream);
    }

    // 2. Check for category keywords
    final category = _extractCategory(lowerQuery);
    if (category != null) {
      return SearchActionResult(
        type: SearchActionType.openList,
        categoryName: category,
      );
    }

    // 3. Check for chat keywords
    if (_isChatQuery(lowerQuery)) {
      final place = _findBestPlaceMatch(lowerQuery);
      if (place != null) {
        return SearchActionResult(
          type: SearchActionType.openChat,
          placeId: place.id,
        );
      }
    }

    // 4. Try to find place match
    final place = _findBestPlaceMatch(lowerQuery);
    if (place != null) {
      return SearchActionResult(
        type: SearchActionType.openDetail,
        placeId: place.id,
      );
    }

    // 5. Fallback: if query contains category-like terms, try category
    final fallbackCategory = _tryExtractCategoryFromQuery(lowerQuery);
    if (fallbackCategory != null) {
      return SearchActionResult(
        type: SearchActionType.openList,
        categoryName: fallbackCategory,
      );
    }

    // No match found
    return const SearchActionResult(type: SearchActionType.openList);
  }

  /// Check if query indicates stream intent
  bool _isStreamQuery(String query) {
    final streamKeywords = ['live', 'was geht', 'stream', 'was läuft', 'was geht ab'];
    return streamKeywords.any((keyword) => query.contains(keyword));
  }

  /// Check if query indicates chat intent
  bool _isChatQuery(String query) {
    final chatKeywords = ['chat', 'nachricht', 'kommentar', 'schreiben'];
    return chatKeywords.any((keyword) => query.contains(keyword));
  }

  /// Extract category from query if present
  String? _extractCategory(String query) {
    // Direct category matches
    if (query.contains('ramen') || query.contains('nudeln') || query.contains('japanisch')) {
      return 'RAMEN';
    }
    if (query.contains('bier') || query.contains('biergarten') || query.contains('oktoberfest')) {
      return 'BIERGARTEN';
    }
    if (query.contains('event') || query.contains('konzert') || query.contains('festival')) {
      return 'EVENTS';
    }
    if (query.contains('kaffee') || query.contains('cafe') || query.contains('café') || query.contains('coffee')) {
      return 'KAFFEE';
    }
    return null;
  }

  /// Try to extract category from general query terms
  String? _tryExtractCategoryFromQuery(String query) {
    // More flexible category matching
    if (query.contains('essen') || query.contains('restaurant')) {
      // Could be any category, but default to RAMEN
      return 'RAMEN';
    }
    if (query.contains('trinken') || query.contains('bar')) {
      return 'BIERGARTEN';
    }
    return null;
  }

  /// Find best matching place for query
  Place? _findBestPlaceMatch(String query) {
    final results = _repository.searchLocal(query);
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

    // Otherwise return first result (already sorted by relevance in searchLocal)
    return results.first;
  }
}

