import 'package:flutter/material.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../services/search_router.dart';
import '../services/gpt_search_suggestions_service.dart';
import 'detail_screen.dart';
import 'event_list_screen.dart';
import 'list_screen.dart';
import 'main_shell.dart';
import 'trip_plan_screen.dart';
import '../screens/categories_screen.dart';
import '../widgets/glass/glass_card.dart';

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

  @override
  void initState() {
    super.initState();
    _activeKind = widget.kind.trim().isEmpty ? 'food' : widget.kind.trim();
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
        if (action.categoryName == 'EVENTS' || _activeKind == 'events') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => EventListScreen(
                categoryName: action.categoryName == 'EVENTS'
                    ? action.categoryName
                    : null,
                searchTerm: action.searchTerm,
              ),
            ),
          );
        } else {
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
        }
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
                  ],
                ),
              ),
            ),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: TabBarView(
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

