import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'supabase_gate.dart';
import 'auth_service.dart';
import '../models/collab.dart' as collab_models;

class Collab {
  final String id;
  final String ownerId;
  final String title;
  final String? description;
  final bool isPublic;
  final List<String> coverMediaUrls;
  final DateTime createdAt;
  final String? creatorDisplayName;
  final String? creatorUsername;
  final String? creatorAvatarUrl;
  final String? creatorBadge;

  const Collab({
    required this.id,
    required this.ownerId,
    required this.title,
    this.description,
    required this.isPublic,
    required this.coverMediaUrls,
    required this.createdAt,
    this.creatorDisplayName,
    this.creatorUsername,
    this.creatorAvatarUrl,
    this.creatorBadge,
  });

  factory Collab.fromJson(Map<String, dynamic> json) {
    final profile =
        json['profiles'] is Map ? Map<String, dynamic>.from(json['profiles']) : null;
    final creatorId = json['creator_id'] as String? ?? json['owner_id'] as String;
    return Collab(
      id: json['id'] as String,
      ownerId: creatorId,
      title: json['title'] as String,
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      coverMediaUrls: _parseMediaUrls(json['cover_media_urls']),
      createdAt: DateTime.parse(json['created_at'] as String),
      creatorDisplayName: profile?['display_name'] as String?,
      creatorUsername: profile?['username'] as String?,
      creatorAvatarUrl: profile?['avatar_url'] as String?,
      creatorBadge: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'description': description,
      'is_public': isPublic,
      'cover_media_urls': coverMediaUrls,
      'created_at': createdAt.toIso8601String(),
      if (creatorDisplayName != null) 'creator_display_name': creatorDisplayName,
      if (creatorUsername != null) 'creator_username': creatorUsername,
      if (creatorAvatarUrl != null) 'creator_avatar_url': creatorAvatarUrl,
      if (creatorBadge != null) 'creator_badge': creatorBadge,
    };
  }

  static List<String> _parseMediaUrls(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
      } catch (_) {}
    }
    return [];
  }
}

class SupabaseCollabsRepository {
  static final SupabaseCollabsRepository _instance =
      SupabaseCollabsRepository._internal();
  factory SupabaseCollabsRepository() => _instance;
  SupabaseCollabsRepository._internal();
  static const String _collabSelect =
      '*, profiles:creator_id(id, username, display_name, avatar_url)';

