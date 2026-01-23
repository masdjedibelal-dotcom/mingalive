import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import 'detail_screen.dart';
import '../widgets/place_image.dart';
import '../widgets/place_distance_text.dart';
import '../theme/app_theme_extensions.dart';

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
  List<String> _categories = [];
  bool _isLoadingCategories = false;
  String? _activeCategory;
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
    final category = _activeCategory ?? widget.categoryName;
    if (category != null) {
      places = await _repository.fetchByCategory(
        category: category,
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
    _activeCategory = widget.categoryName;
    // Phase 1: Load places (cached future, called exactly once)
    _placesFuture = _loadPlaces();
    _loadCategories();
    
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
      _activeCategory = widget.categoryName;
      // Reset state
      // Create new futures
      setState(() {
        _isDistanceSorting = true;
      });
      _placesFuture = _loadPlaces();
      _loadCategories();
      _placesFuture!.then((places) {
        if (!mounted || places.isEmpty) {
          return;
        }
      });
    }
  }

  Future<void> _loadCategories() async {
    if (widget.categoryName == null) return;
    setState(() {
      _isLoadingCategories = true;
    });
    try {
      final activeKind =
          widget.kind.trim().isEmpty ? 'all' : widget.kind.trim();
      final categories = await _repository.fetchTopCategories(
        kind: activeKind == 'all' ? '' : activeKind,
        limit: 1000,
      );
      final sorted = List<String>.from(categories)
        ..sort((a, b) => a.compareTo(b));
      if (!mounted) return;
      setState(() {
        _categories = sorted;
        _isLoadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _isLoadingCategories = false;
      });
    }
  }

  void _onCategoryTap(String category) {
    if (_activeCategory == category) return;
    setState(() {
      _activeCategory = category;
      _isDistanceSorting = true;
    });
    _placesFuture = _loadPlaces();
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
          _activeCategory ?? widget.categoryName ?? 'Ergebnisse',
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
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : FontWeight.w500,
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
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        itemCount: places.length,
                        separatorBuilder: (_, __) => Divider(
                          color: MingaTheme.borderSubtle,
                          height: 24,
                        ),
                        itemBuilder: (context, index) {
                          final place = places[index];
                          return _buildResultRow(context: context, place: place);
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: 6,
      separatorBuilder: (_, __) => Divider(
        color: MingaTheme.borderSubtle,
        height: 24,
      ),
      itemBuilder: (context, index) {
        return _buildSkeletonRow();
      },
    );
  }

  Widget _buildSkeletonRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: MingaTheme.skeletonFill,
            borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 18,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: MingaTheme.skeletonFill,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                ),
              ),
              SizedBox(height: 10),
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: MingaTheme.skeletonFill,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                ),
              ),
              SizedBox(height: 8),
              Container(
                height: 12,
                width: 160,
                decoration: BoxDecoration(
                  color: MingaTheme.skeletonFill,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow({
    required BuildContext context,
    required Place place,
  }) {
    final detailRoute = MaterialPageRoute(
      builder: (context) => DetailScreen(
        place: place,
        placeId: place.id,
        openPlaceChat: widget.openPlaceChat,
      ),
    );
    return Material(
      color: MingaTheme.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(detailRoute),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaceImage(
              imageUrl: place.imageUrl,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              borderRadius: context.radius.sm,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: MingaTheme.titleSmall.copyWith(fontSize: 16),
                  ),
                  SizedBox(height: 6),
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
                      if (_isDistanceSorting && place.distanceKm != null)
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
                  SizedBox(height: 6),
                  Text(
                    _buildMetaLine(place),
                    style: MingaTheme.textMuted.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: MingaTheme.surface,
                        borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
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

  String _buildMetaLine(Place place) {
    final parts = <String>[];
    if (place.category.trim().isNotEmpty) {
      parts.add(place.category);
    }
    if (place.kind != null && place.kind!.trim().isNotEmpty) {
      parts.add(place.kind!.trim());
    }
    if (_isEventPlace(place)) {
      final time = _eventTimeLabel(place);
      if (time.isNotEmpty) {
        parts.add(time);
      } else {
        parts.add('Event');
      }
    }
    if (parts.isEmpty && place.shortStatus.trim().isNotEmpty) {
      parts.add(place.shortStatus.trim());
    }
    return parts.join(' • ');
  }

  bool _isEventPlace(Place place) {
    final category = place.category.trim().toUpperCase();
    return category == 'EVENTS' || place.id.startsWith('event_');
  }

  // Event chips removed; use meta line instead.

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
