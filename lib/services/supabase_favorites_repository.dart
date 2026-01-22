import 'package:flutter/foundation.dart';
import 'supabase_gate.dart';

/// Favorite list model
class FavoriteList {
  final String id;
  final String userId;
  final String title;
  final String emoji;
  final bool isPublic;
  final String? description;
  final String? type;
  final DateTime createdAt;
  final int placeCount;

  FavoriteList({
    required this.id,
    required this.userId,
    required this.title,
    required this.emoji,
    required this.isPublic,
    this.description,
    this.type,
    required this.createdAt,
    this.placeCount = 0,
  });

  factory FavoriteList.fromJson(Map<String, dynamic> json) {
    return FavoriteList(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      emoji: json['emoji'] as String? ?? '❤️',
      isPublic: json['is_public'] as bool? ?? false,
      description: json['description'] as String?,
      type: json['type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      placeCount: (json['place_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'emoji': emoji,
      'is_public': isPublic,
      'description': description,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'place_count': placeCount,
    };
  }

  bool get isCollab =>
      type == 'collab' || title.startsWith('COLLAB •');

  String get collabTitle =>
      title.startsWith('COLLAB •') ? title.replaceFirst('COLLAB •', '').trim() : title;
}

/// Supabase-backed favorites repository
/// 
/// Requires Supabase tables:
/// - public.favorites (user_id, list_id, place_id, created_at)
/// - public.favorite_lists (id, user_id, title, emoji, is_public, created_at)
class SupabaseFavoritesRepository {
  static final SupabaseFavoritesRepository _instance = SupabaseFavoritesRepository._internal();
  factory SupabaseFavoritesRepository() => _instance;
  SupabaseFavoritesRepository._internal();

  /// Fetch favorite counts for multiple places
  /// 
  /// Returns a map of placeId -> count of favorites
  /// Returns empty map if Supabase is disabled or on error
  Future<Map<String, int>> fetchFavoriteCountsForPlaces(List<String> placeIds) async {
    if (!SupabaseGate.isEnabled || placeIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;

      // Build OR filter for multiple place_ids
      if (placeIds.length == 1) {
        final response = await supabase
            .from('favorites')
            .select('place_id')
            .eq('place_id', placeIds.first);

        final favorites = response as List;
        final counts = <String, int>{};
        
        for (final favorite in favorites) {
          final placeId = favorite['place_id'] as String;
          counts[placeId] = (counts[placeId] ?? 0) + 1;
        }
        
        // Ensure all placeIds are in the map (even if count is 0)
        for (final placeId in placeIds) {
          counts.putIfAbsent(placeId, () => 0);
        }
        
        return counts;
      } else {
        // For multiple placeIds, use OR filter
        final orFilter = placeIds.map((id) => 'place_id.eq.$id').join(',');
        
        final response = await supabase
            .from('favorites')
            .select('place_id')
            .or(orFilter);

        final favorites = response as List;
        final counts = <String, int>{};
        
        for (final favorite in favorites) {
          final placeId = favorite['place_id'] as String;
          counts[placeId] = (counts[placeId] ?? 0) + 1;
        }
        
        // Ensure all placeIds are in the map (even if count is 0)
        for (final placeId in placeIds) {
          counts.putIfAbsent(placeId, () => 0);
        }
        
        return counts;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch favorite counts: $e');
      }
      return {};
    }
  }

  /// Fetch favorite lists (optionally filtered by userId)
  Future<List<FavoriteList>> fetchFavoriteLists({String? userId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;

      var query = supabase.from('favorite_lists').select('*');
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      final response = await query.order('created_at', ascending: false);

      final lists = response as List;
      return lists
          .map((list) => FavoriteList.fromJson(Map<String, dynamic>.from(list)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch favorite lists: $e');
      }
      return [];
    }
  }

  /// Fetch a collab list by title (or collab-prefixed title)
  Future<FavoriteList?> fetchCollabList({required String title}) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return null;
      }

      final prefixedTitle = _collabTitlePrefix(title);
      final response = await supabase
          .from('favorite_lists')
          .select('*')
          .eq('user_id', currentUser.id)
          .or('title.eq.$title,title.eq.$prefixedTitle')
          .order('created_at', ascending: false);

      final lists = response as List;
      if (lists.isEmpty) {
        return null;
      }

