class UserProfile {
  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? email;
  final String? bio;
  final String? badge;

  static String resolveDisplayLabel({
    String? displayName,
    String? username,
  }) {
    final display = displayName?.trim() ?? '';
    if (display.isNotEmpty) return display;
    final user = username?.trim() ?? '';
    if (user.isNotEmpty) return user;
    return 'User';
  }

  UserProfile({
    required this.id,
    String? displayName,
    String? username,
    String? avatarUrl,
    String? name,
    String? avatar,
    this.email,
    this.bio,
    this.badge,
  })  : displayName = resolveDisplayLabel(
          displayName: displayName ?? name,
          username: username,
        ),
        username = (username ?? '').trim(),
        avatarUrl = (avatarUrl ?? avatar);

  @Deprecated('Use displayName')
  String get name => displayName;

  @Deprecated('Use avatarUrl')
  String? get avatar => avatarUrl;

  String get displayLabel => resolveDisplayLabel(
        displayName: displayName,
        username: username,
      );

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final displayName = json['display_name'] as String?;
    final username = json['username'] as String?;
    return UserProfile(
      id: json['id'] as String,
      displayName: displayName,
      username: username,
      avatarUrl: json['avatar_url'] as String?,
      email: json['email'] as String?,
      bio: json['bio'] as String?,
      badge: json['badge'] as String? ?? json['badge_label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'username': username,
      'avatar_url': avatarUrl,
      'email': email,
      'bio': bio,
      'badge': badge,
    };
  }
}

