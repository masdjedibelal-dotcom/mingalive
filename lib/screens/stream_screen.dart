import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme_extensions.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import '../models/chat_message.dart';
import '../models/room_media_post.dart';
import '../models/user_presence.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_message_tile.dart';
import '../widgets/media_card.dart';
import '../widgets/add_to_collab_sheet.dart';
import '../widgets/glass/glass_badge.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';
import '../services/chat_repository.dart';
import '../services/supabase_chat_repository.dart';
import '../services/supabase_gate.dart';
import '../services/auth_service.dart';
import 'main_shell.dart';
import '../state/location_store.dart';
import '../models/app_location.dart';
import '../utils/distance_utils.dart';

/// Chat-first Twitch-style stream screen
/// 
/// Can be opened in two modes:
/// 1. Default: Shows all places in PageView (swipeable)
/// 2. With place/roomId: Shows specific place directly
class StreamScreen extends StatefulWidget {
  final String? activeRoomId;
  final String? activePlaceId;

  const StreamScreen({
    super.key,
    this.activeRoomId,
    this.activePlaceId,
  });

  @override
  State<StreamScreen> createState() => StreamScreenState();
}

class StreamScreenState extends State<StreamScreen>
    with WidgetsBindingObserver {
  static const int POOL_FETCH_LIMIT = 400;
  static const double MAX_DISTANCE_KM = 20;
  static const int VISIBLE_PAGE_SIZE = 20;
  static const int VISIBLE_PREFETCH_THRESHOLD = 5;
  final PageController _pageController = PageController();
  final PlaceRepository _repository = PlaceRepository();
  final LocationStore _locationStore = LocationStore();
  List<Place> _poolPlaces = [];
  List<Place> _sortedPlaces = [];
  int _visibleCount = 0;
  int _poolOffset = 0;
  bool _isLoadingPool = false;
  bool _hasMorePool = true;
  bool _isLoading = true;
  bool _isSorting = false;
  final Map<String, bool> _favoriteByPlaceId = {};
  final Map<String, bool> _favoriteLoadingByPlaceId = {};
  Timer? _favoritePrefetchTimer;
  String? _activeRoomId;
  String? _activePlaceId;
  bool _loadFailed = false;
  bool _isSingleRoomMode = false;
  bool _wasVisible = true;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _activeRoomId = widget.activeRoomId;
    _activePlaceId = widget.activePlaceId;
    debugPrint('🟢 StreamScreen activePlaceId=${widget.activePlaceId} activeRoomId=${widget.activeRoomId}');

    _locationStore.addListener(_handleLocationUpdate);
    _locationStore.init();
    _syncUserLocation(_locationStore.currentLocation, force: true);

    _loadFeedPlaces().then((_) async {
      if (widget.activePlaceId != null && widget.activePlaceId!.isNotEmpty) {
        await jumpToPlace(widget.activePlaceId!);
        return;
      }
      if (widget.activeRoomId != null && widget.activeRoomId!.startsWith('place_')) {
        final placeId = widget.activeRoomId!.substring('place_'.length);
        if (placeId.isNotEmpty) {
          await jumpToPlace(placeId);
        }
      }
    });
    // Listen to page changes to load messages for visible page
    _pageController.addListener(_onPageChanged);
  }

  @override
  void didUpdateWidget(covariant StreamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('🟢 StreamScreen activePlaceId=${widget.activePlaceId} activeRoomId=${widget.activeRoomId}');
    _activeRoomId = widget.activeRoomId;
    if (widget.activePlaceId != oldWidget.activePlaceId) {
      _activePlaceId = widget.activePlaceId;
      if (_activePlaceId != null && _activePlaceId!.isNotEmpty) {
        jumpToPlace(_activePlaceId!);
      }
    }
  }

  Future<void> jumpToPlace(String placeId) async {
    if (_sortedPlaces.isEmpty) {
      await _loadFeedPlaces();
    }
    if (!mounted) return;

    if (_sortedPlaces.isEmpty) {
      if (SupabaseGate.isEnabled) {
        final fetched =
            await _repository.fetchById(placeId, allowFallback: false);
        if (fetched != null) {
          await _setSinglePlaceStream(fetched);
        }
      }
      return;
    }

    final index = _sortedPlaces.indexWhere((place) => place.id == placeId);
    debugPrint('🟦 Stream jumpToPlace index=$index placeId=$placeId');
    if (index == -1) {
      debugPrint('🟦 jumpToPlace index=-1 -> fallback to single room mode');
      if (SupabaseGate.isEnabled) {
        final fetched =
            await _repository.fetchById(placeId, allowFallback: false);
        if (fetched != null) {
          await _setSinglePlaceStream(fetched);
        }
      }
      return;
    }

    if (index >= _visibleCount) {
      final nextCount = min(index + 1, _sortedPlaces.length);
      setState(() {
        _visibleCount = nextCount;
      });
    }

    if (!_pageController.hasClients) {
      await _waitForPageController();
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }

    final place = _sortedPlaces[index];
    _prefetchFavorite(place);
    debugPrint('STREAM_JUMPED_ONLY (no subscriptions)');
  }

  Future<void> _waitForPageController() async {
    if (!mounted) return;
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    
    final currentPage = _pageController.page?.round();
    if (currentPage != null && 
        _sortedPlaces.isNotEmpty && 
        currentPage >= 0 && 
        currentPage < _sortedPlaces.length) {
      final place = _sortedPlaces[currentPage];
      final roomId = place.chatRoomId;
      debugPrint(
        'STREAM_ACTIVE_PAGE: index=$currentPage roomId=$roomId placeId=${place.id}',
      );
    }

    _maybeIncreaseVisibleCount(currentPage);
  }

  void _maybeIncreaseVisibleCount(int? currentPage) {
    if (currentPage == null) return;
    if (_visibleCount >= _sortedPlaces.length) return;
    if (currentPage < _visibleCount - VISIBLE_PREFETCH_THRESHOLD) return;
    _increaseVisibleCount();
  }

  void _increaseVisibleCount() {
    if (_visibleCount >= _sortedPlaces.length) return;
    final nextCount =
        min(_visibleCount + VISIBLE_PAGE_SIZE, _sortedPlaces.length);
    if (nextCount == _visibleCount) return;
    setState(() {
      _visibleCount = nextCount;
    });
    debugPrint('VISIBLE count=$_visibleCount');
    if (_visibleCount >= _sortedPlaces.length - VISIBLE_PREFETCH_THRESHOLD) {
      _fetchNextPoolChunk();
    }
  }

  Future<void> _loadFeedPlaces() async {
    debugPrint('🟥 StreamScreen._loadFeedPlaces CALLED');
    await _fetchNextPoolChunk(reset: true);
  }

  Future<void> _fetchNextPoolChunk({bool reset = false}) async {
    if (_isLoadingPool) return;
    if (!reset && !_hasMorePool) return;
    if (mounted) {
      setState(() {
        _isLoadingPool = true;
        if (reset) {
          _isLoading = true;
          _isSorting = false;
          _loadFailed = false;
          _poolPlaces = [];
          _sortedPlaces = [];
          _visibleCount = 0;
          _poolOffset = 0;
          _hasMorePool = true;
        }
      });
    }
    try {
      final newPlaces = await _repository.fetchPlacesPage(
        offset: _poolOffset,
        limit: POOL_FETCH_LIMIT,
      );
      debugPrint(
        'POOL loaded count=${newPlaces.length} offset=$_poolOffset',
      );
      if (newPlaces.isEmpty) {
        _hasMorePool = false;
      } else {
        _poolOffset += POOL_FETCH_LIMIT;
        final byId = <String, Place>{for (final place in _poolPlaces) place.id: place};
        for (final place in newPlaces) {
          byId[place.id] = place;
        }
        _poolPlaces = byId.values.toList();
      }

      if (reset && _hasUserLocation && mounted) {
        setState(() {
          _isSorting = true;
        });
      }
      final sorted = _applyDistanceAndSort(_poolPlaces);
      _logSortTop5(sorted);
      _updateSortedPlaces(sorted, maintainPage: !reset);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingPool = false;
          _isSorting = false;
          _loadFailed = false;
        });
      }

      if (reset) {
        _resetToFirstPage();
        if (_activeRoomId == null && _sortedPlaces.isNotEmpty) {
          _prefetchFavorite(_sortedPlaces.first);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ StreamScreen: Pool fetch failed: $e');
      }
      if (mounted) {
        setState(() {
          _sortedPlaces = [];
          _poolPlaces = [];
          _visibleCount = 0;
          _isLoading = false;
          _isLoadingPool = false;
          _isSorting = false;
          _loadFailed = true;
        });
      }
    }
  }

  String? _currentPlaceId() {
    if (!_pageController.hasClients) return null;
    final index = _pageController.page?.round();
    if (index == null) return null;
    if (index < 0 ||
        index >= _visibleCount ||
        index >= _sortedPlaces.length) {
      return null;
    }
    return _sortedPlaces[index].id;
  }

  void _updateSortedPlaces(
    List<Place> sorted, {
    bool maintainPage = true,
  }) {
    final currentId = maintainPage ? _currentPlaceId() : null;
    if (!mounted) return;
    setState(() {
      _sortedPlaces = sorted;
      if (_visibleCount == 0) {
        _visibleCount = min(VISIBLE_PAGE_SIZE, _sortedPlaces.length);
      } else if (_visibleCount > _sortedPlaces.length) {
        _visibleCount = _sortedPlaces.length;
      }
    });
    debugPrint('VISIBLE count=$_visibleCount');
    if (currentId == null) return;
    final newIndex =
        _sortedPlaces.indexWhere((place) => place.id == currentId);
    if (newIndex == -1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pageController.hasClients) return;
      _pageController.jumpToPage(newIndex);
    });
  }

  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.removeListener(_onPageChanged);
    _favoritePrefetchTimer?.cancel();
    
    _pageController.dispose();
    _locationStore.removeListener(_handleLocationUpdate);
    _locationStore.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Keep current room; refresh only when location changes.
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🟢 StreamScreen activePlaceId=${widget.activePlaceId} activeRoomId=${widget.activeRoomId}');
    final tokens = context.tokens;
    _maybeReloadOnVisibility();
    if (_isLoading) {
      return _buildLoaderScaffold('Places laden…');
    }

    if (_isSorting && _sortedPlaces.isEmpty) {
      return _buildLoaderScaffold('Sortiere nach Nähe…');
    }

    if (_sortedPlaces.isEmpty) {
      return Scaffold(
        backgroundColor: tokens.colors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadFailed
                    ? 'Stream konnte nicht geladen werden.'
                    : 'Keine Live-Orte verfügbar',
                style: tokens.type.body.copyWith(color: tokens.colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.space.s12),
              GlassButton(
                variant: GlassButtonVariant.secondary,
                label: 'Discovery öffnen',
                onPressed: () => MainShell.of(context)?.switchToTab(0),
              ),
            ],
          ),
        ),
      );
    }

    // Default: PageView for multiple places
    final bottomInset = MediaQuery.of(context).padding.bottom + 4;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _visibleCount,
              itemBuilder: (context, index) {
                final place = _sortedPlaces[index];
                return _buildStreamItem(place, index);
              },
            ),
            if (_isLoadingPool && _sortedPlaces.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _buildFooterLoader(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoaderScaffold(String message) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      body: Center(
        child: GlassSurface(
          radius: tokens.radius.lg,
          blur: tokens.blur.med,
          scrim: tokens.card.glassOverlay,
          borderColor: tokens.colors.border,
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.s16,
            vertical: tokens.space.s12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: tokens.space.s16,
                height: tokens.space.s16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.colors.accent,
                ),
              ),
              SizedBox(width: tokens.space.s8),
              Text(
                message,
                style: tokens.type.body.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLoader() {
    final tokens = context.tokens;
    return GlassSurface(
      radius: tokens.radius.md,
      blur: tokens.blur.low,
      scrim: tokens.card.glassOverlay,
      borderColor: tokens.colors.border,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s12,
        vertical: tokens.space.s8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: tokens.space.s12,
            height: tokens.space.s12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.colors.accent,
            ),
          ),
          SizedBox(width: tokens.space.s8),
          Text(
            'Lade mehr…',
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _maybeReloadOnVisibility() {
    final isVisible = TickerMode.of(context);
    if (isVisible == _wasVisible) return;
    _wasVisible = isVisible;
  }

  /// Builds a single stream item with strict layout:
  /// - Top: MediaCard (full-width)
  /// - Below: Chat list (text-only)
  /// - Bottom: Chat input
  Widget _buildStreamItem(Place place, int index) {
    final liveCount = place.liveCount;
    return Column(
      children: [
        // Stream header
        StreamHeader(
          placeName: place.name,
          liveCount: liveCount,
          distanceKm: place.distanceKm,
          isSaved: _favoriteByPlaceId[place.id] ?? false,
          isSaving: _favoriteLoadingByPlaceId[place.id] ?? false,
          onToggleSave: () => _toggleFavorite(place),
          onAddToCollab: () => _openAddToCollab(place),
          showBackButton: _isSingleRoomMode,
          onBack: _isSingleRoomMode ? _exitSingleRoomMode : null,
        ),
        Expanded(
          child: StreamChatPane(
            key: ValueKey('chat_${place.id}'),
            place: place,
            liveCount: liveCount,
          ),
        ),
      ],
    );
  }

  void _prefetchFavorite(Place place) {
    if (_favoriteByPlaceId.containsKey(place.id) ||
        _favoriteLoadingByPlaceId[place.id] == true) {
      return;
    }
    _favoritePrefetchTimer?.cancel();
    _favoritePrefetchTimer = Timer(const Duration(milliseconds: 150), () {
      debugPrint('favoritePrefetch room=${place.chatRoomId}');
      _loadFavoriteStatus(place);
    });
  }

  Future<void> _loadFavoriteStatus(Place place) async {
    final currentUser = AuthService.instance.currentUser;
    if (!SupabaseGate.isEnabled || currentUser == null) {
      if (mounted) {
        setState(() {
          _favoriteByPlaceId[place.id] = false;
        });
      }
      return;
    }

    setState(() {
      _favoriteLoadingByPlaceId[place.id] = true;
    });

    final isFavorite = await _repository.isFavorite(
      placeId: place.id,
      userId: currentUser.id,
    );
    if (!mounted) return;
    setState(() {
      _favoriteByPlaceId[place.id] = isFavorite;
      _favoriteLoadingByPlaceId[place.id] = false;
    });
  }

  Future<void> _toggleFavorite(Place place) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einloggen, um Orte zu speichern.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!SupabaseGate.isEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Favoriten sind nur mit Supabase verfügbar.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final wasFavorite = _favoriteByPlaceId[place.id] ?? false;
    setState(() {
      _favoriteLoadingByPlaceId[place.id] = true;
      _favoriteByPlaceId[place.id] = !wasFavorite;
    });

    try {
      if (wasFavorite) {
        await _repository.removeFavorite(
          placeId: place.id,
          userId: currentUser.id,
        );
      } else {
        await _repository.addFavorite(
          placeId: place.id,
          userId: currentUser.id,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favoriteByPlaceId[place.id] = wasFavorite;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konnte Favorit nicht speichern.'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _favoriteLoadingByPlaceId[place.id] = false;
      });
    }
  }

  void _openAddToCollab(Place place) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einloggen, um Collabs zu nutzen.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    showAddToCollabSheet(context: context, place: place);
  }

  void _handleLocationUpdate() {
    if (!mounted) return;
    if (_isSingleRoomMode) return;
    final location = _locationStore.currentLocation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncUserLocation(location);
    });
  }

  bool get _hasUserLocation => _userLat != null && _userLng != null;

  void _syncUserLocation(AppLocation location, {bool force = false}) {
    final hasLocation = true;
    final nextLat = location.lat;
    final nextLng = location.lng;

    debugPrint(
      'USER_LOC lat=$nextLat lng=$nextLng available=$hasLocation source=${location.source}',
    );

    if (!force && nextLat == _userLat && nextLng == _userLng) return;

    final hadLocation = _hasUserLocation;
    final movedKm = hadLocation
        ? haversineKm(_userLat!, _userLng!, nextLat, nextLng)
        : null;
    final locationChanged =
        force || hadLocation != hasLocation || (movedKm != null && movedKm > 0.15);

    _userLat = nextLat;
    _userLng = nextLng;

    if (!locationChanged) return;
    _resortStreamPlaces();
  }

  void _resortStreamPlaces() {
    if (!mounted) return;
    if (_poolPlaces.isEmpty) return;
    final updated = _applyDistanceAndSort(_poolPlaces);
    _logSortTop5(updated);
    _updateSortedPlaces(updated);
  }

  void _logSortTop5(List<Place> places) {
    final maxLog = places.length < 5 ? places.length : 5;
    for (var i = 0; i < maxLog; i++) {
      final place = places[i];
      debugPrint(
        'SORT top5: ${place.id} | ${place.distanceKm} | ${place.ratingCount}',
      );
    }
    _logExpectedPlacePositions(places);
  }

  void _logExpectedPlacePositions(List<Place> places) {
    const expectedNames = [
      'Marienplatz',
      'Schloss Neuschwanstein',
      'Hofbräuhaus München',
    ];
    for (final name in expectedNames) {
      final exactIndex = places.indexWhere((place) => place.name == name);
      if (exactIndex != -1) {
        debugPrint('SORT position: $name -> index=$exactIndex');
        continue;
      }
      final normalizedName = _normalizeName(name);
      final fuzzyIndex = places.indexWhere(
        (place) => _normalizeName(place.name).contains(normalizedName),
      );
      debugPrint(
        'SORT position: $name -> index=$exactIndex fuzzyIndex=$fuzzyIndex',
      );
    }
  }

  String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Place> _applyDistanceAndSort(List<Place> places) {
    final eligiblePlaces =
        places.where((place) => place.reviewCount >= 3000).toList();
    if (!_hasUserLocation) {
      final cleared = eligiblePlaces
          .map((place) => place.copyWith(clearDistanceKm: true))
          .toList();
      cleared.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
      return cleared;
    }

    final withDistances = eligiblePlaces.map((place) {
      if (place.lat == null || place.lng == null) {
        return place.copyWith(clearDistanceKm: true);
      }
      final distanceKm =
          haversineKm(_userLat!, _userLng!, place.lat!, place.lng!);
      return place.copyWith(distanceKm: distanceKm);
    }).where((place) {
      final distanceKm = place.distanceKm;
      if (distanceKm == null) return false;
      return distanceKm <= MAX_DISTANCE_KM;
    }).toList();

    double score(Place place) {
      final distanceKm = place.distanceKm;
      if (distanceKm == null) return double.negativeInfinity;
      final reviewsScore = place.reviewCount / 1000.0;
      final distancePenalty = (distanceKm * 20) + (distanceKm * distanceKm * 2);
      return reviewsScore - distancePenalty;
    }

    withDistances.sort((a, b) {
      final scoreCompare = score(b).compareTo(score(a));
      if (scoreCompare != 0) return scoreCompare;
      final reviewCompare = b.reviewCount.compareTo(a.reviewCount);
      if (reviewCompare != 0) return reviewCompare;
      return a.name.compareTo(b.name);
    });

    return withDistances;
  }

  Future<void> _setSinglePlaceStream(Place place) async {
    if (!mounted) return;
    setState(() {
      _isSingleRoomMode = true;
      _poolPlaces = [place];
      _sortedPlaces = [place];
      _visibleCount = 1;
      _poolOffset = 0;
      _hasMorePool = false;
      _isLoading = false;
      _loadFailed = false;
    });
    if (!_pageController.hasClients) {
      await _waitForPageController();
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    _prefetchFavorite(place);
  }

  Future<void> _exitSingleRoomMode() async {
    if (!mounted) return;
    setState(() {
      _isSingleRoomMode = false;
      _isLoading = true;
    });
    await _loadFeedPlaces();
  }


  void _resetToFirstPage() {
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      return;
    }
    _pageController.jumpToPage(0);
  }

}

