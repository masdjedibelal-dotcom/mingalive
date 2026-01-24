import 'package:flutter/material.dart';
import '../data/event_repository.dart';
import '../models/event.dart';
import '../widgets/glass/glass_surface.dart';
import 'theme.dart';

class EventListScreen extends StatefulWidget {
  final String? categoryName;
  final String? searchTerm;

  const EventListScreen({
    super.key,
    this.categoryName,
    this.searchTerm,
  }) : assert(
          categoryName != null || searchTerm != null,
          'Either categoryName or searchTerm must be provided',
        );

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final EventRepository _repository = EventRepository();
  Future<List<Event>>? _eventsFuture;
  List<String> _categories = [];
  bool _isLoadingCategories = false;
  String? _activeCategory;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.categoryName;
    _eventsFuture = _loadEvents();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant EventListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryName != widget.categoryName ||
        oldWidget.searchTerm != widget.searchTerm) {
      _activeCategory = widget.categoryName;
      _eventsFuture = _loadEvents();
      _loadCategories();
      setState(() {});
    }
  }

  Future<List<Event>> _loadEvents() async {
    final category = _activeCategory ?? widget.categoryName;
    return _repository.fetchUpcomingEvents(
      category: category,
      searchTerm: widget.searchTerm,
    );
  }

  Future<void> _loadCategories() async {
    if (widget.categoryName == null) return;
    setState(() {
      _isLoadingCategories = true;
    });
    final categories = await _repository.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _isLoadingCategories = false;
    });
  }

  void _onCategoryTap(String category) {
    if (_activeCategory == category) return;
    setState(() {
      _activeCategory = category;
      _eventsFuture = _loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MingaTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _activeCategory ?? widget.categoryName ?? 'Events',
          style: MingaTheme.titleMedium,
        ),
      ),
      body: Column(
        children: [
          if (widget.searchTerm != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Für: ${widget.searchTerm}',
                style: MingaTheme.textMuted.copyWith(fontSize: 14),
              ),
            ),
          if (widget.categoryName != null)
            SizedBox(
              height: 40,
              child: _isLoadingCategories
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 18),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = category == _activeCategory;
                        return GestureDetector(
                          onTap: () => _onCategoryTap(category),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                category,
                                style: MingaTheme.body.copyWith(
                                  color: isSelected
                                      ? MingaTheme.textPrimary
                                      : MingaTheme.textSubtle,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 2,
                                width: isSelected ? 24 : 0,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? MingaTheme.accentGreen
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          Expanded(
            child: FutureBuilder<List<Event>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: MingaTheme.accentGreen,
                    ),
                  );
                }
                final events = snapshot.data ?? [];
                if (events.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _EventListCard(event: events[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 64,
            color: MingaTheme.textSubtle,
          ),
          const SizedBox(height: 24),
          Text(
            'Keine Events gefunden',
            style: MingaTheme.titleSmall.copyWith(
              color: MingaTheme.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventListCard extends StatelessWidget {
  final Event event;

  const _EventListCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateText = _formatEventDate(event);
    final venueText = _formatVenue(event);
    return GlassSurface(
      radius: MingaTheme.cardRadius,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlay,
      boxShadow: MingaTheme.cardShadow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MingaTheme.glassOverlaySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.event,
                color: MingaTheme.accentGreen,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: MingaTheme.titleSmall.copyWith(fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateText,
                    style: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSecondary,
                    ),
                  ),
                  if (venueText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      venueText,
                      style: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEventDate(Event event) {
    final dateTime = event.effectiveStart;
    if (dateTime == null) return 'Datum folgt';
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final time = event.startTime?.trim();
    if (time != null && time.isNotEmpty) {
      final hhmm = time.length >= 5 ? time.substring(0, 5) : time;
      return '$day.$month.$year · $hhmm';
    }
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year · $hour:$minute';
  }

  String _formatVenue(Event event) {
    final venue = event.venueName?.trim();
    if (venue != null && venue.isNotEmpty) return venue;
    final venueId = event.venueId?.trim();
    if (venueId != null && venueId.isNotEmpty) return venueId;
    return '';
  }
}

