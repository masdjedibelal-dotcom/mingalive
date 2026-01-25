import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../services/supabase_gate.dart';

class EventRepository {
  Future<List<Event>> fetchUpcomingEvents({
    String? category,
    String? searchTerm,
  }) async {
    if (!SupabaseGate.isEnabled) return [];
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    try {
      var query = SupabaseGate.client
          .from('events')
          .select()
          .eq('is_public', true)
          .eq('is_cancelled', false);

      final trimmedCategory = category?.trim();
      if (trimmedCategory != null && trimmedCategory.isNotEmpty) {
        query = query.eq('category', trimmedCategory);
      }

      final trimmedSearch = searchTerm?.trim();
      if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
        query = query.ilike('title', '%$trimmedSearch%');
      }

      final response = await query
          .gte('start_datetime', nowUtc)
          .order('start_datetime', ascending: true);
      final rows = (response as List).whereType<Map<String, dynamic>>().toList();
      final now = DateTime.now();
      final events = rows.map(Event.fromSupabase).where((event) {
        if (event.isCancelled || !event.isPublic) return false;
        return !event.isExpired(now);
      }).toList();
      events.sort((a, b) {
        final aStart = a.effectiveStart;
        final bStart = b.effectiveStart;
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
      return events;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ EventRepository: fetchUpcomingEvents failed: $e');
      }
      return [];
    }
  }

  Future<List<Event>> fetchEventsThisWeek() async {
    final now = DateTime.now();
    final endOfWeek = _endOfWeek(now);
    final events = await fetchUpcomingEvents();
    final filtered = events.where((event) {
      final start = event.effectiveStart;
      if (start == null) return false;
      final localStart = start.toLocal();
      return localStart.isBefore(endOfWeek);
    }).toList();
    filtered.sort((a, b) {
      final aStart = a.effectiveStart;
      final bStart = b.effectiveStart;
      if (aStart == null && bStart == null) return 0;
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      return aStart.compareTo(bStart);
    });
    return filtered;
  }

  DateTime _endOfWeek(DateTime now) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final daysFromMonday = now.weekday - DateTime.monday;
    final startOfWeek = startOfDay.subtract(Duration(days: daysFromMonday));
    return startOfWeek.add(const Duration(days: 7));
  }

  Future<List<String>> fetchCategories({int limit = 1000}) async {
    if (!SupabaseGate.isEnabled) return [];
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    try {
      final response = await SupabaseGate.client
          .from('events')
          .select('category,start_datetime,is_public,is_cancelled')
          .eq('is_public', true)
          .eq('is_cancelled', false)
          .gte('start_datetime', nowUtc)
          .order('start_datetime', ascending: true)
          .limit(limit);
      final rows = (response as List).whereType<Map<String, dynamic>>().toList();
      final categories = rows
          .map((row) => row['category']?.toString())
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b));
      return categories;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ EventRepository: fetchCategories failed: $e');
      }
      return [];
    }
  }

  Future<List<Event>> searchFutureEvents({
    required String query,
  }) async {
    if (!SupabaseGate.isEnabled) return [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    try {
      final response = await SupabaseGate.client
          .from('events')
          .select()
          .eq('is_public', true)
          .eq('is_cancelled', false)
          .gte('start_datetime', nowUtc)
          .or(
            'title.ilike.%$trimmed%,description.ilike.%$trimmed%,venue_name.ilike.%$trimmed%',
          )
          .order('start_datetime', ascending: true);
      final rows = (response as List).whereType<Map<String, dynamic>>().toList();
      final now = DateTime.now();
      final events = rows.map(Event.fromSupabase).where((event) {
        if (event.isCancelled || !event.isPublic) return false;
        return !event.isExpired(now);
      }).toList();
      events.sort((a, b) {
        final aStart = a.effectiveStart;
        final bStart = b.effectiveStart;
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
      return events;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ EventRepository: searchFutureEvents failed: $e');
      }
      return [];
    }
  }
}

