import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_gate.dart';
import '../services/auth_service.dart';

/// Service for tracking activity and generating soft presence notifications
/// 
/// Tracks:
/// - Last visit timestamp (per user)
/// - New posts/messages since last visit
/// - Contextual activity (e.g., activity in user's district)
/// 
/// Generates contextual, in-app notifications without spam
class ActivityService {
  static final ActivityService _instance = ActivityService._internal();
  factory ActivityService() => _instance;
  ActivityService._internal();

  static const String _lastVisitKey = 'last_visit_timestamp';
  static const String _lastNotificationKey = 'last_notification_timestamp';
  static const Duration _minNotificationInterval = Duration(minutes: 30); // Prevent spam

  /// Get last visit timestamp for current user
  Future<DateTime?> getLastVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.instance.currentUser?.id;
    
    if (userId == null) return null;
    
    final timestamp = prefs.getInt('${_lastVisitKey}_$userId');
    if (timestamp == null) return null;
    
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Update last visit timestamp for current user
  Future<void> updateLastVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.instance.currentUser?.id;
    
    if (userId == null) return;
    
    await prefs.setInt(
      '${_lastVisitKey}_$userId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Check if we should show a notification (anti-spam)
  Future<bool> shouldShowNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.instance.currentUser?.id;
    
    if (userId == null) return false;
    
    final lastNotification = prefs.getInt('${_lastNotificationKey}_$userId');
    if (lastNotification == null) return true;
    
    final lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(lastNotification);
    final now = DateTime.now();
    final difference = now.difference(lastNotificationTime);
    
    return difference >= _minNotificationInterval;
  }

  /// Mark notification as shown
  Future<void> markNotificationShown() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.instance.currentUser?.id;
    
    if (userId == null) return;
    
    await prefs.setInt(
      '${_lastNotificationKey}_$userId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get activity notification for user
  /// 
  /// Returns contextual notification string or null if none applicable
  Future<String?> getActivityNotification() async {
    // Check if user is logged in
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return null;
    
    // Check anti-spam
    if (!await shouldShowNotification()) return null;
    
    final lastVisit = await getLastVisit();
    if (lastVisit == null) {
      // First visit - no notification
      await updateLastVisit();
      return null;
    }
    
    // Check if last visit was recent (within last hour) - skip notification
    final now = DateTime.now();
    final timeSinceLastVisit = now.difference(lastVisit);
    if (timeSinceLastVisit.inHours < 1) {
      return null; // Too recent, no notification
    }
    
    // Count new posts since last visit
    final newPostsCount = await _countNewPostsSince(lastVisit);
    
    // Check district activity
    final districtActivity = await _checkDistrictActivity();
    
    // Generate contextual notification
    if (newPostsCount > 0) {
      return _formatNewPostsNotification(newPostsCount);
    } else if (districtActivity) {
      return "In deinem Viertel ist gerade was los";
    }
    
    return null;
  }

  /// Count new posts (messages with media) since last visit
  Future<int> _countNewPostsSince(DateTime since) async {
    if (!SupabaseGate.isEnabled) return 0;
    
    try {
      final supabase = SupabaseGate.client;
      final sinceIso = since.toIso8601String();
      
      // Count messages with media_url since last visit
      final response = await supabase
          .from('messages')
          .select('id')
          .gte('created_at', sinceIso)
          .not('media_url', 'is', null);
      
      return (response as List).length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ ActivityService: Failed to count new posts: $e');
      }
      return 0;
    }
  }

  /// Check if there's activity in user's district
  /// 
  /// Returns true if there are active places in nearby districts
  Future<bool> _checkDistrictActivity() async {
    if (!SupabaseGate.isEnabled) return false;
    
    try {
      final supabase = SupabaseGate.client;
      
      // Fetch places with recent activity (last 2 hours)
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      // Query places with active chat rooms (last_active_at within 2 hours and liveCount > 0)
      final response = await supabase
          .from('places')
          .select('*, chat_rooms!left(last_active_at)')
          .limit(50);
      
      final activePlaces = (response as List).where((row) {
        final chatRoomsData = row['chat_rooms'];
        DateTime? lastActiveAt;
        
        if (chatRoomsData != null) {
          if (chatRoomsData is List && chatRoomsData.isNotEmpty) {
            final roomData = chatRoomsData[0] as Map<String, dynamic>?;
            if (roomData != null && roomData['last_active_at'] != null) {
              try {
                lastActiveAt = DateTime.parse(roomData['last_active_at'] as String);
              } catch (e) {
                return false;
              }
            }
          } else if (chatRoomsData is Map) {
            if (chatRoomsData['last_active_at'] != null) {
              try {
                lastActiveAt = DateTime.parse(chatRoomsData['last_active_at'] as String);
              } catch (e) {
                return false;
              }
            }
          }
        }
        
        if (lastActiveAt == null) return false;
        return lastActiveAt.isAfter(twoHoursAgo);
      }).toList();
      
      // Consider it active if there are at least 3 active places
      return activePlaces.length >= 3;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ ActivityService: Failed to check district activity: $e');
      }
      return false;
    }
  }

  /// Format new posts notification
  String _formatNewPostsNotification(int count) {
    if (count == 1) {
      return "1 neuer Post seit deinem letzten Besuch";
    } else {
      return "$count neue Posts seit deinem letzten Besuch";
    }
  }
}

