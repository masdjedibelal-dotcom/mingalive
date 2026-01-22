/// Model representing a place/location in Munich
/// 
/// Core fields: id, name, imageUrl, category, chatRoomId
/// chatRoomId is deterministic: "place_<id>" (or custom if provided)
/// chatRoomId is never null - always defaults to 'place_<id>' if not provided
class Place {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final double? distanceKm;
  final double rating;
  final int ratingCount;
  final bool socialEnabled;
  final bool isLive;
  final int liveCount;
  final int favoritesCount;
  final String shortStatus;
  final List<String> chatPreview;
  final List<String> tags;
  
  // Supabase fields (optional for backward compatibility)
  final double? lat;
  final double? lng;
  final String? kind;
  
  // Extended fields (optional)
  final String? address;
  final String? website; // Website URL
  final String? websiteUrl; // Alias for website (for consistency)
  final String? phone;
  final String? instagram; // Instagram handle/URL
  final String? instagramUrl; // Alias for instagram (for consistency)
  final String? status; // e.g., "open", "closed"
  final String? price; // e.g., "€€", "€€€"
  final Map<String, dynamic>? openingHoursJson; // Opening hours as Map (from JSON)
  final DateTime? lastActiveAt; // Last activity timestamp from chat_rooms
  
  /// Get website URL (websiteUrl or website)
  String? get websiteUrlOrWebsite => websiteUrl ?? website;
  
  /// Get Instagram URL (instagramUrl or instagram)
  String? get instagramUrlOrInstagram => instagramUrl ?? instagram;
  
  /// Get Google Maps URL from lat/lng
  String? get mapsUrl {
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    return null;
  }
  
  /// Deterministic chat room ID: always "place_<id>" or custom if provided
  /// Never null - guaranteed by constructor
  final String chatRoomId;

  /// Computed room ID for chat: always "place_<id>"
  /// This is the room ID used in SupabaseChatRepository
  String get roomId => 'place_$id';

  @Deprecated('Use ratingCount instead.')
  int get reviewCount => ratingCount;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    this.distanceKm,
    required this.rating,
    required this.ratingCount,
    required this.isLive,
    required this.liveCount,
    this.favoritesCount = 0,
    required this.shortStatus,
    required this.chatPreview,
    this.tags = const [],
    this.lat,
    this.lng,
    this.kind,
    this.address,
    this.website,
    this.websiteUrl,
    this.phone,
    this.instagram,
    this.instagramUrl,
    this.status,
    this.price,
    this.openingHoursJson,
    this.lastActiveAt,
    String? chatRoomId,
  })  : socialEnabled = ratingCount > 1500,
        chatRoomId = chatRoomId ?? 'place_$id';

  /// Create Place from Supabase row
  /// 
  /// Maps Supabase columns:
  /// - id -> id
  /// - name -> name
  /// - category -> category
  /// - rating -> rating
  /// - review_count -> ratingCount
  /// - img_url -> imageUrl
  /// - lat/latitude -> lat
  /// - lng/lon/longitude -> lng
  /// - kind -> kind
  /// - address -> address
  /// - website -> website
  /// - phone -> phone
  /// - status -> status
  /// - price -> price
  /// - opening_hours_json -> openingHoursJson
  /// 
  /// Defaults for missing fields:
  /// - distanceKm: null (computed client-side when user location is available)
  /// - isLive: false
  /// - liveCount: 0
  /// - shortStatus: empty string
  /// - chatPreview: empty list
  factory Place.fromSupabase(Map<String, dynamic> row) {
    final lat = _readCoordinate(row, const ['lat', 'latitude']);
    final lng = _readCoordinate(row, const ['lng', 'lon', 'longitude']);
    return Place(
      id: row['id'] as String,
      name: row['name'] as String,
      category: row['category'] as String,
      imageUrl: row['img_url'] as String? ?? '',
      distanceKm: null, // Computed client-side when user location is available
      rating: _parseDouble(row['rating']) ?? 0.0,
      ratingCount: _parseInt(row['review_count']) ??
          _parseInt(row['reviewCount']) ??
          0,
      isLive: false, // Can be determined from presence or other logic
      liveCount: 0, // Can be fetched from presence
      favoritesCount: (row['favorites_count'] as num?)?.toInt() ?? 0,
      shortStatus: '',
      chatPreview: [],
      lat: lat,
      lng: lng,
      kind: row['kind'] as String?,
      address: row['address'] as String?,
      website: row['website'] as String?,
      websiteUrl: row['website_url'] as String? ?? row['website'] as String?,
      phone: row['phone'] as String?,
      instagram: row['instagram'] as String?,
      instagramUrl: row['instagram_url'] as String? ?? row['instagram'] as String?,
      status: row['status'] as String?,
      price: row['price'] as String?,
      openingHoursJson: row['opening_hours_json'] != null
          ? (row['opening_hours_json'] is Map
              ? Map<String, dynamic>.from(row['opening_hours_json'] as Map)
              : null)
          : null,
      lastActiveAt: row['last_active_at'] != null
          ? DateTime.parse(row['last_active_at'] as String)
          : null,
    );
  }

  /// Create Place from generic map
  factory Place.fromMap(Map<String, dynamic> map) {
    return Place.fromSupabase(map);
  }

  /// Create Place from JSON map
  factory Place.fromJson(Map<String, dynamic> json) {
    return Place.fromSupabase(json);
  }

  @override
  String toString() {
    return 'Place(id: $id, name: $name, category: $category, liveCount: $liveCount, favoritesCount: $favoritesCount)';
  }

  static double? _readCoordinate(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (!row.containsKey(key)) continue;
      final parsed = _parseDouble(row[key]);
      if (parsed != null && parsed.isFinite) {
        return parsed;
      }
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Place copyWith({
    int? favoritesCount,
    int? ratingCount,
    double? distanceKm,
    bool clearDistanceKm = false,
  }) {
    return Place(
      id: id,
      name: name,
      category: category,
      imageUrl: imageUrl,
      distanceKm: clearDistanceKm ? null : (distanceKm ?? this.distanceKm),
      rating: rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isLive: isLive,
      liveCount: liveCount,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      shortStatus: shortStatus,
      chatPreview: chatPreview,
      tags: tags,
      lat: lat,
      lng: lng,
      kind: kind,
      address: address,
      website: website,
      websiteUrl: websiteUrl,
      phone: phone,
      instagram: instagram,
      instagramUrl: instagramUrl,
      status: status,
      price: price,
      openingHoursJson: openingHoursJson,
      lastActiveAt: lastActiveAt,
      chatRoomId: chatRoomId,
    );
  }
}
