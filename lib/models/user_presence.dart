/// User presence model with daily activity tracking
/// 
/// Presence scores, badges, and pinned messages are valid ONLY for today.
/// Previous days are automatically ignored through date filtering.
class UserPresence {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String roomId;
  final DateTime lastSeenAt;
  final int messageCountToday; // Messages sent today
  final int mediaCountToday; // Media posts today
  final bool isActiveToday; // Has activity today

  const UserPresence({
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.roomId,
    required this.lastSeenAt,
    required this.messageCountToday,
    required this.mediaCountToday,
    required this.isActiveToday,
  });

  /// Check if presence is from today
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final presenceDate = DateTime(lastSeenAt.year, lastSeenAt.month, lastSeenAt.day);
    return presenceDate == today;
  }

  /// Get total activity score for today (messages + media)
  int get activityScoreToday => messageCountToday + mediaCountToday;

  /// Check if user qualifies for "Heute aktiv" badge
  bool get qualifiesForActiveBadge => isActiveToday && isToday;

  /// Check if user qualifies for "Top Stimme heute" badge
  /// (Top message sender today)
  bool qualifiesForTopVoiceBadge(int threshold) {
    return isToday && messageCountToday >= threshold;
  }
}

/// Lightweight presence profile (current online users in room)
class PresenceProfile {
  final String userId;
  final String userName;
  final String? userAvatar;

  const PresenceProfile({
    required this.userId,
    required this.userName,
    this.userAvatar,
  });
}

/// Helper class for daily window filtering
class DailyWindow {
  /// Get start of today (00:00:00)
  static DateTime get todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Get end of today (23:59:59.999)
  static DateTime get todayEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  /// Check if a DateTime is today
  static bool isToday(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
    return date == today;
  }

  /// Get ISO string for today start (for Supabase queries)
  static String get todayStartIso => todayStart.toIso8601String();

  /// Get ISO string for today end (for Supabase queries)
  static String get todayEndIso => todayEnd.toIso8601String();

  /// Filter messages to only today's messages
  static List<T> filterToday<T>(List<T> items, DateTime Function(T) getDate) {
    return items.where((item) => isToday(getDate(item))).toList();
  }
}



