  Future<Collab?> createCollab({
    required String title,
    String? description,
    required bool isPublic,
    required List<String> coverMediaUrls,
    List<String> placeIds = const [],
  }) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    final supabase = SupabaseGate.client;
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return null;
    }

    try {
      final payload = {
        'owner_id': currentUser.id,
        'creator_id': currentUser.id,
        'title': title,
        'description': description,
        'is_public': isPublic,
        'cover_media_urls': coverMediaUrls,
      };

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: insert collabs title=$title',
        );
      }

      final response = await supabase
          .from('collabs')
          .insert(payload)
          .select(_collabSelect)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      final collab = Collab.fromJson(Map<String, dynamic>.from(response));

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: insert collabs count=1',
        );
      }

      if (placeIds.isNotEmpty) {
        final items = <Map<String, dynamic>>[];
        for (var i = 0; i < placeIds.length; i++) {
          items.add({
            'collab_id': collab.id,
            'place_id': placeIds[i],
            'position': i,
          });
        }

        if (kDebugMode) {
          debugPrint(
            '🟣 SupabaseCollabsRepository: insert collab_items collab_id=${collab.id}',
          );
        }

        await supabase.from('collab_items').insert(items);

        if (kDebugMode) {
          debugPrint(
            '🟣 SupabaseCollabsRepository: insert collab_items count=${items.length}',
          );
        }
      }

      return collab;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: create collab failed: $e');
      }
      return null;
    }
  }

  Future<List<Collab>> fetchPublicCollabs() async {
    return _fetchCollabs(
      queryLabel: 'collabs public',
      queryBuilder: (supabase) => supabase
          .from('collabs')
          .select(_collabSelect)
          .eq('is_public', true)
          .order('created_at', ascending: false),
    );
  }

  Future<Collab?> fetchCollabById(String collabId) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint('🟣 SupabaseCollabsRepository: select collab id=$collabId');
      }

      final response = await supabase
          .from('collabs')
          .select(_collabSelect)
          .eq('id', collabId)
          .maybeSingle();

      if (response == null) {
        if (kDebugMode) {
          debugPrint('🟣 SupabaseCollabsRepository: select collab count=0');
        }
        return null;
      }

      if (kDebugMode) {
        debugPrint('🟣 SupabaseCollabsRepository: select collab count=1');
      }

      return Collab.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch collab failed: $e');
      }
      return null;
    }
  }

  Future<bool> updateCollab({
    required String collabId,
    String? title,
    String? description,
    bool? isPublic,
    List<String>? coverMediaUrls,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return false;
    }

    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (description != null) payload['description'] = description;
    if (isPublic != null) payload['is_public'] = isPublic;
    if (coverMediaUrls != null) payload['cover_media_urls'] = coverMediaUrls;

    if (payload.isEmpty) return true;

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint('🟣 SupabaseCollabsRepository: update collab id=$collabId');
      }

      final response = await supabase
          .from('collabs')
          .update(payload)
          .eq('id', collabId)
          .select();

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: update collab count=${(response as List).length}',
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: update collab failed: $e');
      }
      return false;
    }
  }

  Future<String?> uploadCollabMedia({
    required String userId,
    required String collabId,
    required List<int> bytes,
    required String filename,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      final ext = _extensionFromFilename(filename);
      final mediaId = _uuidV4();
      final path = 'collabs/$collabId/$mediaId.$ext';

      if (kDebugMode) {
        debugPrint('🟣 SupabaseCollabsRepository: upload media path=$path');
      }

      await supabase.storage
          .from('collab_media')
          .uploadBinary(path, Uint8List.fromList(bytes));

      final publicUrl = supabase.storage
          .from('collab_media')
          .getPublicUrl(path);

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: upload media url=$publicUrl',
        );
      }

      return publicUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: upload media failed: $e');
      }
      return null;
    }
  }

  Future<List<collab_models.CollabMediaItem>> fetchCollabMediaItems(
    String collabId,
  ) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('collab_media_items')
          .select('*')
          .eq('collab_id', collabId)
          .order('sort_order', ascending: true);

      final rows = response as List;
      return rows
          .map(
            (row) => collab_models.CollabMediaItem.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch media items failed: $e');
      }
      return [];
    }
  }

  Future<collab_models.CollabMediaItem?> addCollabMediaItem({
    required String collabId,
    required String userId,
    required Uint8List bytes,
    required String filename,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      final ext = _extensionFromFilename(filename);
      final mediaId = _uuidV4();
      final path = 'collabs/$collabId/$mediaId.$ext';
      final kind = _isVideoFilename(filename) ? 'video' : 'image';

      await supabase.storage.from('collab_media').uploadBinary(path, bytes);

      final publicUrl =
          supabase.storage.from('collab_media').getPublicUrl(path);

      final existingResponse = await supabase
          .from('collab_media_items')
          .select('id')
          .eq('collab_id', collabId);
      final sortOrder = (existingResponse as List).length;

      final response = await supabase
          .from('collab_media_items')
          .insert({
            'collab_id': collabId,
            'user_id': userId,
            'kind': kind,
            'storage_path': path,
            'public_url': publicUrl,
            'sort_order': sortOrder,
          })
          .select()
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return collab_models.CollabMediaItem.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: add media item failed: $e');
      }
      return null;
    }
  }

  Future<void> deleteCollabMediaItem({
    required String itemId,
    required String storagePath,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      await supabase.storage.from('collab_media').remove([storagePath]);
      await supabase.from('collab_media_items').delete().eq('id', itemId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: delete media item failed: $e');
      }
      rethrow;
    }
  }

  Future<void> reorderCollabMediaItems(
    String collabId,
    List<collab_models.CollabMediaItem> items,
  ) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final updates = <Map<String, dynamic>>[];
      for (var i = 0; i < items.length; i++) {
        updates.add({
          'id': items[i].id,
          'collab_id': collabId,
          'sort_order': i,
        });
      }
      await supabase.from('collab_media_items').upsert(
            updates,
            onConflict: 'id',
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: reorder media items failed: $e');
      }
      rethrow;
    }
  }

  Future<List<Collab>> fetchCollabsByOwner({
    required String ownerId,
    required bool isPublic,
  }) async {
    return _fetchCollabs(
      queryLabel: 'collabs owner=$ownerId public=$isPublic',
      queryBuilder: (supabase) => supabase
          .from('collabs')
          .select(_collabSelect)
          .eq('owner_id', ownerId)
          .eq('is_public', isPublic)
          .order('created_at', ascending: false),
    );
  }

  Future<List<String>> fetchCollabPlaceIds({required String collabId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_items collab_id=$collabId',
        );
      }

      final response = await supabase
          .from('collab_items')
          .select('place_id')
          .eq('collab_id', collabId);

      final rows = response as List;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_items count=${rows.length}',
        );
      }

      return rows
          .map((row) => row['place_id'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch collab items failed: $e');
      }
      return [];
    }
  }

  Future<Map<String, String>> fetchCollabPlaceNotes({
    required String collabId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('collab_items')
          .select('place_id, note')
          .eq('collab_id', collabId);

      final rows = response as List;
      final Map<String, String> notes = {};
      for (final row in rows) {
        final placeId = row['place_id'] as String?;
        final note = row['note'] as String?;
        if (placeId != null && note != null && note.trim().isNotEmpty) {
          notes[placeId] = note.trim();
        }
      }
      return notes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch notes failed: $e');
      }
      return {};
    }
  }

  Future<void> updateCollabPlaceNote({
    required String collabId,
    required String placeId,
    required String note,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      await supabase
          .from('collab_items')
          .update({'note': note.trim()})
          .eq('collab_id', collabId)
          .eq('place_id', placeId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: update note failed: $e');
      }
      rethrow;
    }
  }

  Future<void> addPlaceToCollab({
    required String collabId,
    required String placeId,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final countResponse = await supabase
          .from('collab_items')
          .select('position')
          .eq('collab_id', collabId);

      final currentItems = countResponse as List;
      final position = currentItems.length;

      await supabase.from('collab_items').upsert({
        'collab_id': collabId,
        'place_id': placeId,
        'position': position,
      }, onConflict: 'collab_id,place_id');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: add collab item failed: $e');
      }
      rethrow;
    }
  }

  Future<void> addPlacesToCollab({
    required String collabId,
    required List<String> placeIds,
  }) async {
    if (!SupabaseGate.isEnabled || placeIds.isEmpty) {
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('collab_items')
          .select('position')
          .eq('collab_id', collabId);

      final currentItems = response as List;
      final existingCount = currentItems.length;
      final items = <Map<String, dynamic>>[];
      for (var i = 0; i < placeIds.length; i++) {
        items.add({
          'collab_id': collabId,
          'place_id': placeIds[i],
          'position': existingCount + i,
        });
      }

      await supabase.from('collab_items').upsert(
            items,
            onConflict: 'collab_id,place_id',
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: add collab items failed: $e');
      }
      rethrow;
    }
  }

  Future<List<Collab>> fetchSavedCollabs({required String userId}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_saves user_id=$userId',
        );
      }

      final response = await supabase
          .from('collab_saves')
          .select('collab_id')
          .eq('user_id', userId);

      final rows = response as List;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_saves count=${rows.length}',
        );
      }

      final collabIds = rows
          .map((row) => row['collab_id'] as String?)
          .whereType<String>()
          .toList();
      if (collabIds.isEmpty) {
        return [];
      }

      return fetchCollabsByIds(collabIds);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch saved collabs failed: $e');
      }
      return [];
    }
  }

  Future<List<Collab>> fetchCollabsByIds(List<String> collabIds) async {
    if (!SupabaseGate.isEnabled || collabIds.isEmpty) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collabs by ids count=${collabIds.length}',
        );
      }

      final response = await supabase
          .from('collabs')
          .select(_collabSelect)
          .inFilter('id', collabIds);

      final rows = response as List;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collabs by ids count=${rows.length}',
        );
      }

      return rows
          .map((row) => Collab.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch collabs by ids failed: $e');
      }
      return [];
    }
  }

  Future<Map<String, int>> fetchCollabSaveCounts(List<String> collabIds) async {
    if (!SupabaseGate.isEnabled || collabIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_saves for ${collabIds.length} collabs',
        );
      }

      final response = await supabase
          .from('collab_saves')
          .select('collab_id')
          .inFilter('collab_id', collabIds);

      final rows = response as List;
      final counts = <String, int>{};
      for (final row in rows) {
        final id = row['collab_id'] as String?;
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select collab_saves count=${rows.length}',
        );
      }

      return counts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch save counts failed: $e');
      }
      return {};
    }
  }

  Future<List<Collab>> _fetchCollabs({
    required String queryLabel,
    required Future<dynamic> Function(dynamic supabase) queryBuilder,
  }) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint('🟣 SupabaseCollabsRepository: select $queryLabel');
      }

      final response = await queryBuilder(supabase);
      final rows = response as List;

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseCollabsRepository: select $queryLabel count=${rows.length}',
        );
      }

      return rows
          .map((row) => Collab.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseCollabsRepository: fetch $queryLabel failed: $e');
      }
      return [];
    }
  }

  String _extensionFromFilename(String filename) {
    final normalized = filename.toLowerCase();
    final dot = normalized.lastIndexOf('.');
    if (dot == -1 || dot == normalized.length - 1) {
      return 'jpg';
    }
    return normalized.substring(dot + 1);
  }

  bool _isVideoFilename(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi');
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String toHex(int value) => value.toRadixString(16).padLeft(2, '0');
    return '${toHex(bytes[0])}${toHex(bytes[1])}${toHex(bytes[2])}${toHex(bytes[3])}'
        '-${toHex(bytes[4])}${toHex(bytes[5])}'
        '-${toHex(bytes[6])}${toHex(bytes[7])}'
        '-${toHex(bytes[8])}${toHex(bytes[9])}'
        '-${toHex(bytes[10])}${toHex(bytes[11])}${toHex(bytes[12])}${toHex(bytes[13])}${toHex(bytes[14])}${toHex(bytes[15])}';
  }
}

