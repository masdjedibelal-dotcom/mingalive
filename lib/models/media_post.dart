/// Media post model for stream-only media
/// 
/// Represents a media post (image/video) in a stream.
/// Separate from room_media_posts (chat room media).
class MediaPost {
  final String id;
  final String roomId;
  final String mediaUrl;
  final DateTime createdAt;
  final int reactionsCount;
  final String? currentUserReaction; // Current user's reaction emoji (if any)

  const MediaPost({
    required this.id,
    required this.roomId,
    required this.mediaUrl,
    required this.createdAt,
    required this.reactionsCount,
    this.currentUserReaction,
  });

  /// Create MediaPost from Supabase JSON row
  factory MediaPost.fromJson(Map<String, dynamic> json) {
    return MediaPost(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      mediaUrl: json['media_url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      reactionsCount: (json['reactions_count'] as num?)?.toInt() ?? 0,
      currentUserReaction: json['current_user_reaction'] as String?,
    );
  }

  /// Convert MediaPost to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'media_url': mediaUrl,
      'created_at': createdAt.toIso8601String(),
      'reactions_count': reactionsCount,
    };
  }
}


