import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/collab.dart';
import '../models/place.dart';
import '../models/app_location.dart';
import '../services/distance_cache_service.dart';
import '../services/location_service.dart';
import '../utils/geo.dart';
import 'mock_places.dart';
import '../services/supabase_gate.dart';

class PlaceRepository {
  final List<Place> _places = MockPlaces.allPlaces;
  final DistanceCacheService _distanceCacheService = DistanceCacheService();
  final LocationService _locationService = LocationService();

  static double distanceOrInfinity(double? km) {
    return km ?? double.infinity;
  }

  static int compareByDistanceNullable(Place a, Place b) {
    final da = distanceOrInfinity(a.distanceKm);
    final db = distanceOrInfinity(b.distanceKm);
    return da.compareTo(db);
  }

  /// Activity rank for sorting: active_now > active_today > quiet
  int getActivityRank(Place place) {
    if (place.isLive || place.liveCount > 0) {
      return 2; // active_now
    }
    final lastActiveAt = place.lastActiveAt;
    if (lastActiveAt != null && _isSameDay(lastActiveAt, DateTime.now())) {
      return 1; // active_today
    }
    return 0; // quiet
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Returns the trending place: highest liveCount, tie-breaker: nearest distance
  Place getTrendingPlace() {
    final livePlaces = _places.where((place) => place.isLive).toList();
    
    if (livePlaces.isEmpty) {
      // Fallback: return place with highest rating if no live places
      _places.sort((a, b) => b.rating.compareTo(a.rating));
      return _places.first;
    }

    // Sort by liveCount descending, then distance ascending
    livePlaces.sort((a, b) {
      final liveCountComparison = b.liveCount.compareTo(a.liveCount);
      if (liveCountComparison != 0) return liveCountComparison;
      return compareByDistanceNullable(a, b);
    });

    return livePlaces.first;
  }

  /// Returns places by category, sorted by distance ascending, then rating descending
  List<Place> getByCategory(String category, {String? kind}) {
    final categoryPlaces = _places
        .where((place) => place.category.toUpperCase() == category.toUpperCase())
        .where((place) {
          if (kind == null || kind.isEmpty || kind == 'all') return true;
          return place.kind == kind;
        })
        .toList();

    categoryPlaces.sort((a, b) {
      // First sort by distance ascending
      final distanceComparison = compareByDistanceNullable(a, b);
      if (distanceComparison != 0) return distanceComparison;
      // If distance is equal, sort by rating descending
      return b.rating.compareTo(a.rating);
    });

    return categoryPlaces;
  }

  /// Returns all cached places (local/mock fallback).
  List<Place> getAllPlaces() {
    return List<Place>.from(_places);
  }

  /// Returns stream places sorted by liveCount descending, then distance ascending
  /// Only includes places that are currently live
  List<Place> getStreamPlaces() {
    final livePlaces = _places.where((place) => place.isLive).toList();

    livePlaces.sort((a, b) {
      // First sort by liveCount descending
      final liveCountComparison = b.liveCount.compareTo(a.liveCount);
      if (liveCountComparison != 0) return liveCountComparison;
      // If liveCount is equal, sort by distance ascending
      return compareByDistanceNullable(a, b);
    });

    return livePlaces;
  }

  /// Fetch stream places from Supabase (no mock ids)
  Future<List<Place>> fetchStreamPlaces({int limit = 50}) async {
    if (kDebugMode) {
      debugPrint('🟩 PlaceRepository.fetchStreamPlaces CALLED limit=$limit');
    }
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('🟩 PlaceRepository.fetchStreamPlaces source=local');
      }
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint('🟩 PlaceRepository.fetchStreamPlaces source=supabase');
        debugPrint('🟩 PlaceRepository.fetchStreamPlaces table=places');
        debugPrint(
          '🟩 PlaceRepository.fetchStreamPlaces filters=none',
        );
      }
      final response = await supabase.from('places').select('*');

