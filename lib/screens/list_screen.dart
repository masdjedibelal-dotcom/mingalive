import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import 'detail_screen.dart';
import '../widgets/activity_badge.dart';
import '../widgets/place_image.dart';
import '../widgets/place_distance_text.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_card.dart' as glass;
import '../widgets/glass/glass_chip.dart';

/// Screen showing places filtered by category or search term
class ListScreen extends StatefulWidget {
  final String? categoryName;
  final String? searchTerm;
  final String kind;
  final void Function(String placeId) openPlaceChat;
  
  const ListScreen({
    super.key,
    this.categoryName,
    this.searchTerm,
    required this.kind,
    required this.openPlaceChat,
  }) : assert(
          categoryName != null || searchTerm != null,
          'Either categoryName or searchTerm must be provided',
        );

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final PlaceRepository _repository = PlaceRepository();
  // Cached futures - created once in initState
  Future<List<Place>>? _placesFuture;
  bool _isDistanceSorting = false;
  bool get _isEventCategory =>
      (widget.categoryName ?? '').trim().toUpperCase() == 'EVENTS';

  /// Phase 1: Load places only (immediate, no blocking)
  Future<List<Place>> _loadPlaces() async {
    if (mounted) {
      setState(() {
        _isDistanceSorting = true;
      });
    }
    List<Place> places;
    final activeKind =
        widget.kind.trim().isEmpty ? 'all' : widget.kind.trim();
    if (widget.categoryName != null) {
      places = await _repository.fetchByCategory(
        category: widget.categoryName!,
        kind: activeKind == 'all' ? '' : activeKind,
      );
    } else if (widget.searchTerm != null) {
      places = await _repository.search(
        query: widget.searchTerm!,
        kind: activeKind == 'all' ? null : activeKind,
      );
    } else {
      return [];
    }

    if (kDebugMode) {
      debugPrint(
        '🟣 ListScreen: activeKind=$activeKind category=${widget.categoryName} search=${widget.searchTerm} count=${places.length}',
      );
    }

    // Base order (secondary for null distances)
    places.sort((a, b) => a.name.compareTo(b.name));
    final sorted = _sortPlacesByDistanceOnce(places);
    if (mounted) {
      setState(() {
        _isDistanceSorting = false;
      });
    }
    return sorted;
  }

