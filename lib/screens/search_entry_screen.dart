import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../data/event_repository.dart';
import '../models/event.dart';
import '../models/place.dart';
import '../services/gpt_search_suggestions_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'detail_screen.dart';
import '../screens/categories_screen.dart';
import '../widgets/glass/glass_card.dart';
import '../widgets/glass/glass_text_field.dart';
import '../widgets/add_to_collab_sheet.dart';
import '../widgets/place_image.dart';
import '../utils/geo.dart';
import '../utils/bottom_nav_padding.dart';

class SearchEntryScreen extends StatefulWidget {
  final String kind;
  final void Function(String placeId) openPlaceChat;
  final String? initialQuery;
  final VoidCallback? onClose;

  const SearchEntryScreen({
    super.key,
    required this.kind,
    required this.openPlaceChat,
    this.initialQuery,
    this.onClose,
  });

  @override
  State<SearchEntryScreen> createState() => _SearchEntryScreenState();
}

class _SearchEntryScreenState extends State<SearchEntryScreen>
    with SingleTickerProviderStateMixin {
  final EventRepository _eventRepository = EventRepository();
  final TextEditingController _controller = TextEditingController();
  final PlaceRepository _repository = PlaceRepository();
  final LocationService _locationService = LocationService();
  late final GptSearchSuggestionsService _gptService =
      GptSearchSuggestionsService(_repository);
  late String _activeKind;
  late final TabController _tabController;
  late final List<String> _kinds;
  bool _isLoadingGpt = false;
  List<GptSearchSuggestion> _gptSuggestions = const [];
  Timer? _searchDebounce;
  bool _isQuerying = false;
  List<Place> _queryResults = const [];
  List<Event> _eventResults = const [];
  String _lastQuery = '';
  final Map<String, bool> _favoriteByPlaceId = {};
  final Map<String, bool> _favoriteLoadingByPlaceId = {};
  _SearchMode _searchMode = _SearchMode.places;
  _PlaceSort _placeSort = _PlaceSort.relevance;
  bool _filterOpenNow = false;
  bool _filterNear = false;
  final double _nearKm = 2.0;
  _EventFilter _eventFilter = _EventFilter.all;
  _EventSort _eventSort = _EventSort.date;

  @override
  void initState() {
    super.initState();
    _activeKind = widget.kind.trim().isEmpty ? 'food' : widget.kind.trim();
    _searchMode =
        _activeKind == 'events' ? _SearchMode.events : _SearchMode.places;
    _kinds = const ['food', 'sight', 'events'];
    final initialIndex =
        _kinds.indexOf(_activeKind).clamp(0, _kinds.length - 1);
    _tabController = TabController(length: _kinds.length, vsync: this);
    _tabController.index = initialIndex;
    _tabController.addListener(_handleTabChanged);
    _loadGptSuggestions();
    _applyInitialQuery();
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _applyInitialQuery() {
    final query = widget.initialQuery?.trim();
    if (query == null || query.isEmpty) return;
    _controller.text = query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _runSearch(query);
      }
    });
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _queryResults = const [];
        _eventResults = const [];
        _isQuerying = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty || query == _lastQuery) return;
    _lastQuery = query;
    setState(() {
      _isQuerying = true;
    });
    try {
      if (_searchMode == _SearchMode.events) {
        final results = await _eventRepository.searchFutureEvents(query: query);
        if (!mounted) return;
        setState(() {
          _eventResults = results;
          _queryResults = const [];
          _isQuerying = false;
        });
        return;
      }
      final kind = _activeKind == 'events' ? null : _activeKind;
      final results = await _repository.search(query: query, kind: kind);
      final withDistances = await _withDistances(results);
      if (!mounted) return;
      setState(() {
        _queryResults = withDistances;
        _eventResults = const [];
        _isQuerying = false;
      });
      _prefetchFavorites(results);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _queryResults = const [];
        _eventResults = const [];
        _isQuerying = false;
      });
    }
  }

  Future<List<Place>> _withDistances(List<Place> places) async {
    if (places.isEmpty) return places;
    try {
      final origin = await _locationService.getOriginOrFallback();
      return places.map((place) {
        if (place.lat == null || place.lng == null) return place;
        final distance = haversineDistanceKm(
          origin.lat,
          origin.lng,
          place.lat!,
          place.lng!,
        );
        return place.copyWith(distanceKm: distance);
      }).toList();
    } catch (_) {
      return places;
    }
  }

  Future<void> _prefetchFavorites(List<Place> places) async {
    final user = AuthService.instance.currentUser;
    if (user == null || places.isEmpty) {
      if (!mounted) return;
      setState(() {
        _favoriteByPlaceId.clear();
        _favoriteLoadingByPlaceId.clear();
      });
      return;
    }
    for (final place in places) {
      if (_favoriteByPlaceId.containsKey(place.id) ||
          _favoriteLoadingByPlaceId[place.id] == true) {
        continue;
      }
      _loadFavoriteStatus(place, user.id);
    }
  }

  Future<void> _loadFavoriteStatus(Place place, String userId) async {
    setState(() {
      _favoriteLoadingByPlaceId[place.id] = true;
    });
    final isFav = await _repository.isFavorite(
      placeId: place.id,
      userId: userId,
    );
    if (!mounted) return;
    setState(() {
      _favoriteByPlaceId[place.id] = isFav;
      _favoriteLoadingByPlaceId[place.id] = false;
    });
  }

  Future<void> _toggleFavorite(Place place) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte einloggen, um Favoriten zu speichern.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_favoriteLoadingByPlaceId[place.id] == true) return;
    setState(() {
      _favoriteLoadingByPlaceId[place.id] = true;
    });
    final isSaved = _favoriteByPlaceId[place.id] ?? false;
    try {
      if (isSaved) {
        await _repository.removeFavorite(placeId: place.id, userId: user.id);
      } else {
        await _repository.addFavorite(placeId: place.id, userId: user.id);
      }
      if (!mounted) return;
      setState(() {
        _favoriteByPlaceId[place.id] = !isSaved;
        _favoriteLoadingByPlaceId[place.id] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteLoadingByPlaceId[place.id] = false;
      });
    }
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final kind = _kinds[_tabController.index];
    if (_activeKind == kind) return;
    setState(() {
      _activeKind = kind;
    });
    _loadGptSuggestions();
  }

  Future<void> _loadGptSuggestions() async {
    if (_activeKind == 'events') {
      setState(() {
        _gptSuggestions = const [];
        _isLoadingGpt = false;
      });
      return;
    }
    setState(() {
      _isLoadingGpt = true;
    });
    final suggestions = await _gptService.fetchSuggestions(kind: _activeKind);
    if (!mounted) return;
    setState(() {
      _gptSuggestions = suggestions;
      _isLoadingGpt = false;
    });
  }
  // Use-cases intentionally removed; only "Vorschläge" remain.

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        title: Text('Suche', style: MingaTheme.titleMedium),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasQuery) ...[
                      GlassTextField(
                        controller: _controller,
                        hintText:
                            'Suche nach Titel, Kategorie, Straße…',
                        textInputAction: TextInputAction.search,
                        prefixIcon: Icon(
                          Icons.search,
                          color: MingaTheme.textSubtle,
                        ),
                        suffixIcon: _controller.text.trim().isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  _onQueryChanged('');
                                },
                                icon: Icon(
                                  Icons.close,
                                  color: MingaTheme.textSubtle,
                                ),
                              ),
                        onChanged: (value) {
                          setState(() {});
                          _onQueryChanged(value);
                        },
                        onSubmitted: _runSearch,
                      ),
                      SizedBox(height: 16),
                    ],
                    if (!hasQuery) ...[
                      SizedBox(height: 16),
                      Text(
                        'Vorschläge',
                        style: MingaTheme.label,
                      ),
                      SizedBox(height: 10),
                      if (_isLoadingGpt)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                            height: 26,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: MingaTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else if (_gptSuggestions.isNotEmpty)
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 6),
                            itemCount: _gptSuggestions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final suggestion = _gptSuggestions[index];
                              return SizedBox(
                                width: 220,
                                child: GestureDetector(
                                  onTap: () {
                                    _controller.text = suggestion.query;
                                    _onQueryChanged(suggestion.query);
                                  },
                                  child: GlassCard(
                                    variant: GlassCardVariant.glass,
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          suggestion.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: MingaTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          suggestion.reason,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: MingaTheme.bodySmall.copyWith(
                                            color: MingaTheme.textSecondary,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          suggestion.query,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: MingaTheme.label.copyWith(
                                            color: MingaTheme.textSubtle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            if (hasQuery)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchStickyHeaderDelegate(
                  height: 140,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      children: [
                        GlassTextField(
                          controller: _controller,
                          hintText:
                              'Suche nach Titel, Kategorie, Straße…',
                          textInputAction: TextInputAction.search,
                          prefixIcon: Icon(
                            Icons.search,
                            color: MingaTheme.textSubtle,
                          ),
                          suffixIcon: _controller.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _controller.clear();
                                    _onQueryChanged('');
                                  },
                                  icon: Icon(
                                    Icons.close,
                                    color: MingaTheme.textSubtle,
                                  ),
                                ),
                          onChanged: (value) {
                            setState(() {});
                            _onQueryChanged(value);
                          },
                          onSubmitted: _runSearch,
                        ),
                        const SizedBox(height: 10),
                        _buildSearchModeToggle(),
                        const SizedBox(height: 10),
                        _buildFilterRow(),
                      ],
                    ),
                  ),
                ),
              ),
            if (!hasQuery)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchTabBarDelegate(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.only(right: 18),
                      tabAlignment: TabAlignment.start,
                      indicator: UnderlineTabIndicator(
                        borderSide: BorderSide(
                          color: MingaTheme.accentGreen,
                          width: 2,
                        ),
                        insets: const EdgeInsets.only(bottom: 2),
                      ),
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: MingaTheme.textPrimary,
                      unselectedLabelColor: MingaTheme.textSubtle,
                      labelStyle: MingaTheme.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: MingaTheme.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Essen & Trinken'),
                        Tab(text: 'Places'),
                        Tab(text: 'Events'),
                      ],
                    ),
                  ),
                ),
              ),
          ];
        },
        body: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 0,
          ),
          child: hasQuery
              ? _buildSearchResults()
              : TabBarView(
                  controller: _tabController,
                  children: const [
                    CategoriesView(kind: 'food', showSearchField: false),
                    CategoriesView(kind: 'sight', showSearchField: false),
                    EventsCategoriesView(showSearchField: false),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isQuerying) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: MingaTheme.accentGreen,
        ),
      );
    }
    if (_searchMode == _SearchMode.events) {
      final filtered = _applyEventFilters(_eventResults);
      if (filtered.isEmpty) {
        return Center(
          child: Text(
            'Keine Events gefunden.',
            style: MingaTheme.bodySmall.copyWith(
              color: MingaTheme.textSubtle,
            ),
          ),
        );
      }
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(
          0,
          12,
          0,
          bottomNavSafePadding(context),
        ),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => Divider(
          color: MingaTheme.borderSubtle,
          height: 20,
        ),
        itemBuilder: (context, index) {
          final event = filtered[index];
          return _EventResultTile(event: event);
        },
      );
    }
    final filteredPlaces = _applyPlaceFilters(_queryResults);
    if (filteredPlaces.isEmpty) {
      return Center(
        child: Text(
          'Keine Ergebnisse gefunden.',
          style: MingaTheme.bodySmall.copyWith(
            color: MingaTheme.textSubtle,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        0,
        12,
        0,
        bottomNavSafePadding(context),
      ),
      itemCount: filteredPlaces.length,
      separatorBuilder: (_, __) => Divider(
        color: MingaTheme.borderSubtle,
        height: 20,
      ),
      itemBuilder: (context, index) {
        final place = filteredPlaces[index];
        return _SearchResultTile(
          place: place,
          isSaved: _favoriteByPlaceId[place.id] ?? false,
          isSaving: _favoriteLoadingByPlaceId[place.id] ?? false,
          onFavoriteTap: () => _toggleFavorite(place),
          onAddToCollab: () => showAddToCollabSheet(
            context: context,
            place: place,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DetailScreen(
                  place: place,
                  openPlaceChat: widget.openPlaceChat,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchModeToggle() {
    return Row(
      children: [
        Expanded(
          child: _SearchModeButton(
            label: 'Places',
            isActive: _searchMode == _SearchMode.places,
            onTap: () {
              if (_searchMode == _SearchMode.places) return;
              setState(() {
                _searchMode = _SearchMode.places;
              });
              _runSearch(_controller.text.trim());
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SearchModeButton(
            label: 'Events',
            isActive: _searchMode == _SearchMode.events,
            onTap: () {
              if (_searchMode == _SearchMode.events) return;
              setState(() {
                _searchMode = _SearchMode.events;
              });
              _runSearch(_controller.text.trim());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    if (_searchMode == _SearchMode.events) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SearchFilterChip(
            label: 'Alle',
            isActive: _eventFilter == _EventFilter.all,
            onTap: () {
              setState(() {
                _eventFilter = _EventFilter.all;
              });
            },
          ),
          _SearchFilterChip(
            label: 'Heute',
            isActive: _eventFilter == _EventFilter.today,
            onTap: () {
              setState(() {
                _eventFilter = _EventFilter.today;
              });
            },
          ),
          _SearchFilterChip(
            label: 'Diese Woche',
            isActive: _eventFilter == _EventFilter.week,
            onTap: () {
              setState(() {
                _eventFilter = _EventFilter.week;
              });
            },
          ),
          _SearchFilterChip(
            label: 'Datum',
            isActive: _eventSort == _EventSort.date,
            onTap: () {
              setState(() {
                _eventSort = _EventSort.date;
              });
            },
          ),
          _SearchFilterChip(
            label: 'Titel',
            isActive: _eventSort == _EventSort.title,
            onTap: () {
              setState(() {
                _eventSort = _EventSort.title;
              });
            },
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SearchFilterChip(
          label: 'Relevanz',
          isActive: _placeSort == _PlaceSort.relevance,
          onTap: () {
            setState(() {
              _placeSort = _PlaceSort.relevance;
            });
          },
        ),
        _SearchFilterChip(
          label: 'Nähe',
          isActive: _placeSort == _PlaceSort.distance,
          onTap: () {
            setState(() {
              _placeSort = _PlaceSort.distance;
            });
          },
        ),
        _SearchFilterChip(
          label: 'Bewertung',
          isActive: _placeSort == _PlaceSort.rating,
          onTap: () {
            setState(() {
              _placeSort = _PlaceSort.rating;
            });
          },
        ),
        _SearchFilterChip(
          label: 'Jetzt offen',
          isActive: _filterOpenNow,
          onTap: () {
            setState(() {
              _filterOpenNow = !_filterOpenNow;
            });
          },
        ),
        _SearchFilterChip(
          label: '≤ ${_nearKm.toStringAsFixed(0)} km',
          isActive: _filterNear,
          onTap: () {
            setState(() {
              _filterNear = !_filterNear;
            });
          },
        ),
      ],
    );
  }

  List<Place> _applyPlaceFilters(List<Place> input) {
    var result = List<Place>.from(input);
    if (_filterOpenNow) {
      result = result.where(_isOpenNow).toList();
    }
    if (_filterNear) {
      result = result
          .where((place) =>
              place.distanceKm != null && place.distanceKm! <= _nearKm)
          .toList();
    }
    if (_placeSort == _PlaceSort.distance) {
      result.sort((a, b) {
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        final compare = da.compareTo(db);
        if (compare != 0) return compare;
        return b.ratingCount.compareTo(a.ratingCount);
      });
    } else if (_placeSort == _PlaceSort.rating) {
      result.sort((a, b) {
        final compare = b.ratingCount.compareTo(a.ratingCount);
        if (compare != 0) return compare;
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        return da.compareTo(db);
      });
    }
    return result;
  }

  bool _isOpenNow(Place place) {
    final openNow = place.openingHoursJson?['open_now'];
    if (openNow is bool) return openNow;
    final status = place.status?.toLowerCase() ?? '';
    if (status.contains('geschlossen') || status.contains('closed')) {
      return false;
    }
    if (status.contains('geöffnet') ||
        status.contains('open') ||
        status.contains('rund um die uhr')) {
      return true;
    }
    return false;
  }

  List<Event> _applyEventFilters(List<Event> input) {
    var result = List<Event>.from(input);
    final now = DateTime.now();
    if (_eventFilter == _EventFilter.today) {
      result = result.where((event) {
        final start = event.effectiveStart;
        if (start == null) return false;
        final local = start.toLocal();
        return local.year == now.year &&
            local.month == now.month &&
            local.day == now.day;
      }).toList();
    } else if (_eventFilter == _EventFilter.week) {
      final startOfDay = DateTime(now.year, now.month, now.day);
      final end = startOfDay.add(const Duration(days: 7));
      result = result.where((event) {
        final start = event.effectiveStart;
        if (start == null) return false;
        final local = start.toLocal();
        return local.isAfter(startOfDay) && local.isBefore(end);
      }).toList();
    }
    if (_eventSort == _EventSort.title) {
      result.sort((a, b) => a.title.compareTo(b.title));
    } else {
      result.sort((a, b) {
        final aStart = a.effectiveStart;
        final bStart = b.effectiveStart;
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
    }
    return result;
  }
}

enum _SearchMode { places, events }
enum _PlaceSort { relevance, distance, rating }
enum _EventFilter { all, today, week }
enum _EventSort { date, title }

class _SearchModeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SearchModeButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: 14,
        blurSigma: 14,
        overlayColor: isActive
            ? MingaTheme.glassOverlayStrong
            : MingaTheme.glassOverlaySoft,
        borderColor:
            isActive ? MingaTheme.accentGreenBorder : MingaTheme.borderSubtle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: MingaTheme.body.copyWith(
                color: isActive
                    ? MingaTheme.accentGreen
                    : MingaTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SearchFilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: 14,
        blurSigma: 12,
        overlayColor: isActive
            ? MingaTheme.glassOverlayStrong
            : MingaTheme.glassOverlaySoft,
        borderColor:
            isActive ? MingaTheme.accentGreenBorder : MingaTheme.borderSubtle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: MingaTheme.bodySmall.copyWith(
              color: isActive
                  ? MingaTheme.accentGreen
                  : MingaTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Place place;
  final bool isSaved;
  final bool isSaving;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onAddToCollab;

  const _SearchResultTile({
    required this.place,
    required this.isSaved,
    required this.isSaving,
    required this.onTap,
    required this.onFavoriteTap,
    required this.onAddToCollab,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MingaTheme.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              PlaceImage(
                imageUrl: place.imageUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MingaTheme.titleSmall.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildMeta(place),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onAddToCollab,
                    icon: Icon(
                      Icons.playlist_add,
                      color: MingaTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    onPressed: isSaving ? null : onFavoriteTap,
                    icon: Icon(
                      isSaved ? Icons.favorite : Icons.favorite_border,
                      color: isSaved
                          ? MingaTheme.accentGreen
                          : MingaTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMeta(Place place) {
    final parts = <String>[];
    if (place.category.trim().isNotEmpty) {
      parts.add(place.category.trim());
    }
    final address = place.address?.trim();
    if (address != null && address.isNotEmpty) {
      parts.add(address);
    }
    return parts.join(' · ');
  }
}

class _EventResultTile extends StatelessWidget {
  final Event event;

  const _EventResultTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final dateText = _formatDate(event.effectiveStart, event.startDate);
    final timeText = _formatTime(context);
    final venue = event.venueName?.trim() ?? '';
    final subtitleParts = <String>[
      dateText,
      if (timeText != null && timeText.isNotEmpty) timeText,
      if (venue.isNotEmpty) venue,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MingaTheme.titleSmall.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            subtitleParts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MingaTheme.bodySmall.copyWith(
              color: MingaTheme.textSubtle,
            ),
          ),
          if (event.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              event.description.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? dateTime, String? fallbackDate) {
    if (dateTime != null) {
      final local = dateTime.toLocal();
      final day = local.day.toString().padLeft(2, '0');
      final month = local.month.toString().padLeft(2, '0');
      final year = local.year.toString();
      return '$day.$month.$year';
    }
    final trimmed = fallbackDate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Datum folgt';
  }

  String? _formatTime(BuildContext context) {
    final raw = event.startTime?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final hh = parts[0].padLeft(2, '0');
      final mm = parts[1].padLeft(2, '0');
      return '$hh:$mm';
    }
    return raw;
  }
}


class _SearchTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _SearchTabBarDelegate({required this.child});

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: MingaTheme.background,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SearchTabBarDelegate oldDelegate) {
    return false;
  }
}

class _SearchStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  const _SearchStickyHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: MingaTheme.background,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SearchStickyHeaderDelegate oldDelegate) {
    return false;
  }
}