      final rows = response as List;
      if (kDebugMode) {
        debugPrint('RAW_DIAG rows=${rows.length}');
        final maxRaw = rows.length < 20 ? rows.length : 20;
        for (var i = 0; i < maxRaw; i++) {
          final row = rows[i] as Map<String, dynamic>;
          debugPrint(
            'RAW_DIAG ${row['id']} | ${row['review_count']} | ${row['kind']} | ${row['lat']} | ${row['lng']}',
          );
        }

        int parseInt(dynamic value) {
          if (value is num) return value.toInt();
          if (value is String) return int.tryParse(value.trim()) ?? 0;
          return 0;
        }

        final eligibleRaw = rows.where((row) {
          if (row is! Map<String, dynamic>) return false;
          return parseInt(row['review_count']) >= 1500;
        }).length;
        debugPrint('RAW_DIAG eligible>=1500 = $eligibleRaw');
      }

      var places = rows
          .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
          .toList();
      final rawCount = places.length;

      if (kDebugMode) {
        debugPrint(
          '✅ PlaceRepository: fetched stream pool: ${places.length} (raw=$rawCount)',
        );
        final maxLog = places.length < 10 ? places.length : 10;
        for (var i = 0; i < maxLog; i++) {
          final place = places[i];
          debugPrint('🟩 PlaceRepository.stream item=${place.id} ratingCount=${place.ratingCount}');
        }
      }