  /// Sort places by distance asc (nulls last). If both distances are null,
  /// keep existing order (pre-sorted by name).
  List<Place> _sortPlacesByDistanceOnce(List<Place> places) {
    final indexed = places.asMap().entries.toList();
    indexed.sort((a, b) {
      final distanceA = a.value.distanceKm;
      final distanceB = b.value.distanceKm;
      final aMissing = distanceA == null;
      final bMissing = distanceB == null;
      if (aMissing && bMissing) {
        return a.key.compareTo(b.key);
      }
      if (aMissing) return 1;
      if (bMissing) return -1;
      final distanceComparison = distanceA.compareTo(distanceB);
      if (distanceComparison != 0) return distanceComparison;
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList();
  }

  @override
  void initState() {
    super.initState();
    // Phase 1: Load places (cached future, called exactly once)
    _placesFuture = _loadPlaces();
    
    _placesFuture!.then((places) {
      if (!mounted || places.isEmpty) {
        return;
      }
    });
  }

  @override
  void didUpdateWidget(ListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload if category or search term changed
    if (oldWidget.categoryName != widget.categoryName ||
        oldWidget.searchTerm != widget.searchTerm ||
        oldWidget.kind != widget.kind) {
      // Reset state
      // Create new futures
      setState(() {
        _isDistanceSorting = true;
      });
      _placesFuture = _loadPlaces();
      _placesFuture!.then((places) {
        if (!mounted || places.isEmpty) {
          return;
        }
      });
    }
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
          widget.categoryName ?? 'Ergebnisse',
          style: MingaTheme.titleMedium,
        ),
      ),
      body: Column(
        children: [
          // Subtitle for search mode
          if (widget.searchTerm != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Für: ${widget.searchTerm}',
                style: MingaTheme.textMuted.copyWith(fontSize: 14),
              ),
            ),
          // Places list with FutureBuilder
          Expanded(
            child: FutureBuilder<List<Place>>(
              future: _placesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildSkeletonList();
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: MingaTheme.textSubtle,
                          ),
                          SizedBox(height: 24),
                          Text(
                            'Fehler beim Laden',
                            style: MingaTheme.titleSmall,
                          ),
                          SizedBox(height: 16),
                          Text(
                            snapshot.error.toString(),
                            style: MingaTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                final places = snapshot.data ?? [];
                
                if (places.isEmpty) {
                  return _buildEmptyState();
                }

                return Column(
                  children: [
                    SizedBox(
                      height: 28,
                      child: _isDistanceSorting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: MingaTheme.accentGreen,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Sortiere nach Entfernung…',
                                  style: MingaTheme.textMuted,
                                ),
                              ],
                            )
                          : SizedBox.shrink(),
                    ),
                    // Places list - render immediately from snapshot.data
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        itemCount: places.length,
                        itemBuilder: (context, index) {
                          final place = places[index];
                          return _buildResultCard(context: context, place: place);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return _buildSkeletonCard();
      },
    );
  }

  Widget _buildSkeletonCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassSurface(
        radius: 20,
        blurSigma: 18,
        overlayColor: MingaTheme.glassOverlayXSoft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Skeleton Bild
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: MingaTheme.skeletonFill,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                ),
              ),
              SizedBox(width: 16),
              // Skeleton Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 20,
                      width: double.infinity,
                      decoration: BoxDecoration(
                      color: MingaTheme.skeletonFill,
                      borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      height: 16,
                      width: 120,
                      decoration: BoxDecoration(
                      color: MingaTheme.skeletonFill,
                      borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required BuildContext context,
    required Place place,
  }) {
    final isEvent = _isEventPlace(place);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: glass.GlassCard(
        variant: glass.GlassCardVariant.glass,
        glow: isEvent,
        padding: const EdgeInsets.all(16),
        child: Material(
          color: MingaTheme.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(MingaTheme.cardRadius),
            onTap: () {
              final placeId = place.id;
              debugPrint('📄 List tap -> placeId=$placeId (pushing detail)');
              // Navigate to DetailScreen
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DetailScreen(
                    place: place,
                    placeId: placeId,
                    openPlaceChat: widget.openPlaceChat,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEvent) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildLabelPill('Event', MingaTheme.hotOrange),
                        _buildTimePill(place),
                        if (place.liveCount > 0 || place.isLive)
                          _buildLabelPill('Live', MingaTheme.accentGreen),
                      ],
                    ),
                    SizedBox(height: 10),
                  ] else ...[
                    SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quadratisches Bild
                      PlaceImage(
                        imageUrl: place.imageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        borderRadius: context.radius.sm,
                      ),
                      SizedBox(width: 16),
                      // Name, Entfernung und Live-Indikator
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    place.name,
                                    style: MingaTheme.titleSmall.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (place.distanceKm != null ||
                                    _isDistanceSorting)
                                  Row(
                                    children: [
                                      if (_isDistanceSorting)
                                        SizedBox(
                                          width: context.space.s12,
                                          height: context.space.s12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.colors.textMuted,
                                          ),
                                        ),
                                      if (_isDistanceSorting &&
                                          place.distanceKm != null)
                                        SizedBox(width: context.space.s4),
                                      PlaceDistanceText(
                                        distanceKm: place.distanceKm,
                                        style: MingaTheme.textMuted.copyWith(
                                          color: MingaTheme.textSubtle,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ActivityBadge(
                                  label: isEvent
                                      ? _getEventActivityLabel(place)
                                      : _getActivityLabel(place),
                                  color: isEvent
                                      ? _getEventActivityColor(place)
                                      : _getActivityColor(place),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                // Show live count if > 0
                                if (place.liveCount > 0) ...[
                                  SizedBox(width: 12),
                                  Text(
                                    "${place.liveCount} live",
                                    style: MingaTheme.textMuted.copyWith(
                                      color: MingaTheme.accentGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                // Show last active time if available
                                if (place.lastActiveAt != null &&
                                    place.liveCount == 0) ...[
                                  SizedBox(width: 12),
                                  Text(
                                    _formatLastActive(place.lastActiveAt!),
                                    style: MingaTheme.textMuted,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final exampleSearches = [
      'ramen',
      'biergarten',
      'kaffee',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isEventCategory ? Icons.event_busy : Icons.search_off,
              size: 64,
              color: MingaTheme.textSubtle,
            ),
            SizedBox(height: 24),
            Text(
              _isEventCategory
                  ? 'Heute keine Events in deiner Nähe'
                  : 'Keine Ergebnisse gefunden',
              style: MingaTheme.titleSmall,
            ),
            SizedBox(height: 16),
            Text(
              _isEventCategory
                  ? 'Schau später nochmal vorbei oder ändere den Ort.'
                  : 'Versuch es mit einer dieser Suchen:',
              style: MingaTheme.textMuted.copyWith(fontSize: 14),
            ),
            if (!_isEventCategory) ...[
              SizedBox(height: 24),
              ...exampleSearches.map((search) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: glass.GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Text(
                        search,
                        style: MingaTheme.titleSmall.copyWith(fontSize: 15),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  /// Format last active time as "aktiv vor X Min/Std/Tag"
  String _formatLastActive(DateTime lastActiveAt) {
    final now = DateTime.now();
    final difference = now.difference(lastActiveAt);
    
    if (difference.inMinutes < 1) {
      return 'gerade aktiv';
    } else if (difference.inMinutes < 60) {
      return 'aktiv vor ${difference.inMinutes} Min';
    } else if (difference.inHours < 24) {
      return 'aktiv vor ${difference.inHours} Std';
    } else if (difference.inDays < 7) {
      return 'aktiv vor ${difference.inDays} Tag${difference.inDays > 1 ? 'en' : ''}';
    } else {
      return 'aktiv vor ${(difference.inDays / 7).floor()} Woche${(difference.inDays / 7).floor() > 1 ? 'n' : ''}';
    }
  }

  String _getActivityLabel(Place place) {
    if (place.isLive || place.liveCount > 0) {
      return 'Aktiv';
    }
    final lastActiveAt = place.lastActiveAt;
    if (lastActiveAt != null && _repository.getActivityRank(place) > 0) {
      return 'Heute aktiv';
    }
    return 'Ruhig';
  }

  Color _getActivityColor(Place place) {
    if (place.isLive || place.liveCount > 0) {
      return MingaTheme.accentGreen;
    }
    final lastActiveAt = place.lastActiveAt;
    if (lastActiveAt != null && _repository.getActivityRank(place) > 0) {
      return MingaTheme.warningOrange;
    }
    return MingaTheme.textSecondary;
  }

  bool _isEventPlace(Place place) {
    final category = place.category.trim().toUpperCase();
    return category == 'EVENTS' || place.id.startsWith('event_');
  }

  String _getEventActivityLabel(Place place) {
    if (place.isLive || place.liveCount > 0) return 'Live';
    final time = _eventTimeLabel(place);
    return time.isNotEmpty ? time : 'Heute';
  }

  Color _getEventActivityColor(Place place) {
    if (place.isLive || place.liveCount > 0) return MingaTheme.accentGreen;
    final time = _eventTimeLabel(place).toLowerCase();
    if (time.contains('morgen')) return MingaTheme.infoBlue;
    return MingaTheme.hotOrange;
  }

  Widget _buildLabelPill(String label, Color color, {bool muted = false}) {
    return GlassChip(
      label: label,
      selected: !muted,
      onTap: null,
    );
  }

  Widget _buildTimePill(Place place) {
    final label = _eventTimeLabel(place);
    if (label.isEmpty) return SizedBox.shrink();
    final color = label.toLowerCase().contains('morgen')
        ? MingaTheme.infoBlue
        : MingaTheme.hotOrange;
    return _buildLabelPill(label, color);
  }

  String _eventTimeLabel(Place place) {
    final status = place.shortStatus.toLowerCase();
    if (status.contains('morgen')) return 'Morgen';
    if (status.contains('heute')) return 'Heute';
    if (status.contains('gleich') || status.contains('in ')) {
      return 'Heute';
    }
    return '';
  }
}