      return FavoriteList.fromJson(Map<String, dynamic>.from(lists.first));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch collab list: $e');
      }
      return null;
    }
  }

  /// Fetch public favorite lists for a user
  Future<List<FavoriteList>> fetchPublicFavoriteLists({required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;

      final response = await supabase
          .from('favorite_lists')
          .select('*')
          .eq('user_id', userId)
          .eq('is_public', true)
          .order('created_at', ascending: false);

      final lists = response as List;
      return lists
          .map((list) => FavoriteList.fromJson(Map<String, dynamic>.from(list)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch public favorite lists: $e');
      }
      return [];
    }
  }

  /// Fetch public collabs across all users
  Future<List<FavoriteList>> fetchPublicCollabs({int? limit}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      var query = supabase
          .from('favorite_lists')
          .select('*')
          .eq('is_public', true)
          .order('created_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      final lists = response as List;
      return lists
          .map((list) => FavoriteList.fromJson(Map<String, dynamic>.from(list)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch public collabs: $e');
      }
      return [];
    }
  }

  /// Count how many times a collab was saved by other users (best-effort).
  Future<int> fetchCollabSaveCount({
    required String title,
    String? ownerUserId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return 0;
    }

    try {
      final supabase = SupabaseGate.client;
      final prefixedTitle = _collabTitlePrefix(title);
      var query = supabase
          .from('favorite_lists')
          .select('id')
          .eq('type', 'collab')
          .or('title.eq.$title,title.eq.$prefixedTitle');

      if (ownerUserId != null) {
        query = query.neq('user_id', ownerUserId);
      }

      final response = await query;
      final lists = response as List;
      return lists.length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '❌ SupabaseFavoritesRepository: Failed to count collab saves: $e',
        );
      }
      return 0;
    }
  }

  /// Create a new favorite list
  Future<void> createFavoriteList({
    required String title,
    String? emoji,
    String? description,
    bool isPublic = false,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      await supabase.from('favorite_lists').insert({
        'user_id': currentUser.id,
            'title': title,
            'emoji': emoji,
            'is_public': isPublic,
        'description': description,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to create favorite list: $e');
      }
    }
  }

  /// Update list visibility (public/private)
  Future<void> updateFavoriteListVisibility({
    required String listId,
    required bool isPublic,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      await supabase
          .from('favorite_lists')
          .update({'is_public': isPublic})
          .eq('id', listId)
          .eq('user_id', currentUser.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '❌ SupabaseFavoritesRepository: Failed to update list visibility: $e',
        );
      }
    }
  }

  /// Update list fields (title/description/visibility)
  Future<void> updateFavoriteList({
    required String listId,
    String? title,
    String? description,
    bool? isPublic,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (description != null) payload['description'] = description;
      if (isPublic != null) payload['is_public'] = isPublic;

      if (payload.isEmpty) return;

      await supabase
          .from('favorite_lists')
          .update(payload)
          .eq('id', listId)
          .eq('user_id', currentUser.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '❌ SupabaseFavoritesRepository: Failed to update list: $e',
        );
      }
    }
  }

  /// Ensure a collab list exists (creates if missing) and returns it.
  Future<FavoriteList?> ensureCollabList({
    required String title,
    required String subtitle,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    final existing = await fetchCollabList(title: title);
    if (existing != null) {
      return existing;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return null;
      }

      final payload = {
        'user_id': currentUser.id,
        'title': title,
        'emoji': '✨',
        'is_public': false,
        'description': subtitle,
        'type': 'collab',
      };

      await supabase.from('favorite_lists').insert(payload);
    } catch (e) {
      try {
        final supabase = SupabaseGate.client;
        final currentUser = supabase.auth.currentUser;
        if (currentUser == null) {
          return null;
        }

        final fallbackTitle = _collabTitlePrefix(title);
        await supabase.from('favorite_lists').insert({
          'user_id': currentUser.id,
          'title': fallbackTitle,
          'emoji': '✨',
          'is_public': false,
        });
      } catch (fallbackError) {
        if (kDebugMode) {
          debugPrint(
            '❌ SupabaseFavoritesRepository: Failed to create collab list: $fallbackError',
          );
        }
        return null;
      }
    }

    return fetchCollabList(title: title);
  }

  /// Delete a favorite list by id
  Future<void> deleteFavoriteList({required String listId}) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      await supabase
          .from('favorite_lists')
          .delete()
          .eq('id', listId)
          .eq('user_id', currentUser.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to delete list: $e');
      }
    }
  }

  /// Fetch place IDs in a favorite list
  Future<List<String>> fetchPlaceIdsInList({required String listId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      var query = supabase
          .from('favorites')
          .select('place_id')
          .eq('list_id', listId);

      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        query = query.eq('user_id', currentUser.id);
      }

      final response = await query;
      final items = response as List;
      return items.map((item) => item['place_id'] as String).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to fetch places in list: $e');
      }
      return [];
    }
  }

  /// Backward-compatible wrapper
  Future<List<String>> fetchPlacesInList(String listId) async {
    return fetchPlaceIdsInList(listId: listId);
  }

  /// Add a place to a favorite list
  Future<void> addPlaceToList({
    required String listId,
    required String placeId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      // Use upsert to avoid duplicates
      await supabase.from('favorites').upsert({
        'user_id': currentUser.id,
            'list_id': listId,
            'place_id': placeId,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,list_id,place_id');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to add place to list: $e');
      }
      return;
    }
  }

  /// Remove a place from a favorite list
  Future<void> removePlaceFromList({
    required String listId,
    required String placeId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        return;
      }

      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', currentUser.id)
          .eq('list_id', listId)
          .eq('place_id', placeId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseFavoritesRepository: Failed to remove place from list: $e');
      }
      return;
    }
  }

  String _collabTitlePrefix(String title) => 'COLLAB • $title';
}

