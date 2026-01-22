import 'package:flutter/material.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import '../services/search_router.dart';
import '../services/gpt_search_suggestions_service.dart';
import '../services/supabase_gate.dart';
import 'detail_screen.dart';
import 'list_screen.dart';
import 'main_shell.dart';
import 'trip_plan_screen.dart';
import '../screens/categories_screen.dart';
import '../widgets/glass/glass_card.dart';
import '../widgets/glass/glass_chip.dart';

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

class _UseCaseRule {
  final String title;
  final String query;
  final List<String> keywords;
  final bool isTopSpots;

  const _UseCaseRule({
    required this.title,
    required this.query,
    required this.keywords,
    this.isTopSpots = false,
  });
}

class _UseCaseSuggestion {
  final String title;
  final String query;
  final List<Place> places;

  const _UseCaseSuggestion({
    required this.title,
    required this.query,
    required this.places,
  });
}

class _SearchEntryScreenState extends State<SearchEntryScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final PlaceRepository _repository = PlaceRepository();
  late final SearchRouter _router = SearchRouter(_repository);
  late final GptSearchSuggestionsService _gptService =
      GptSearchSuggestionsService(_repository);
  bool _isSearching = false;
  String? _assistantText;
  late String _activeKind;
  late final TabController _tabController;
  late final List<String> _kinds;
  bool _isLoadingGpt = false;
  List<GptSearchSuggestion> _gptSuggestions = const [];
  bool _isLoadingUseCases = false;
  List<_UseCaseSuggestion> _useCaseSuggestions = const [];

  @override
  void initState() {
    super.initState();
    _activeKind = widget.kind.trim().isEmpty ? 'food' : widget.kind.trim();
    _kinds = const ['food', 'sight'];
    final initialIndex =
        _kinds.indexOf(_activeKind).clamp(0, _kinds.length - 1);
    _tabController = TabController(length: _kinds.length, vsync: this);
    _tabController.index = initialIndex;
    _tabController.addListener(_handleTabChanged);
    _loadGptSuggestions();
    _loadUseCaseSuggestions();
    _applyInitialQuery();
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
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

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _assistantText = null;
    });
    try {
      final action = await _router.handle(query);
      if (!mounted) return;
      setState(() {
        _assistantText = action.assistantText;
        _isSearching = false;
      });
      await _executeSearchAction(action);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assistantText = 'Probier es mit einem Ort, einer Stimmung oder Kategorie.';
        _isSearching = false;
      });
    }
  }

  Future<void> _executeSearchAction(SearchAction action) async {
    switch (action.type) {
      case SearchActionType.openList:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ListScreen(
              categoryName: action.categoryName,
              searchTerm: action.searchTerm,
              kind: _activeKind,
              openPlaceChat: widget.openPlaceChat,
            ),
          ),
        );
        break;
      case SearchActionType.openStream:
        MainShell.of(context)?.switchToTab(1);
        break;
      case SearchActionType.openDetail:
        if (action.placeId != null) {
          final place = _repository.getById(action.placeId!);
          if (place != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DetailScreen(
                  place: place,
                  openPlaceChat: widget.openPlaceChat,
                ),
              ),
            );
          }
        }
        break;
      case SearchActionType.openChat:
        if (action.placeId != null) {
          widget.openPlaceChat(action.placeId!);
        }
        break;
      case SearchActionType.planTrip:
        if (action.trip != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TripPlanScreen(
                trip: action.trip!,
                assistantText: action.assistantText,
              ),
            ),
          );
        }
        break;
      case SearchActionType.answerOnly:
        _showAnswerBottomSheet(action.assistantText);
        break;
    }
  }

  void _showAnswerBottomSheet(String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MingaTheme.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: GlassSurface(
          radius: 20,
          blurSigma: 18,
          overlayColor: MingaTheme.glassOverlay,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Antwort', style: MingaTheme.titleSmall),
                SizedBox(height: 16),
                Text(
                  text,
                  style: MingaTheme.body.copyWith(height: 1.5),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final kind = _kinds[_tabController.index];
    if (_activeKind == kind) return;
    setState(() {
      _activeKind = kind;
    });
    _loadGptSuggestions();
    _loadUseCaseSuggestions();
  }

  Future<void> _loadGptSuggestions() async {
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

  Future<void> _loadUseCaseSuggestions() async {
    setState(() {
      _isLoadingUseCases = true;
    });
    final places = await _fetchUseCasePlaces();
    if (!mounted) return;
    final suggestions = _buildUseCaseSuggestions(places);
    setState(() {
      _useCaseSuggestions = suggestions;
      _isLoadingUseCases = false;
    });
  }

  Future<List<Place>> _fetchUseCasePlaces() async {
    if (SupabaseGate.isEnabled) {
      try {
        final remote =
            await _repository.fetchPlacesPage(offset: 0, limit: 200);
        if (remote.isNotEmpty) {
          return remote;
        }
      } catch (_) {}
    }
    return _repository.getAllPlaces();
  }

  List<_UseCaseSuggestion> _buildUseCaseSuggestions(List<Place> places) {
    final filtered = places
        .where((place) =>
            _activeKind.isEmpty ||
            place.kind == _activeKind ||
            place.kind == null)
        .toList();
    final rules = const [
      _UseCaseRule(
        title: 'Pizza',
        query: 'Pizza',
        keywords: ['pizza'],
      ),
      _UseCaseRule(
        title: 'Ramen',
        query: 'Ramen',
        keywords: ['ramen'],
      ),
      _UseCaseRule(
        title: 'Biergarten',
        query: 'Biergarten',
        keywords: ['biergarten', 'beer', 'brau'],
      ),
      _UseCaseRule(
        title: 'Parks',
        query: 'Parks',
        keywords: ['park', 'garten'],
      ),
      _UseCaseRule(
        title: 'Seen',
        query: 'Seen',
        keywords: ['see', 'lake'],
      ),
      _UseCaseRule(
        title: 'Was trinken gehen',
        query: 'Drinks',
        keywords: ['bar', 'cocktail', 'drinks', 'pub'],
      ),
      _UseCaseRule(
        title: 'Party',
        query: 'Party',
        keywords: ['club', 'party', 'night'],
      ),
      _UseCaseRule(
        title: 'Top Spots',
        query: 'Top Spots',
        keywords: [],
        isTopSpots: true,
      ),
    ];

    final suggestions = <_UseCaseSuggestion>[];
    for (final rule in rules) {
      final matches = rule.isTopSpots
          ? filtered
          : filtered.where((place) => _matchesRule(place, rule)).toList();
      if (matches.isEmpty) continue;
      matches.sort(_comparePlaces);
      suggestions.add(
        _UseCaseSuggestion(
          title: rule.title,
          query: rule.query,
          places: matches.take(3).toList(),
        ),
      );
    }

    return suggestions;
  }

  bool _matchesRule(Place place, _UseCaseRule rule) {
    if (rule.keywords.isEmpty) return true;
    final haystack = [
      place.name,
      place.category,
      ...place.tags,
    ].map((value) => value.toLowerCase()).toList();
    for (final keyword in rule.keywords) {
      final lower = keyword.toLowerCase();
      if (haystack.any((value) => value.contains(lower))) {
        return true;
      }
    }
    return false;
  }

  int _comparePlaces(Place a, Place b) {
    final ratingCountCompare = b.ratingCount.compareTo(a.ratingCount);
    if (ratingCountCompare != 0) return ratingCountCompare;
    final ratingCompare = b.rating.compareTo(a.rating);
    if (ratingCompare != 0) return ratingCompare;
    final distanceA = a.distanceKm ?? double.infinity;
    final distanceB = b.distanceKm ?? double.infinity;
    return distanceA.compareTo(distanceB);
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
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
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
                    if (_isSearching)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: MingaTheme.textSecondary,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Suche läuft…', style: MingaTheme.bodySmall),
                          ],
                        ),
                      ),
                    if (_assistantText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _assistantText!,
                          style: MingaTheme.bodySmall,
                        ),
                      ),
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
                                  _runSearch(suggestion.query);
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
                    Text(
                      'Use‑Cases',
                      style: MingaTheme.label,
                    ),
                    SizedBox(height: 10),
                    if (_isLoadingUseCases)
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
                    else if (_useCaseSuggestions.isNotEmpty)
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _useCaseSuggestions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final suggestion = _useCaseSuggestions[index];
                            return GestureDetector(
                              onTap: () => _runSearch(suggestion.query),
                              child: GlassChip(
                                label: suggestion.title,
                                selected: false,
                              ),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchTabBarDelegate(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: GlassSurface(
                    radius: MingaTheme.pillRadius,
                    blurSigma: 16,
                    overlayColor: MingaTheme.glassOverlayXSoft,
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: MingaTheme.accentGreen,
                      labelColor: MingaTheme.textPrimary,
                      unselectedLabelColor: MingaTheme.textSubtle,
                      tabs: const [
                        Tab(text: 'Essen & Trinken'),
                        Tab(text: 'Places'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: TabBarView(
            controller: _tabController,
            children: const [
              CategoriesView(kind: 'food', showSearchField: false),
              CategoriesView(kind: 'sight', showSearchField: false),
            ],
          ),
        ),
      ),
    );
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

