class CollabQuery {
  final List<String> includeCategories;
  final List<String> excludeCategories;
  final bool onlySocialEnabled;
  final String sort;
  final int minReviewCount;

  const CollabQuery({
    this.includeCategories = const [],
    this.excludeCategories = const [],
    this.onlySocialEnabled = false,
    this.sort = 'reviewCount',
    this.minReviewCount = 0,
  });
}

class CreatorLabelResolver {
  static String resolve({
    String? displayName,
    String? username,
  }) {
    final display = _sanitize(displayName);
    if (display.isNotEmpty) return display;
    final user = _sanitize(username);
    if (user.isNotEmpty) return user;
    return 'User';
  }

  static String _sanitize(String? value) {
    final normalized = value?.trim() ?? '';
    final lower = normalized.toLowerCase();
    if (lower.isEmpty ||
        lower == 'user' ||
        lower == 'unknown' ||
        lower.contains('unbekannt')) {
      return '';
    }
    return normalized;
  }
}

class CollabDefinition {
  final String id;
  final String title;
  final String subtitle;
  final String creatorId;
  final String creatorName;
  final String? creatorAvatarUrl;
  final String heroType; // "image" | "gradient"
  final String? heroImageUrl;
  final String? gradientKey;
  final CollabQuery query;
  final int limit;

  const CollabDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.creatorId,
    required this.creatorName,
    this.creatorAvatarUrl,
    required this.heroType,
    this.heroImageUrl,
    this.gradientKey,
    required this.query,
    this.limit = 30,
  });
}

class CollabMediaItem {
  final String id;
  final String collabId;
  final String userId;
  final String kind; // 'image' | 'video'
  final String storagePath;
  final String publicUrl;
  final int sortOrder;
  final DateTime createdAt;

  const CollabMediaItem({
    required this.id,
    required this.collabId,
    required this.userId,
    required this.kind,
    required this.storagePath,
    required this.publicUrl,
    required this.sortOrder,
    required this.createdAt,
  });

  factory CollabMediaItem.fromJson(Map<String, dynamic> json) {
    return CollabMediaItem(
      id: json['id'] as String,
      collabId: json['collab_id'] as String,
      userId: json['user_id'] as String,
      kind: json['kind'] as String? ?? 'image',
      storagePath: json['storage_path'] as String? ?? '',
      publicUrl: json['public_url'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

extension CollabMediaItemList on List<CollabMediaItem> {
  List<CollabMediaItem> limitedForCarousel() {
    if (length <= 5) return this;
    return take(5).toList();
  }
}

