import 'package:flutter/material.dart';
import '../models/user_presence.dart';
import '../screens/theme.dart';

/// Service for calculating local presence scores
/// 
/// Score formula: activity × reactions × recency
/// - activity: messageCountToday + mediaCountToday
/// - reactions: placeholder for future reactions (currently 1.0)
/// - recency: time-decay factor based on lastSeenAt
/// 
/// Daily reset: Scores are calculated only for today's activity
class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  /// Calculate presence score for a user
  /// 
  /// Score = activity × reactions × recency
  /// - activity: messageCountToday + mediaCountToday
  /// - reactions: currently 1.0 (placeholder for future reactions)
  /// - recency: time-decay factor (1.0 for recent, decays over time)
  double calculateScore(UserPresence presence) {
    // Activity component: messages + media
    final activity = presence.messageCountToday + presence.mediaCountToday;
    
    // Reactions component: placeholder (currently 1.0)
    // Future: could be based on likes/reactions received
    const reactions = 1.0;
    
    // Recency component: time-decay based on lastSeenAt
    final recency = _calculateRecency(presence.lastSeenAt);
    
    // Score = activity × reactions × recency
    return activity * reactions * recency;
  }

  /// Calculate recency factor (time-decay)
  /// 
  /// Returns 1.0 for very recent activity, decays over time
  /// - Last 5 minutes: 1.0
  /// - Last hour: 0.8
  /// - Last 6 hours: 0.5
  /// - Last 24 hours: 0.2
  /// - Older: 0.1
  double _calculateRecency(DateTime lastSeenAt) {
    final now = DateTime.now();
    final difference = now.difference(lastSeenAt);
    
    if (difference.inMinutes < 5) {
      return 1.0; // Very recent
    } else if (difference.inHours < 1) {
      return 0.8; // Last hour
    } else if (difference.inHours < 6) {
      return 0.5; // Last 6 hours
    } else if (difference.inHours < 24) {
      return 0.2; // Last 24 hours
    } else {
      return 0.1; // Older
    }
  }

  /// Get badge type for a user based on their presence and score
  /// 
  /// Badges (in priority order):
  /// 1. "Top Stimme heute" - Top message sender today (>= 5 messages)
  /// 2. "Beliebt hier" - High score (top 10% in room)
  /// 3. "Heute aktiv" - Has activity today
  /// 
  /// Returns null if no badge applies
  PresenceBadgeType? getBadgeType(
    UserPresence presence,
    double score,
    Map<String, UserPresence> allPresences,
  ) {
    // Only show badges for today's activity
    if (!presence.isToday) return null;
    
    // 1. "Top Stimme heute" - Top message sender (>= 5 messages today)
    if (presence.messageCountToday >= 5) {
      return PresenceBadgeType.topVoice;
    }
    
    // 2. "Beliebt hier" - High score (top 10% in room)
    if (_isTopScorer(score, allPresences)) {
      return PresenceBadgeType.popular;
    }
    
    // 3. "Heute aktiv" - Has activity today
    if (presence.qualifiesForActiveBadge) {
      return PresenceBadgeType.active;
    }
    
    return null;
  }

  /// Check if user is in top 10% of scorers in the room
  bool _isTopScorer(double score, Map<String, UserPresence> allPresences) {
    if (allPresences.isEmpty) return false;
    
    // Calculate scores for all users
    final scores = allPresences.values
        .map((p) => calculateScore(p))
        .toList()
      ..sort((a, b) => b.compareTo(a)); // Descending
    
    if (scores.isEmpty) return false;
    
    // Top 10% threshold (at least top 1 if room is small)
    final thresholdIndex = (scores.length * 0.1).ceil().clamp(1, scores.length);
    final threshold = scores[thresholdIndex - 1];
    
    return score >= threshold && score > 0;
  }

  /// Calculate scores for all users in a room
  Map<String, double> calculateScoresForRoom(Map<String, UserPresence> presences) {
    return {
      for (final entry in presences.entries)
        entry.key: calculateScore(entry.value),
    };
  }
}

/// Badge types for presence
enum PresenceBadgeType {
  active,      // "Heute aktiv"
  topVoice,    // "Top Stimme heute"
  popular,     // "Beliebt hier"
}

/// Extension for badge labels
extension PresenceBadgeTypeExtension on PresenceBadgeType {
  String get label {
    switch (this) {
      case PresenceBadgeType.active:
        return 'Heute aktiv';
      case PresenceBadgeType.topVoice:
        return 'Top Stimme heute';
      case PresenceBadgeType.popular:
        return 'Beliebt hier';
    }
  }
  
  Color get color {
    switch (this) {
      case PresenceBadgeType.active:
        return MingaTheme.accentGreen;
      case PresenceBadgeType.topVoice:
        return MingaTheme.hotOrange;
      case PresenceBadgeType.popular:
        return MingaTheme.warningOrange;
    }
  }
}

