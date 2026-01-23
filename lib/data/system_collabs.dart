import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/collab.dart';

class SystemCollabsStore {
  static const String _assetPath = 'assets/localspots_lists_munich_22.json';
  static List<CollabDefinition>? _cache;

  static Future<List<CollabDefinition>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(_assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final lists = (data['lists'] as List?) ?? [];
    const gradientKeys = ['mint', 'sunset', 'calm', 'deep'];
    var gradientIndex = 0;
    final result = <CollabDefinition>[];

    for (final entry in lists) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final listId = map['list_id']?.toString() ?? '';
      if (listId.isEmpty) continue;
      if (listId == 'spots_with_website') continue;
      final title = map['title']?.toString() ?? 'Empfohlen';
      final requiresRuntime = map['requires_runtime'] == true;
      final runtimeFilters = (map['runtime_filters'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final ranking = (map['ranking'] as List? ?? [])
          .map((value) => value.toString())
          .toList();
      final spotPool = (map['spot_pool'] as List? ?? []);
      final spotPoolIds = spotPool
          .map((value) {
            if (value is Map && value['id'] != null) {
              return value['id'].toString();
            }
            return null;
          })
          .whereType<String>()
          .toList();

      final gradientKey = gradientKeys[gradientIndex % gradientKeys.length];
      gradientIndex += 1;

      result.add(
        CollabDefinition(
          id: listId,
          title: title,
          subtitle: 'Von LocalSpots für dich',
          creatorId: 'localspots',
          creatorName: 'LocalSpots',
          creatorAvatarUrl: null,
          heroType: 'gradient',
          gradientKey: gradientKey,
          query: const CollabQuery(),
          limit: spotPoolIds.length,
          spotPoolIds: spotPoolIds,
          requiresRuntime: requiresRuntime,
          runtimeFilters: runtimeFilters,
          ranking: ranking,
        ),
      );
    }

    _cache = result;
    return result;
  }

  static CollabDefinition? findById(String id) {
    final cached = _cache;
    if (cached == null) return null;
    for (final collab in cached) {
      if (collab.id == id) return collab;
    }
    return null;
  }
}