      return places;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Failed to fetch stream places: $e');
      }
      rethrow;
    }
  }

  Future<List<Place>> fetchPlacesPage({
    required int offset,
    required int limit,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '🟩 PlaceRepository.fetchPlacesPage CALLED offset=$offset limit=$limit',
      );
    }
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('🟩 PlaceRepository.fetchPlacesPage source=local');
      }
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint('🟩 PlaceRepository.fetchPlacesPage source=supabase');
        debugPrint('🟩 PlaceRepository.fetchPlacesPage table=places');
      }
      final end = limit <= 0 ? offset : (offset + limit - 1);
      final response = await supabase
          .from('places')
          .select('*')
          .order('review_count', ascending: false)
          .range(offset, end);

      final places = (response as List)
          .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
          .toList();

      if (kDebugMode) {
        debugPrint(
          '✅ PlaceRepository.fetchPlacesPage count=${places.length} offset=$offset limit=$limit',
        );
      }
      return places;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository.fetchPlacesPage failed: $e');
      }
      return [];
    }
  }

  /// Search that matches on name, category, optional keywords/tags, and shortStatus
  /// Case-insensitive, partial matches allowed
  List<Place> searchLocal(String query, {String? kind}) {
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase().trim();

    return _places.where((place) {
      if (kind != null && kind.isNotEmpty && kind != 'all') {
        if (place.kind != kind) return false;
      }
      // Search in name (case-insensitive, partial match)
      if (place.name.toLowerCase().contains(lowerQuery)) return true;
      
      // Search in category (case-insensitive, partial match)
      if (place.category.toLowerCase().contains(lowerQuery)) return true;
      
      // Search in optional keywords/tags if available (case-insensitive, partial match)
      if (place.tags.isNotEmpty) {
        for (final tag in place.tags) {
          if (tag.toLowerCase().contains(lowerQuery)) return true;
        }
      }
      
      return false;
    }).toList();
  }

  /// Get a place by its ID (mock data only)
  Place? getById(String id) {
    try {
      return _places.firstWhere((place) => place.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Fetch a place by ID from Supabase (optional fallback to mock)
  /// 
  /// If SupabaseGate is enabled, fetches from Supabase table "places".
  /// Returns full Place object with all extended fields.
  /// Falls back to mock data if Supabase is disabled or request fails.
  Future<Place?> fetchById(String id, {bool allowFallback = true}) async {
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        
        final response = await supabase
            .from('places')
            .select('*')
            .eq('id', id)
            .maybeSingle();
        
        if (response != null) {
          final place = Place.fromSupabase(Map<String, dynamic>.from(response));
          final enriched = await _attachFavoritesCounts([place]);
          
          if (kDebugMode) {
            debugPrint('✅ PlaceRepository: Fetched place by id: $id');
          }
          
          return enriched.isNotEmpty ? enriched.first : place;
        }
        
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Place not found with id: $id');
        }
        
        return null;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Failed to fetch place by id from Supabase: $e');
        }
        if (!allowFallback) {
          return null;
        }
      }
    }
    
    // Fallback to mock data
    if (!allowFallback) {
      return null;
    }
    return getById(id);
  }

  /// Fetch places for a collab definition (Supabase backed)
  Future<List<Place>> fetchPlacesForCollab(CollabDefinition collab) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase.from('places').select('*');
      var places = (response as List)
          .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
          .toList();
      places = await _attachFavoritesCounts(places);

      final include = collab.query.includeCategories
          .map((value) => value.toLowerCase())
          .toList();
      final exclude = collab.query.excludeCategories
          .map((value) => value.toLowerCase())
          .toList();

      places = places.where((place) {
        final category = place.category.toLowerCase();
        if (include.isNotEmpty &&
            !include.any((value) => category.contains(value))) {
          return false;
        }
        if (exclude.isNotEmpty &&
            exclude.any((value) => category.contains(value))) {
          return false;
        }
        if (collab.query.onlySocialEnabled && !place.socialEnabled) {
          return false;
        }
        final minReviewCount = collab.query.minReviewCount;
        if (minReviewCount > 0 && place.reviewCount < minReviewCount) {
          return false;
        }
        return true;
      }).toList();

      if (collab.query.sort == 'random') {
        places = _stableShuffle(places, collab.id);
      } else {
        places.sort((a, b) {
          final reviewComparison = b.reviewCount.compareTo(a.reviewCount);
          if (reviewComparison != 0) return reviewComparison;
          return a.name.compareTo(b.name);
        });
      }

      final limit = collab.limit;
      if (limit > 0 && places.length > limit) {
        places = places.take(limit).toList();
      }

      return places;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Failed to fetch collab places: $e');
      }
      return [];
    }
  }

  /// Get all places
  List<Place> getAll() {
    return List.unmodifiable(_places);
  }

  /// Compute distanceKm for places from an AppLocation (client-side).
  List<Place> withDistances(List<Place> places, AppLocation location) {
    return places.map((place) {
      if (place.lat == null || place.lng == null) {
        return place;
      }
      final distance = haversineDistanceKm(
        location.lat,
        location.lng,
        place.lat!,
        place.lng!,
      );
      return place.copyWith(distanceKm: distance);
    }).toList();
  }

  /// Fetch places by category from Supabase (or fallback to mock)
  /// 
  /// If SupabaseGate is enabled, fetches from Supabase table "places".
  /// Filters by category and optional kind.
  /// Normalizes category string (trim, case-insensitive matching).
  /// Uses strict match first, then falls back to case-insensitive partial match.
  /// Falls back to mock data if Supabase is disabled or request fails.
  Future<List<Place>> fetchByCategory({
    required String category,
    String kind = 'food',
  }) async {
    // Guard against null/empty categories
    // Normalize: trim whitespace
    final normalizedCategory = category.trim();
    if (normalizedCategory.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Empty category provided, returning empty list');
      }
      return [];
    }

    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        
        // First try strict match (case-sensitive exact match)
        // Fetch from places table only (no joins)
        var query = supabase
            .from('places')
            .select('*')
            .eq('category', normalizedCategory);
        
        // Filter by kind if provided
        if (kind.isNotEmpty) {
          query = query.eq('kind', kind);
        }
        
        var response = await query;
        var places = (response as List)
            .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
            .toList();
        
        // If strict match returns empty, try case-insensitive partial match
        if (places.isEmpty) {
          if (kDebugMode) {
            debugPrint('ℹ️ PlaceRepository: Strict match empty, trying case-insensitive match for category $normalizedCategory');
          }
          
          var ilikeQuery = supabase
              .from('places')
              .select('*')
              .ilike('category', '%$normalizedCategory%');
          
          // Filter by kind if provided
          if (kind.isNotEmpty) {
            ilikeQuery = ilikeQuery.eq('kind', kind);
          }
          
          response = await ilikeQuery;
          places = (response as List)
              .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
              .toList();
        }
        
        places = await _attachFavoritesCounts(places);
        final enrichmentResult = await _enrichAndSortByDistance(places);
        
        if (kDebugMode) {
          debugPrint(
            '🟣 PlaceRepository: fetchByCategory kind=$kind category=$normalizedCategory count=${enrichmentResult.places.length} withDistance=${enrichmentResult.withDistance} missingCoords=${enrichmentResult.missingCoords}',
          );
        }
        
        return enrichmentResult.places;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Failed to fetch from Supabase, using fallback: $e');
        }
      }
    }
    
    // Fallback to mock data (with normalized category)
    final fallback = getByCategory(normalizedCategory, kind: kind);
    final enrichmentResult = await _enrichAndSortByDistance(fallback);
    if (kDebugMode) {
      debugPrint(
        '🟣 PlaceRepository: fetchByCategory fallback kind=$kind category=$normalizedCategory count=${enrichmentResult.places.length} withDistance=${enrichmentResult.withDistance} missingCoords=${enrichmentResult.missingCoords}',
      );
    }
    return enrichmentResult.places;
  }

  /// Search places from Supabase (or fallback to mock)
  /// 
  /// If SupabaseGate is enabled, searches in Supabase table "places".
  /// Searches in name and category fields.
  /// Falls back to mock data if Supabase is disabled or request fails.
  Future<List<Place>> search({
    required String query,
    String? kind,
  }) async {
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        
        var supabaseQuery = supabase
            .from('places')
            .select('*')
            .or('name.ilike.%$query%,category.ilike.%$query%');
        
        // Filter by kind if provided
        if (kind != null && kind.isNotEmpty) {
          supabaseQuery = supabaseQuery.eq('kind', kind);
        }
        
        final response = await supabaseQuery;
        
        var places = (response as List)
            .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
            .toList();
        places = await _attachFavoritesCounts(places);
        
        if (kDebugMode) {
          debugPrint(
            '🟣 PlaceRepository: search kind=${kind ?? 'all'} query=$query count=${places.length}',
          );
        }
        
        return places;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Failed to search in Supabase, using fallback: $e');
        }
      }
    }
    
    // Fallback to mock data
    final fallback = searchLocal(query, kind: kind);
    if (kDebugMode) {
      debugPrint(
        '🟣 PlaceRepository: search fallback kind=${kind ?? 'all'} query=$query count=${fallback.length}',
      );
    }
    return fallback;
  }

  /// Fetch trending places from Supabase (or fallback to mock)
  /// 
  /// If SupabaseGate is enabled, fetches from Supabase table "places".
  /// Sorts by review_count desc, then rating desc.
  /// Note: Activity-based sorting (liveCount, lastActiveAt) must be done separately
  /// via SupabaseChatRepository using the place's roomId.
  /// Falls back to mock data if Supabase is disabled or request fails.
  Future<List<Place>> fetchTrending({int limit = 10}) async {
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        
        // Fetch from places table only (no joins)
        final response = await supabase
            .from('places')
            .select('*')
            .order('review_count', ascending: false)
            .order('rating', ascending: false)
            .limit(limit);
        
        var places = (response as List)
            .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
            .toList();
        places = await _attachFavoritesCounts(places);
        
        if (kDebugMode) {
          debugPrint('✅ PlaceRepository: Fetched ${places.length} trending places');
        }
        
        return places;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Failed to fetch trending from Supabase, using fallback: $e');
        }
      }
    }
    
    // Fallback: return first place from mock data
    final allPlaces = getAll();
    if (allPlaces.isNotEmpty) {
      return [allPlaces.first];
    }
    return [];
  }

  /// Fetch top categories from Supabase (or fallback to mock)
  /// 
  /// If SupabaseGate is enabled, fetches from Supabase table "places".
  /// Filters by kind, selects category field, counts occurrences,
  /// and returns top 'limit' categories sorted by count descending.
  /// Falls back to mock categories if Supabase is disabled or request fails.
  Future<List<String>> fetchTopCategories({
    String kind = 'food',
    int limit = 10,
  }) async {
    if (kDebugMode) {
      debugPrint('🟨 PlaceRepository.fetchTopCategories CALLED');
    }
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        
        // Fetch all places with the specified kind
        final response = await supabase
            .from('places')
            .select('category')
            .eq('kind', kind);
        
        // Extract categories, filter null/empty
        final categories = (response as List)
            .map((row) => row['category'] as String?)
            .whereType<String>()
            .where((category) => category.isNotEmpty)
            .toList();
        
        // Count occurrences
        final categoryCounts = <String, int>{};
        for (final category in categories) {
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }
          
          // Sort by count descending, then by category name ascending
          final sortedCategories = categoryCounts.entries.toList()
            ..sort((a, b) {
              final countComparison = b.value.compareTo(a.value);
              if (countComparison != 0) return countComparison;
              return a.key.compareTo(b.key);
            });
          
          // Take top 'limit' categories
          final topCategories = sortedCategories
              .take(limit)
              .map((entry) => entry.key)
              .toList();
          
        if (kDebugMode) {
          debugPrint(
            '🟣 PlaceRepository: fetchTopCategories kind=$kind count=${topCategories.length}',
          );
        }
        
        return topCategories;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ PlaceRepository: Failed to fetch categories from Supabase, using fallback: $e');
        }
      }
    }
    
    // Fallback: return empty list (no mock categories)
    if (kDebugMode) {
      debugPrint(
        '🟣 PlaceRepository: fetchTopCategories kind=$kind count=0',
      );
    }
    return [];
  }

  /// Check if a place is favorited by a user
  ///
  /// Returns true if the place is in the user's favorites, false otherwise.
  /// Falls back to false if Supabase is disabled.
  Future<bool> isFavorite({required String placeId, required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      return false;
    }

    try {
      final supabase = SupabaseGate.client;

      final response = await supabase
          .from('favorites')
          .select()
          .eq('user_id', userId)
          .eq('place_id', placeId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Failed to check favorite: $e');
      }
      return false;
    }
  }

  /// Add a place to user's favorites
  ///
  /// Inserts a new favorite record. Does nothing if Supabase is disabled.
  Future<void> addFavorite({required String placeId, required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Cannot add favorite (Supabase disabled)');
      }
      return;
    }

    try {
      final supabase = SupabaseGate.client;

      // Use upsert to avoid duplicates (onConflict: user_id, place_id)
      await supabase.from('favorites').upsert({
        'user_id': userId,
        'place_id': placeId,
      }, onConflict: 'user_id,place_id');

      if (kDebugMode) {
        debugPrint('✅ PlaceRepository: Added favorite: place_id=$placeId, user_id=$userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ PlaceRepository: Failed to add favorite: $e');
      }
      rethrow;
    }
  }

  /// Remove a place from user's favorites
  ///
  /// Deletes the favorite record. Does nothing if Supabase is disabled.
  Future<void> removeFavorite({required String placeId, required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Cannot remove favorite (Supabase disabled)');
      }
      return;
    }

    try {
      final supabase = SupabaseGate.client;

      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('place_id', placeId);

      if (kDebugMode) {
        debugPrint('✅ PlaceRepository: Removed favorite: place_id=$placeId, user_id=$userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ PlaceRepository: Failed to remove favorite: $e');
      }
      rethrow;
    }
  }

  /// Fetch all favorite places for a user
  ///
  /// First fetches place_id list from favorites table, then fetches full Place objects.
  /// Returns empty list if Supabase is disabled or user has no favorites.
  Future<List<Place>> fetchFavorites({required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;

      // First: fetch place_id list from favorites
      final favoritesResponse = await supabase
          .from('favorites')
          .select('place_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final favorites = favoritesResponse as List;
      if (favorites.isEmpty) {
        return [];
      }

      // Extract place_ids
      final placeIds = favorites
          .map((row) => row['place_id'] as String)
          .whereType<String>()
          .toList();

      if (placeIds.isEmpty) {
        return [];
      }

      // Second: fetch places where id in (place_ids)
      // Build OR query: id.eq.place1,id.eq.place2,...
      final orFilter = placeIds.map((id) => 'id.eq.$id').join(',');
      final placesResponse = await supabase
          .from('places')
          .select('*')
          .or(orFilter);

      var places = (placesResponse as List)
          .map((row) => Place.fromSupabase(row as Map<String, dynamic>))
          .toList();
      places = await _attachFavoritesCounts(places);

      // Maintain order from favorites (most recent first)
      final placeMap = {for (var place in places) place.id: place};
      final orderedPlaces = placeIds
          .map((id) => placeMap[id])
          .whereType<Place>()
          .toList();

      if (kDebugMode) {
        debugPrint('✅ PlaceRepository: Fetched ${orderedPlaces.length} favorites for user $userId');
      }

      return orderedPlaces;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ PlaceRepository: Failed to fetch favorites: $e');
      }
      return [];
    }
  }

  Future<List<Place>> _attachFavoritesCounts(List<Place> places) async {
    if (!SupabaseGate.isEnabled || places.isEmpty) {
      return places;
    }

    try {
      final supabase = SupabaseGate.client;
      final placeIds = places.map((p) => p.id).toList();

      final response = await supabase
          .from('favorites')
          .select('place_id')
          .inFilter('place_id', placeIds);

      final counts = <String, int>{};
      for (final row in response as List) {
        final placeId = row['place_id'] as String?;
        if (placeId == null) continue;
        counts[placeId] = (counts[placeId] ?? 0) + 1;
      }

      return places
          .map((place) => place.copyWith(
                favoritesCount: counts[place.id] ?? 0,
              ))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ PlaceRepository: Failed to attach favorites counts: $e');
      }
      return places;
    }
  }

  Future<_DistanceEnrichmentResult> _enrichAndSortByDistance(
    List<Place> places,
  ) async {
    if (places.isEmpty) {
      return _DistanceEnrichmentResult(
        places: places,
        withDistance: 0,
        missingCoords: 0,
      );
    }

    final origin = await _locationService.getOriginOrFallback();
    _distanceCacheService.setOrigin(origin.lat, origin.lng);

    var withDistance = 0;
    var missingCoords = 0;

    final enriched = places.map((place) {
      if (place.lat == null || place.lng == null) {
        missingCoords += 1;
        return place.copyWith(distanceKm: null);
      }

      final cached = _distanceCacheService.getDistanceKm(place.id);
      final distanceKm = cached ??
          _distanceCacheService.computeAndCache(
            placeId: place.id,
            lat: place.lat,
            lng: place.lng,
          );
      if (distanceKm != null) {
        withDistance += 1;
      }

      return place.copyWith(distanceKm: distanceKm);
    }).toList();

    enriched.sort((a, b) {
      final distanceComparison = compareByDistanceNullable(a, b);
      if (distanceComparison != 0) return distanceComparison;
      return b.reviewCount.compareTo(a.reviewCount);
    });

    return _DistanceEnrichmentResult(
      places: enriched,
      withDistance: withDistance,
      missingCoords: missingCoords,
    );
  }

  List<Place> _stableShuffle(List<Place> places, String seed) {
    final random = Random(_seedFromString(seed));
    final shuffled = List<Place>.from(places);
    for (var i = shuffled.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    return shuffled;
  }

  int _seedFromString(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((hash & 0x0007ffff) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((hash & 0x03ffffff) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((hash & 0x00003fff) << 15));
    return hash;
  }
}

class _DistanceEnrichmentResult {
  final List<Place> places;
  final int withDistance;
  final int missingCoords;

  const _DistanceEnrichmentResult({
    required this.places,
    required this.withDistance,
    required this.missingCoords,
  });
}
