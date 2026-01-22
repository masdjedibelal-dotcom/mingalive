import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_gate.dart';
import '../models/user_profile.dart';

export '../models/user_profile.dart';

/// Supabase-backed profile repository
/// 
/// Requires Supabase table:
/// - public.profiles (id, username, display_name, avatar_url)
class SupabaseProfileRepository {
  static final SupabaseProfileRepository _instance = SupabaseProfileRepository._internal();
  factory SupabaseProfileRepository() => _instance;
  SupabaseProfileRepository._internal();
  final Map<String, UserProfile> _liteCache = {};
  UserProfile? getCachedProfile(String userId) {
    return _liteCache[userId];
  }

  void cacheProfile(UserProfile profile) {
    _liteCache[profile.id] = profile;
  }
  final Set<String> _upsertedProfiles = {};
  bool _loggedFetchError = false;
  bool _loggedUpsertError = false;
  bool _loggedLiteError = false;

  Future<void> ensureProfileRow({
    required String userId,
    required String name,
    String? avatarUrl,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    if (_upsertedProfiles.contains(userId)) {
      return;
    }

    await upsertProfile(
      UserProfile(
        id: userId,
        displayName: name,
        username: '',
        avatarUrl: avatarUrl,
      ),
    );
  }

  /// Fetch user profile by ID
  Future<UserProfile?> fetchUserProfile(String userId) async {
    return fetchProfile(userId);
  }

  Future<UserProfile?> fetchProfile(String userId) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .single();

      final username = response['username'] as String?;
      final displayName = response['display_name'] as String?;
      final profile = UserProfile(
        id: response['id'] as String,
        displayName: displayName,
        username: username,
        avatarUrl: response['avatar_url'] as String?,
        bio: response['bio'] as String?,
      );
      _liteCache[profile.id] = profile;
      return profile;
    } catch (e) {
      _logFetchErrorOnce('❌ SupabaseProfileRepository: Failed to fetch profile: $e');
      return null;
    }
  }

  /// Fetch minimal profile data (id, username, avatar_url, bio) with caching.
  Future<UserProfile?> fetchUserProfileLite(String userId) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    final cached = _liteCache[userId];
    if (cached != null) {
      return cached;
    }

    try {
      final profiles = await fetchLiteProfilesByIds([userId]);
      final profile = profiles.isNotEmpty ? profiles.first : null;
      if (profile != null) {
        _liteCache[userId] = profile;
      }
      return profile;
    } catch (e) {
      _logLiteErrorOnce('❌ SupabaseProfileRepository: Failed to fetch lite profile: $e');
      return null;
    }
  }

  Future<bool> upsertProfile(UserProfile profile) async {
    if (!SupabaseGate.isEnabled) {
      return false;
    }

    try {
      final supabase = SupabaseGate.client;
      final payload = {
        'id': profile.id,
        'display_name': profile.displayName,
        'username': profile.username,
        'avatar_url': profile.avatarUrl,
        'bio': profile.bio,
      };

      if (kDebugMode) {
        debugPrint('🟣 SupabaseProfileRepository: upsert profiles id=${profile.id}');
      }

      final response = await supabase
          .from('profiles')
          .upsert(payload, onConflict: 'id')
          .select();

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseProfileRepository: upsert profiles count=${(response as List).length}',
        );
      }

      _upsertedProfiles.add(profile.id);
      return true;
    } catch (e) {
      _logUpsertErrorOnce('❌ SupabaseProfileRepository: profile upsert failed: $e');
      return false;
    }
  }

  /// Update user profile fields (profiles table only)
  Future<bool> updateUserProfile({
    required String userId,
    String? name,
    String? username,
    String? avatarUrl,
    String? bio,
  }) async {
    final success = await upsertProfile(
      UserProfile(
        id: userId,
        displayName: name,
        username: username,
        avatarUrl: avatarUrl,
        bio: bio,
      ),
    );
    if (success) {
      final cached = _liteCache[userId];
      if (cached != null) {
        _liteCache[userId] = UserProfile(
          id: cached.id,
          displayName: name ?? cached.displayName,
          username: username ?? cached.username,
          avatarUrl: avatarUrl ?? cached.avatarUrl,
          bio: bio ?? cached.bio,
          badge: cached.badge,
        );
      }
    }
    return success;
  }

  Future<List<UserProfile>> fetchLiteProfilesByIds(List<String> ids) async {
    if (!SupabaseGate.isEnabled || ids.isEmpty) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio')
          .inFilter('id', ids);

      final rows = response as List;
      return rows
          .map(
            (row) => UserProfile(
              id: row['id'] as String,
              displayName: row['display_name'] as String?,
              username: row['username'] as String?,
              avatarUrl: row['avatar_url'] as String?,
              bio: row['bio'] as String?,
            ),
          )
          .toList();
    } catch (e) {
      _logLiteErrorOnce(
        '❌ SupabaseProfileRepository: Failed to fetch lite profiles: $e',
      );
      return [];
    }
  }

  /// Upload avatar image to Supabase Storage and return public URL
  Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String filename,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      const ext = 'jpg';
      final path = '$userId/avatar.$ext';
      final mimeType = lookupMimeType(filename) ?? 'image/jpeg';

      await supabase.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: mimeType,
            ),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseProfileRepository: avatar upload path=$path url=$publicUrl',
        );
      }
      return publicUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseProfileRepository: Avatar upload failed: $e');
      }
      return null;
    }
  }

  void _logFetchErrorOnce(String message) {
    if (_loggedFetchError) return;
    _loggedFetchError = true;
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void _logUpsertErrorOnce(String message) {
    if (_loggedUpsertError) return;
    _loggedUpsertError = true;
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void _logLiteErrorOnce(String message) {
    if (_loggedLiteError) return;
    _loggedLiteError = true;
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}