class StreamChatPane extends StatefulWidget {
  final Place place;
  final int liveCount;

  const StreamChatPane({
    super.key,
    required this.place,
    required this.liveCount,
  });

  @override
  State<StreamChatPane> createState() => _StreamChatPaneState();
}

class _StreamChatPaneState extends State<StreamChatPane> {
  late final dynamic _chatRepository;
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  StreamSubscription<List<RoomMediaPost>>? _mediaSubscription;
  StreamSubscription<int>? _presenceSubscription;
  StreamSubscription<List<PresenceProfile>>? _presenceRosterSubscription;
  final ScrollController _chatScrollController = ScrollController();
  List<ChatMessage> _messages = [];
  final List<ChatMessage> _systemMessages = [];
  List<RoomMediaPost> _mediaPosts = [];
  bool _isReactingToMessage = false;
  final Map<String, UserPresence> _userPresences = {};
  Timer? _reactionRefreshTimer;
  int _presenceCount = 0;
  List<PresenceProfile> _presenceRoster = [];

  @override
  void initState() {
    super.initState();
    if (SupabaseGate.isEnabled) {
      _chatRepository = SupabaseChatRepository();
    } else {
      _chatRepository = ChatRepository();
    }
    final roomId = widget.place.chatRoomId;
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      Future.microtask(() {
        supabaseRepo.ensureRoomExists(roomId, widget.place.id);
      });
      _messagesSubscription =
          supabaseRepo.watchMessages(roomId, limit: 50).listen((messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
          });
          _rebuildUserPresences();
          _scheduleReactionRefresh(messages);
        }
      });
      _mediaSubscription = supabaseRepo
          .watchRoomMediaPosts(roomId, limit: ROOM_MEDIA_LIMIT)
          .listen((posts) {
        if (mounted) {
          setState(() {
            _mediaPosts = posts;
          });
          _rebuildUserPresences();
        }
      });
      _presenceSubscription =
          supabaseRepo.watchPresenceCount(roomId).listen((count) {
        if (mounted) {
          setState(() {
            _presenceCount = count;
          });
        }
      });
      _presenceRosterSubscription =
          supabaseRepo.watchPresenceRoster(roomId).listen((roster) {
        if (mounted) {
          _applyPresenceRoster(roster);
        }
      });
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        supabaseRepo.joinRoomPresence(
          roomId,
          userId: currentUser.id,
          userName: currentUser.name.isNotEmpty ? currentUser.name : 'User',
        );
      }
    } else {
      _messagesSubscription = _chatRepository
          .watchMessages(roomId)
          .listen((messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
          });
          _rebuildUserPresences();
        }
      });
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _mediaSubscription?.cancel();
    _presenceSubscription?.cancel();
    _presenceRosterSubscription?.cancel();
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final roomId = widget.place.chatRoomId;
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      supabaseRepo.leaveRoomPresence(roomId);
    }
    _chatScrollController.dispose();
    _reactionRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final roomId = widget.place.chatRoomId;
    final textMessages = _messages
        .where((message) => message.mediaUrl == null || message.mediaUrl!.isEmpty)
        .toList();
    final displayMessages = _buildDisplayMessages(textMessages);

    return LayoutBuilder(
      builder: (context, constraints) {
        const mediaHeight = 260.0;
        return Column(
          children: [
            SizedBox(
              height: mediaHeight,
              width: double.infinity,
              child: MediaCard(
                place: widget.place,
                mediaPosts: _mediaPosts,
                liveCount: widget.liveCount,
                borderRadius: BorderRadius.zero,
                topRightActions: null,
                useAspectRatio: false,
              ),
            ),
            SizedBox(height: tokens.space.s8),
            Expanded(
              child: GlassSurface(
                radius: tokens.radius.lg,
                blur: tokens.blur.med,
                scrim: tokens.card.glassOverlay,
                borderColor: tokens.colors.border,
                child: Column(
                  children: [
                    _buildChatHeader(textMessages.length),
                    Expanded(
                      child: _buildChatList(
                        displayMessages,
                        _chatScrollController,
                      ),
                    ),
                    _buildChatInput(roomId),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatHeader(int messageCount) {
    final tokens = context.tokens;
    final activeCount = _userPresences.values
        .where((presence) => presence.isToday)
        .length;
    final onlineCount = SupabaseGate.isEnabled
        ? (_presenceRoster.isNotEmpty ? _presenceRoster.length : _presenceCount)
        : widget.liveCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space.s16,
        tokens.space.s12,
        tokens.space.s16,
        tokens.space.s8,
      ),
      child: Row(
        children: [
          Text(
            'Chat',
            style: tokens.type.title.copyWith(
              color: tokens.colors.textPrimary,
            ),
          ),
          SizedBox(width: tokens.space.s8),
          Text(
            '$messageCount',
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textMuted,
            ),
          ),
          SizedBox(width: tokens.space.s12),
          GlassBadge(
            label: 'Online $onlineCount',
            variant: GlassBadgeVariant.online,
          ),
          if (activeCount > 0) ...[
            SizedBox(width: tokens.space.s8),
            Text(
              'Aktiv $activeCount',
              style: tokens.type.caption.copyWith(
                color: tokens.colors.textMuted,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: Icon(Icons.group, color: tokens.colors.textPrimary),
            onPressed: _openRoomInfo,
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(
    List<ChatMessage> textMessages,
    ScrollController scrollController,
  ) {
    final tokens = context.tokens;
    if (textMessages.isEmpty) {
      return Center(
        child: Text(
          'Starte den Chat in diesem Raum',
          style: tokens.type.caption.copyWith(
            color: tokens.colors.textMuted,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s16,
        vertical: tokens.space.s6,
      ),
      itemCount: textMessages.length,
      itemBuilder: (context, index) {
        final message = textMessages[textMessages.length - 1 - index];
        return AnimatedSwitcher(
          duration: tokens.motion.med,
          child: ChatMessageTile(
            key: ValueKey(message.id),
            message: message,
            userPresences: _userPresences,
            onReact: (reaction) => _handleMessageReaction(message, reaction),
          ),
        );
      },
    );
  }

  List<ChatMessage> _buildDisplayMessages(List<ChatMessage> textMessages) {
    final combined = <ChatMessage>[
      ...textMessages,
      ..._systemMessages,
    ];
    combined.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return combined;
  }

  void _applyPresenceRoster(List<PresenceProfile> roster) {
    final previousIds = _presenceRoster.map((entry) => entry.userId).toSet();
    final nextIds = roster.map((entry) => entry.userId).toSet();

    final joined = roster.where((entry) => !previousIds.contains(entry.userId));
    final left = _presenceRoster
        .where((entry) => !nextIds.contains(entry.userId));

    final now = DateTime.now();
    for (final entry in joined) {
      _systemMessages.add(
        ChatMessage(
          id: 'sys_${now.microsecondsSinceEpoch}_${entry.userId}_join',
          roomId: widget.place.chatRoomId,
          userId: 'system',
          userName: 'system',
          text: '${entry.userName} ist beigetreten',
          createdAt: now,
          isMine: false,
        ),
      );
    }
    for (final entry in left) {
      _systemMessages.add(
        ChatMessage(
          id: 'sys_${now.microsecondsSinceEpoch}_${entry.userId}_leave',
          roomId: widget.place.chatRoomId,
          userId: 'system',
          userName: 'system',
          text: '${entry.userName} hat den Raum verlassen',
          createdAt: now,
          isMine: false,
        ),
      );
    }

    if (_systemMessages.length > 50) {
      _systemMessages.removeRange(0, _systemMessages.length - 50);
    }

    setState(() {
      _presenceRoster = roster;
    });
  }

  void _openRoomInfo() {
    final presences = _userPresences.values
        .where((presence) => presence.isToday)
        .toList()
      ..sort((a, b) {
        final scoreCompare = b.activityScoreToday.compareTo(a.activityScoreToday);
        if (scoreCompare != 0) return scoreCompare;
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomInfoScreen(
          place: widget.place,
          liveCount: SupabaseGate.isEnabled ? _presenceCount : widget.liveCount,
          presences: presences,
          roster: _presenceRoster,
        ),
      ),
    );
  }

  Widget _buildChatInput(String roomId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return ChatInput(
        roomId: roomId,
        userId: '',
        onSend: (_, __, ___) async {},
        placeholder: 'Schreib etwas…',
        enabled: false,
      );
    }
    return ChatInput(
      roomId: roomId,
      userId: currentUser.id,
      onSend: (roomId, userId, text) async {
        if (_chatRepository is SupabaseChatRepository) {
          final repo = _chatRepository as SupabaseChatRepository;
          await repo.sendTextMessage(roomId, userId, text);
        } else {
          final message = ChatMessage(
            id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
            roomId: roomId,
            userId: userId,
            userName: currentUser.name,
            userAvatar: currentUser.photoUrl,
            text: text,
            createdAt: DateTime.now(),
            isMine: true,
          );
          _chatRepository.sendMessage(roomId, message);
        }
      },
      placeholder: 'Schreib etwas…',
    );
  }


  void _scheduleReactionRefresh(List<ChatMessage> messages) {
    if (_chatRepository is! SupabaseChatRepository) return;
    _reactionRefreshTimer?.cancel();
    _reactionRefreshTimer = Timer(const Duration(milliseconds: 120), () async {
      final repo = _chatRepository as SupabaseChatRepository;
      final refreshed = await repo.attachMessageReactions(messages);
      if (!mounted) return;
      setState(() {
        _messages = refreshed;
      });
    });
  }

  void _rebuildUserPresences() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final perUser = <String, UserPresence>{};

    for (final message in _messages) {
      if (DateTime(message.createdAt.year, message.createdAt.month, message.createdAt.day) !=
          today) {
        continue;
      }
      final existing = perUser[message.userId];
      final lastSeenAt = existing == null ||
              message.createdAt.isAfter(existing.lastSeenAt)
          ? message.createdAt
          : existing.lastSeenAt;
      perUser[message.userId] = UserPresence(
        userId: message.userId,
        userName: message.userName,
        userAvatar: message.userAvatar,
        roomId: message.roomId,
        lastSeenAt: lastSeenAt,
        messageCountToday: (existing?.messageCountToday ?? 0) + 1,
        mediaCountToday: existing?.mediaCountToday ?? 0,
        isActiveToday: true,
      );
    }

    for (final post in _mediaPosts) {
      if (DateTime(post.createdAt.year, post.createdAt.month, post.createdAt.day) !=
          today) {
        continue;
      }
      final existing = perUser[post.userId];
      final lastSeenAt = existing == null ||
              post.createdAt.isAfter(existing.lastSeenAt)
          ? post.createdAt
          : existing.lastSeenAt;
      perUser[post.userId] = UserPresence(
        userId: post.userId,
        userName: existing?.userName ?? '',
        userAvatar: existing?.userAvatar,
        roomId: widget.place.chatRoomId,
        lastSeenAt: lastSeenAt,
        messageCountToday: existing?.messageCountToday ?? 0,
        mediaCountToday: (existing?.mediaCountToday ?? 0) + 1,
        isActiveToday: true,
      );
    }

    setState(() {
      _userPresences
        ..clear()
        ..addAll(perUser);
    });
  }

  Future<void> _handleMessageReaction(
    ChatMessage message,
    String reaction,
  ) async {
    if (_isReactingToMessage) return;
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;

    final original = message;
    final wasSelected = original.currentUserReaction == reaction;
    final hadReaction = original.currentUserReaction != null;

    final updatedCounts = Map<String, int>.from(original.reactionCounts);
    int newTotal = original.reactionsCount;
    String? newUserReaction;

    if (wasSelected) {
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 1) - 1;
      if ((updatedCounts[reaction] ?? 0) <= 0) {
        updatedCounts.remove(reaction);
      }
      newTotal = (newTotal - 1).clamp(0, 1 << 31);
      newUserReaction = null;
    } else if (hadReaction) {
      final previous = original.currentUserReaction!;
      updatedCounts[previous] = (updatedCounts[previous] ?? 1) - 1;
      if ((updatedCounts[previous] ?? 0) <= 0) {
        updatedCounts.remove(previous);
      }
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      newUserReaction = reaction;
    } else {
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      newTotal = newTotal + 1;
      newUserReaction = reaction;
    }

    final updatedMessage = ChatMessage(
      id: original.id,
      roomId: original.roomId,
      userId: original.userId,
      userName: original.userName,
      userAvatar: original.userAvatar,
      text: original.text,
      mediaUrl: original.mediaUrl,
      createdAt: original.createdAt,
      isMine: original.isMine,
      reactionsCount: newTotal,
      currentUserReaction: newUserReaction,
      reactionCounts: updatedCounts,
    );

    setState(() {
      _messages = _messages
          .map((msg) => msg.id == original.id ? updatedMessage : msg)
          .toList();
      _isReactingToMessage = true;
    });

    try {
      if (_chatRepository is SupabaseChatRepository) {
        final repo = _chatRepository as SupabaseChatRepository;
        await repo.reactToMessage(messageId: message.id, reaction: reaction);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((msg) => msg.id == original.id ? original : msg)
            .toList();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isReactingToMessage = false;
        });
      }
    }
  }
}

class StreamChatRoomScreen extends StatefulWidget {
  final Place place;

  const StreamChatRoomScreen({
    super.key,
    required this.place,
  });

  @override
  State<StreamChatRoomScreen> createState() => _StreamChatRoomScreenState();
}

class _StreamChatRoomScreenState extends State<StreamChatRoomScreen> {
  late final dynamic _chatRepository;
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  StreamSubscription<List<RoomMediaPost>>? _mediaSubscription;
  StreamSubscription<int>? _presenceSubscription;
  StreamSubscription<List<PresenceProfile>>? _presenceRosterSubscription;
  final ScrollController _chatScrollController = ScrollController();
  List<ChatMessage> _messages = [];
  final List<ChatMessage> _systemMessages = [];
  List<RoomMediaPost> _mediaPosts = [];
  int _presenceCount = 0;
  bool _isReactingToMessage = false;
  List<PresenceProfile> _presenceRoster = [];

  @override
  void initState() {
    super.initState();
    if (SupabaseGate.isEnabled) {
      _chatRepository = SupabaseChatRepository();
    } else {
      _chatRepository = ChatRepository();
    }
    final roomId = widget.place.chatRoomId;
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      Future.microtask(() {
        supabaseRepo.ensureRoomExists(roomId, widget.place.id);
      });
      _messagesSubscription =
          supabaseRepo.watchMessages(roomId, limit: 50).listen((messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
          });
        }
      });
      _mediaSubscription = supabaseRepo
          .watchRoomMediaPosts(roomId, limit: ROOM_MEDIA_LIMIT)
          .listen((posts) {
        if (mounted) {
          setState(() {
            _mediaPosts = posts;
          });
        }
      });
      _presenceSubscription =
          supabaseRepo.watchPresenceCount(roomId).listen((count) {
        if (mounted) {
          setState(() {
            _presenceCount = count;
          });
        }
      });
      _presenceRosterSubscription =
          supabaseRepo.watchPresenceRoster(roomId).listen((roster) {
        if (mounted) {
          _applyRoomPresenceRoster(roster);
        }
      });
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        supabaseRepo.joinRoomPresence(
          roomId,
          userId: currentUser.id,
          userName: currentUser.name.isNotEmpty ? currentUser.name : 'User',
        );
      }
    } else {
      _messagesSubscription = _chatRepository
          .watchMessages(roomId)
          .listen((messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _mediaSubscription?.cancel();
    _presenceSubscription?.cancel();
    _presenceRosterSubscription?.cancel();
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final roomId = widget.place.chatRoomId;
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      supabaseRepo.leaveRoomPresence(roomId);
    }
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final roomId = widget.place.chatRoomId;
    final textMessages = _messages
        .where((message) => message.mediaUrl == null || message.mediaUrl!.isEmpty)
        .toList();
    final displayMessages = _buildRoomDisplayMessages(textMessages);
    final liveCount =
        SupabaseGate.isEnabled ? _presenceCount : widget.place.liveCount;

    return Scaffold(
      backgroundColor: tokens.colors.bg,
      appBar: AppBar(
        backgroundColor: tokens.colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.place.name,
          style: tokens.type.title.copyWith(
            color: tokens.colors.textPrimary,
          ),
        ),
        actions: [
          GlassBadge(
            label:
                'Online ${SupabaseGate.isEnabled ? (_presenceRoster.isNotEmpty ? _presenceRoster.length : _presenceCount) : widget.place.liveCount}',
            variant: GlassBadgeVariant.online,
          ),
          GlassButton(
            variant: GlassButtonVariant.icon,
            icon: Icons.group,
            onPressed: _openRoomInfo,
          ),
          SizedBox(width: tokens.space.s8),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: MediaCard(
              place: widget.place,
              mediaPosts: _mediaPosts,
              liveCount: liveCount,
              borderRadius: BorderRadius.zero,
              topRightActions: null,
              useAspectRatio: false,
            ),
          ),
          Expanded(
            child: GlassSurface(
              radius: tokens.radius.sm,
              blur: tokens.blur.med,
              scrim: tokens.card.glassOverlay,
              borderColor: tokens.colors.transparent,
              child: displayMessages.isEmpty
                    ? Center(
                        child: Text(
                          'Noch keine Nachrichten',
                          style: tokens.type.caption.copyWith(
                            color: tokens.colors.textMuted,
                          ),
                        ),
                      )
                  : ListView.builder(
                      controller: _chatScrollController,
                      reverse: true,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.space.s16,
                        vertical: tokens.space.s8,
                      ),
                      itemCount: displayMessages.length,
                      itemBuilder: (context, index) {
                        final message =
                            displayMessages[displayMessages.length - 1 - index];
                        return AnimatedSwitcher(
                          duration: tokens.motion.med,
                          child: ChatMessageTile(
                            key: ValueKey(message.id),
                            message: message,
                                onReact: (reaction) =>
                                    _handleMessageReaction(message, reaction),
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Builder(
              builder: (context) {
                final currentUser = AuthService.instance.currentUser;
                if (currentUser == null) {
                  return ChatInput(
                    roomId: roomId,
                    userId: '',
                    onSend: (_, __, ___) async {},
                    placeholder: 'Schreib etwas…',
                    enabled: false,
                  );
                }
                return ChatInput(
                  roomId: roomId,
                  userId: currentUser.id,
                  onSend: (roomId, userId, text) async {
                    if (_chatRepository is SupabaseChatRepository) {
                      final repo = _chatRepository as SupabaseChatRepository;
                      await repo.sendTextMessage(roomId, userId, text);
                    } else {
                      final message = ChatMessage(
                        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                        roomId: roomId,
                        userId: userId,
                        userName: currentUser.name,
                        userAvatar: currentUser.photoUrl,
                        text: text,
                        createdAt: DateTime.now(),
                        isMine: true,
                      );
                      _chatRepository.sendMessage(roomId, message);
                    }
                  },
                  placeholder: 'Schreib etwas…',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ChatMessage> _buildRoomDisplayMessages(List<ChatMessage> textMessages) {
    final combined = <ChatMessage>[
      ...textMessages,
      ..._systemMessages,
    ];
    combined.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return combined;
  }

  void _applyRoomPresenceRoster(List<PresenceProfile> roster) {
    final previousIds = _presenceRoster.map((entry) => entry.userId).toSet();
    final nextIds = roster.map((entry) => entry.userId).toSet();

    final joined = roster.where((entry) => !previousIds.contains(entry.userId));
    final left = _presenceRoster
        .where((entry) => !nextIds.contains(entry.userId));

    final now = DateTime.now();
    for (final entry in joined) {
      _systemMessages.add(
        ChatMessage(
          id: 'sys_${now.microsecondsSinceEpoch}_${entry.userId}_join',
          roomId: widget.place.chatRoomId,
          userId: 'system',
          userName: 'system',
          text: '${entry.userName} ist beigetreten',
          createdAt: now,
          isMine: false,
        ),
      );
    }
    for (final entry in left) {
      _systemMessages.add(
        ChatMessage(
          id: 'sys_${now.microsecondsSinceEpoch}_${entry.userId}_leave',
          roomId: widget.place.chatRoomId,
          userId: 'system',
          userName: 'system',
          text: '${entry.userName} hat den Raum verlassen',
          createdAt: now,
          isMine: false,
        ),
      );
    }

    if (_systemMessages.length > 50) {
      _systemMessages.removeRange(0, _systemMessages.length - 50);
    }

    setState(() {
      _presenceRoster = roster;
    });
  }

  void _openRoomInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomInfoScreen(
          place: widget.place,
          liveCount: SupabaseGate.isEnabled ? _presenceCount : widget.place.liveCount,
          presences: _buildRoomPresences(),
          roster: _presenceRoster,
        ),
      ),
    );
  }

  List<UserPresence> _buildRoomPresences() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final perUser = <String, UserPresence>{};
    for (final message in _messages) {
      final messageDate = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (messageDate != todayDate) continue;
      final existing = perUser[message.userId];
      final lastSeenAt = existing == null || message.createdAt.isAfter(existing.lastSeenAt)
          ? message.createdAt
          : existing.lastSeenAt;
      final isMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
      perUser[message.userId] = UserPresence(
        userId: message.userId,
        userName: message.userName,
        userAvatar: message.userAvatar,
        roomId: widget.place.chatRoomId,
        lastSeenAt: lastSeenAt,
        messageCountToday: (existing?.messageCountToday ?? 0) + (isMedia ? 0 : 1),
        mediaCountToday: (existing?.mediaCountToday ?? 0) + (isMedia ? 1 : 0),
        isActiveToday: true,
      );
    }
    final presences = perUser.values.toList()
      ..sort((a, b) {
        final scoreCompare = b.activityScoreToday.compareTo(a.activityScoreToday);
        if (scoreCompare != 0) return scoreCompare;
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
    return presences;
  }

  Future<void> _handleMessageReaction(
    ChatMessage message,
    String reaction,
  ) async {
    if (_isReactingToMessage) return;
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;

    final original = message;
    final wasSelected = original.currentUserReaction == reaction;
    final hadReaction = original.currentUserReaction != null;

    final updatedCounts = Map<String, int>.from(original.reactionCounts);
    int newTotal = original.reactionsCount;
    String? newUserReaction;

    if (wasSelected) {
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 1) - 1;
      if ((updatedCounts[reaction] ?? 0) <= 0) {
        updatedCounts.remove(reaction);
      }
      newTotal = (newTotal - 1).clamp(0, 1 << 31);
      newUserReaction = null;
    } else if (hadReaction) {
      final previous = original.currentUserReaction!;
      updatedCounts[previous] = (updatedCounts[previous] ?? 1) - 1;
      if ((updatedCounts[previous] ?? 0) <= 0) {
        updatedCounts.remove(previous);
      }
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      newUserReaction = reaction;
    } else {
      updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      newTotal = newTotal + 1;
      newUserReaction = reaction;
    }

    final updatedMessage = ChatMessage(
      id: original.id,
      roomId: original.roomId,
      userId: original.userId,
      userName: original.userName,
      userAvatar: original.userAvatar,
      text: original.text,
      mediaUrl: original.mediaUrl,
      createdAt: original.createdAt,
      isMine: original.isMine,
      reactionsCount: newTotal,
      currentUserReaction: newUserReaction,
      reactionCounts: updatedCounts,
    );

    setState(() {
      _messages = _messages
          .map((msg) => msg.id == original.id ? updatedMessage : msg)
          .toList();
      _isReactingToMessage = true;
    });

    try {
      if (_chatRepository is SupabaseChatRepository) {
        final repo = _chatRepository as SupabaseChatRepository;
        await repo.reactToMessage(messageId: message.id, reaction: reaction);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((msg) => msg.id == original.id ? original : msg)
            .toList();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isReactingToMessage = false;
        });
      }
    }
  }
}

class StreamHeader extends StatelessWidget {
  final String placeName;
  final int liveCount;
  final double? distanceKm;
  final bool isSaved;
  final bool isSaving;
  final VoidCallback onToggleSave;
  final VoidCallback onAddToCollab;
  final bool showBackButton;
  final VoidCallback? onBack;

  const StreamHeader({
    super.key,
    required this.placeName,
    required this.liveCount,
    this.distanceKm,
    required this.isSaved,
    required this.isSaving,
    required this.onToggleSave,
    required this.onAddToCollab,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GlassSurface(
      radius: tokens.radius.sm,
      blur: tokens.blur.low,
      scrim: tokens.card.glassOverlay,
      borderColor: tokens.colors.border,
      padding: EdgeInsets.fromLTRB(
        tokens.space.s12,
        tokens.space.s12,
        tokens.space.s12,
        tokens.space.s8,
      ),
      child: Row(
        children: [
          if (showBackButton) ...[
            GlassButton(
              variant: GlassButtonVariant.icon,
              icon: Icons.arrow_back,
              onPressed: onBack,
            ),
            SizedBox(width: tokens.space.s8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placeName,
                  style: tokens.type.title.copyWith(
                    color: tokens.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: tokens.space.s6),
                Wrap(
                  spacing: tokens.space.s8,
                  runSpacing: tokens.space.s6,
                  children: [
                    GlassBadge(
                      label: liveCount > 0 ? 'LIVE · $liveCount' : 'LIVE',
                      variant: GlassBadgeVariant.live,
                    ),
                    if (distanceKm != null)
                      _buildDistancePill(context, distanceKm!),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              isSaving
                  ? SizedBox(
                      width: tokens.space.s24,
                      height: tokens.space.s24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.colors.textPrimary,
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        isSaved ? Icons.favorite : Icons.favorite_border,
                        color: tokens.colors.textPrimary,
                      ),
                      onPressed: isSaving ? null : onToggleSave,
                    ),
              SizedBox(width: tokens.space.s8),
              IconButton(
                icon: Icon(Icons.playlist_add, color: tokens.colors.textPrimary),
                onPressed: onAddToCollab,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistancePill(BuildContext context, double distanceKm) {
    final tokens = context.tokens;
    return GlassSurface(
      radius: tokens.radius.pill,
      blur: tokens.blur.low,
      scrim: tokens.card.glassOverlay,
      borderColor: tokens.colors.borderStrong,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s12,
        vertical: tokens.space.s6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.place,
            size: tokens.space.s12,
            color: tokens.colors.textSecondary,
          ),
          SizedBox(width: tokens.space.s6),
          Text(
            '${distanceKm.toStringAsFixed(1)} km',
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatRoomInfoScreen extends StatelessWidget {
  final Place place;
  final int liveCount;
  final List<UserPresence> presences;
  final List<PresenceProfile> roster;

  const ChatRoomInfoScreen({
    super.key,
    required this.place,
    required this.liveCount,
    required this.presences,
    required this.roster,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      appBar: AppBar(
        backgroundColor: tokens.colors.bg,
        elevation: 0,
        leading: GlassButton(
          variant: GlassButtonVariant.icon,
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Chatroom',
          style: tokens.type.title.copyWith(color: tokens.colors.textPrimary),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(tokens.space.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place.name,
              style: tokens.type.headline.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
            SizedBox(height: tokens.space.s12),
            Row(
              children: [
                _InfoChip(
                  label: 'Online $liveCount',
                  variant: GlassBadgeVariant.online,
                ),
                SizedBox(width: tokens.space.s8),
                _InfoChip(
                  label: 'Aktiv ${presences.length}',
                  variant: GlassBadgeVariant.fresh,
                ),
              ],
            ),
            SizedBox(height: tokens.space.s20),
            Text(
              'Online jetzt',
              style: tokens.type.title.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
            SizedBox(height: tokens.space.s12),
            SizedBox(
              height: 140,
              child: roster.isEmpty
                  ? Center(
                      child: Text(
                        'Gerade niemand online',
                        style: tokens.type.caption.copyWith(
                          color: tokens.colors.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: roster.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: tokens.colors.border, height: 1),
                      itemBuilder: (context, index) {
                        final presence = roster[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: GlassSurface(
                            radius: tokens.radius.pill,
                            blur: tokens.blur.low,
                            scrim: tokens.card.glassOverlay,
                            borderColor: tokens.colors.border,
                            child: CircleAvatar(
                              backgroundColor: tokens.colors.transparent,
                              backgroundImage: presence.userAvatar == null ||
                                      presence.userAvatar!.trim().isEmpty
                                  ? null
                                  : NetworkImage(presence.userAvatar!.trim()),
                              child: (presence.userAvatar == null ||
                                      presence.userAvatar!.trim().isEmpty)
                                  ? Icon(
                                      Icons.person,
                                      color: tokens.colors.textSecondary,
                                    )
                                  : null,
                            ),
                          ),
                          title: Text(
                            presence.userName,
                            style: tokens.type.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: tokens.colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Online',
                            style: tokens.type.caption.copyWith(
                              color: tokens.colors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(height: tokens.space.s20),
            Text(
              'Aktiv heute',
              style: tokens.type.title.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
            SizedBox(height: tokens.space.s12),
            Expanded(
              child: presences.isEmpty
                  ? Center(
                      child: Text(
                        'Noch keine aktiven Nutzer',
                        style: tokens.type.caption.copyWith(
                          color: tokens.colors.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: presences.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: tokens.colors.border, height: 1),
                      itemBuilder: (context, index) {
                        final presence = presences[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: GlassSurface(
                            radius: tokens.radius.pill,
                            blur: tokens.blur.low,
                            scrim: tokens.card.glassOverlay,
                            borderColor: tokens.colors.border,
                            child: CircleAvatar(
                              backgroundColor: tokens.colors.transparent,
                              backgroundImage: presence.userAvatar == null ||
                                      presence.userAvatar!.trim().isEmpty
                                  ? null
                                  : NetworkImage(presence.userAvatar!.trim()),
                              child: (presence.userAvatar == null ||
                                      presence.userAvatar!.trim().isEmpty)
                                  ? Icon(
                                      Icons.person,
                                      color: tokens.colors.textSecondary,
                                    )
                                  : null,
                            ),
                          ),
                          title: Text(
                            presence.userName,
                            style: tokens.type.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: tokens.colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '${presence.messageCountToday} Nachrichten · ${presence.mediaCountToday} Medien',
                            style: tokens.type.caption.copyWith(
                              color: tokens.colors.textMuted,
                            ),
                          ),
                          trailing: Text(
                            _formatTimeAgo(presence.lastSeenAt),
                            style: tokens.type.caption.copyWith(
                              color: tokens.colors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'gerade';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'vor ${diff.inHours}h';
    return 'vor ${diff.inDays}d';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final GlassBadgeVariant variant;

  const _InfoChip({
    required this.label,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBadge(label: label, variant: variant);
  }
}
