/// Chat message model
class ChatMessage {
  final String id;
  final String roomId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String text;
  final String? mediaUrl; // Optional media URL (image/video)
  final DateTime createdAt;
  final bool isMine;
  final int reactionsCount;
  final String? currentUserReaction;
  final Map<String, int> reactionCounts;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.text,
    this.mediaUrl,
    required this.createdAt,
    required this.isMine,
    this.reactionsCount = 0,
    this.currentUserReaction,
    this.reactionCounts = const {},
  });

  /// Create ChatMessage from Supabase JSON row
  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      userAvatar: json['user_avatar'] as String?,
      text: json['text'] as String,
      mediaUrl: json['media_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      isMine: currentUserId != null && json['user_id'] == currentUserId,
      reactionsCount: (json['reactions_count'] as num?)?.toInt() ?? 0,
      currentUserReaction: json['current_user_reaction'] as String?,
      reactionCounts: _parseReactionCounts(json['reaction_counts']),
    );
  }

  /// Convert ChatMessage to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'user_id': userId,
      'user_name': userName,
      'user_avatar': userAvatar,
      'text': text,
      if (mediaUrl != null) 'media_url': mediaUrl,
      'reactions_count': reactionsCount,
      if (currentUserReaction != null)
        'current_user_reaction': currentUserReaction,
      if (reactionCounts.isNotEmpty) 'reaction_counts': reactionCounts,
    };
  }

  /// Check if message was created today
  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    return messageDate == today;
  }

  static Map<String, int> _parseReactionCounts(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num?)?.toInt() ?? 0,
        ),
      );
    }
    return {};
  }
}


