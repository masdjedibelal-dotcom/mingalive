/// Reaction model for user reactions on media posts or messages
class Reaction {
  final String id;
  final String targetId; // media_post_id or message_id
  final String userId;
  final String emoji; // e.g., '🔥', '❤️', '😂', '👀'
  final DateTime createdAt;

  const Reaction({
    required this.id,
    required this.targetId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      id: json['id'] as String,
      targetId: json['media_post_id'] as String? ?? json['message_id'] as String? ?? '',
      userId: json['user_id'] as String,
      emoji: json['reaction'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_post_id': targetId,
      'user_id': userId,
      'reaction': emoji,
      'created_at': createdAt.toIso8601String(),
    };
  }
}


























