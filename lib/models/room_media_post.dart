/// Room media post model
/// 
/// Represents a media post (image/video) in a chat room.
/// Media posts are separate from text messages.
class RoomMediaPost {
  final String id;
  final String roomId;
  final String userId;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final DateTime createdAt;
  final int reactionsCount;
  final String? currentUserReaction;
  final Map<String, int> reactionCounts;

  const RoomMediaPost({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    this.reactionsCount = 0,
    this.currentUserReaction,
    this.reactionCounts = const {},
  });

  /// Create RoomMediaPost from Supabase JSON row
  factory RoomMediaPost.fromJson(Map<String, dynamic> json) {
    return RoomMediaPost(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      mediaUrl: json['media_url'] as String,
      mediaType: json['media_type'] as String? ?? 'image',
      createdAt: DateTime.parse(json['created_at'] as String),
      reactionsCount: (json['reactions_count'] as num?)?.toInt() ?? 0,
      currentUserReaction: json['current_user_reaction'] as String?,
      reactionCounts: _parseReactionCounts(json['reaction_counts']),
    );
  }

  /// Convert RoomMediaPost to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'user_id': userId,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'created_at': createdAt.toIso8601String(),
      'reactions_count': reactionsCount,
      if (currentUserReaction != null)
        'current_user_reaction': currentUserReaction,
      if (reactionCounts.isNotEmpty) 'reaction_counts': reactionCounts,
    };
  }

  static Map<String, int> _parseReactionCounts(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0));
    }
    return {};
  }

  /// Check if post was created today
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final postDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    return postDate == today;
  }
}










