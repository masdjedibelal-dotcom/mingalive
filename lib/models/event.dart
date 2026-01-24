class Event {
  final String id;
  final String title;
  final String description;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final String? startDate;
  final String? startTime;
  final String? venueName;
  final String? venueId;
  final String? category;
  final String? sourceUrl;
  final bool isPublic;
  final bool isCancelled;

  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.startDateTime,
    required this.endDateTime,
    required this.startDate,
    required this.startTime,
    required this.venueName,
    required this.venueId,
    required this.category,
    required this.sourceUrl,
    required this.isPublic,
    required this.isCancelled,
  });

  factory Event.fromSupabase(Map<String, dynamic> json) {
    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final parsed = DateTime.tryParse(value.toString());
      return parsed;
    }

    final startDateTime = parseDateTime(json['start_datetime']);
    final endDateTime = parseDateTime(json['end_datetime']);
    final startDate = json['start_date']?.toString();
    final startTime = json['start_time']?.toString();
    final fallbackStart = _parseFallbackStart(startDate, startTime);

    return Event(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      startDateTime: startDateTime ?? fallbackStart,
      endDateTime: endDateTime,
      startDate: startDate,
      startTime: startTime,
      venueName: json['venue_name']?.toString(),
      venueId: json['venue_id']?.toString(),
      category: json['category']?.toString(),
      sourceUrl: json['source_url']?.toString(),
      isPublic: json['is_public'] == true,
      isCancelled: json['is_cancelled'] == true,
    );
  }

  DateTime? get effectiveStart => startDateTime;

  DateTime? get effectiveEnd => endDateTime ?? startDateTime;

  bool isExpired(DateTime now) {
    final end = effectiveEnd;
    if (end == null) return false;
    return end.isBefore(now);
  }

  static DateTime? _parseFallbackStart(String? date, String? time) {
    if (date == null || date.trim().isEmpty) return null;
    final datePart = date.trim();
    final timePart =
        (time == null || time.trim().isEmpty) ? '00:00:00' : time.trim();
    return DateTime.tryParse('${datePart}T${timePart}');
  }
}

