import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme_extensions.dart';
import '../theme/app_tokens.dart';
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
import '../widgets/glass/glass_bottom_sheet.dart';
import '../widgets/glass/glass_surface.dart';
import '../services/chat_repository.dart';
import '../services/supabase_chat_repository.dart';
import '../services/supabase_gate.dart';
import '../services/auth_service.dart';
import 'main_shell.dart';
import '../state/location_store.dart';
import '../models/app_location.dart';
import '../utils/distance_utils.dart';

enum StreamView { list, map }

class _RoomMessagePreview {
  final Place place;
  final ChatMessage? message;

  const _RoomMessagePreview({
    required this.place,
    required this.message,
  });
}

class _PlaceCluster {
  final String key;
  final List<Place> places;

  _PlaceCluster({
    required this.key,
    required this.places,
  });

  factory _PlaceCluster.single(Place place) {
    return _PlaceCluster(key: place.id, places: [place]);
  }

  LatLng get center {
    final avgLat =
        places.map((p) => p.lat ?? 0).reduce((a, b) => a + b) / places.length;
    final avgLng =
        places.map((p) => p.lng ?? 0).reduce((a, b) => a + b) / places.length;
    return LatLng(avgLat, avgLng);
  }

  int get totalLiveCount =>
      places.fold(0, (sum, place) => sum + place.liveCount);
}

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
  static const int MAP_MAX_PINS = 20;
  static final LatLngBounds _munichBounds = LatLngBounds(
    southwest: LatLng(47.95, 11.35),
    northeast: LatLng(48.35, 11.85),
  );
  static const double _mapMinZoom = 10.5;
  static const double _mapMaxZoom = 17.5;
  static const String _darkMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#151a20"}]},
  {"elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1f2630"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#26303b"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f141a"}]}
]
''';
  final PageController _pageController = PageController();
  final PlaceRepository _repository = PlaceRepository();
  final LocationStore _locationStore = LocationStore();
  late final dynamic _chatRepository;
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
  String? _userLabel;
  AppLocationSource? _userSource;
  bool _didFirstFrame = false;
  StreamView _activeView = StreamView.map;
  GoogleMapController? _mapController;
  CameraPosition? _lastMapCamera;
  bool _isMapLoading = false;
  bool _mapStyleReady = false;
  List<_RoomMessagePreview> _mapPreviews = [];
  Timer? _mapRefreshTimer;
  Set<Marker> _mapMarkers = {};
  Set<Circle> _mapCircles = {};
  RealtimeChannel? _liveTickerChannel;
  Set<String> _liveTickerRoomIds = {};
  Timer? _liveTickerOverlayTimer;
  double _tickerExtent = 0;
  bool _tickerInitialized = false;
  final Map<String, BitmapDescriptor> _markerIconCache = {};
  Timer? _loginGateTimer;
  String? _expandedClusterKey;
  bool get _isTickerExpanded => _tickerExtent > 140;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _didFirstFrame = true;
    });
    
    _activeRoomId = widget.activeRoomId;
    _activePlaceId = widget.activePlaceId;
    debugPrint('🟢 StreamScreen activePlaceId=${widget.activePlaceId} activeRoomId=${widget.activeRoomId}');
    if ((_activePlaceId != null && _activePlaceId!.isNotEmpty) ||
        (_activeRoomId != null && _activeRoomId!.isNotEmpty)) {
      _activeView = StreamView.list;
    }

    if (SupabaseGate.isEnabled) {
      _chatRepository = SupabaseChatRepository();
      _ensureLiveTickerRealtime();
    } else {
      _chatRepository = ChatRepository();
    }

    _locationStore.addListener(_handleLocationUpdate);
    _locationStore.init();
    _syncUserLocation(_locationStore.currentLocation, force: true);

    _scheduleGuestLoginNotice();

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
        _setStreamView(StreamView.list);
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

  void openPlaceRoom(String placeId) {
    _setStreamView(StreamView.list);
    _activePlaceId = placeId;
    _activeRoomId = 'place_$placeId';
    jumpToPlace(placeId);
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

  void _scheduleGuestLoginNotice() {
    if (AuthService.instance.currentUser != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Als Gast kannst du nicht schreiben. Bitte einloggen.'),
          duration: Duration(seconds: 3),
        ),
      );
    });
    _loginGateTimer?.cancel();
    _loginGateTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (AuthService.instance.currentUser != null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Bitte einloggen, um im Stream zu schreiben.'),
          duration: Duration(seconds: 4),
        ),
      );
    });
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
    _scheduleMapRefresh();
    _syncLiveTickerRoomIds();
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

  void _setStreamView(StreamView next) {
    if (_activeView == next) return;
    setState(() {
      _activeView = next;
    });
    if (next == StreamView.map) {
      setState(() {
        _mapStyleReady = false;
      });
      _applyMapStyle();
      _scheduleMapRefresh();
    }
  }

  Future<void> _applyMapStyle() async {
    if (_mapController == null) return;
    await _mapController!.setMapStyle(_darkMapStyle);
    if (!mounted) return;
    setState(() {
      _mapStyleReady = true;
    });
  }

  List<Place> get _mapPlaces {
    final candidates = _sortedPlaces
        .where((place) => place.lat != null && place.lng != null)
        .toList();
    if (candidates.length <= MAP_MAX_PINS) return candidates;
    return candidates.take(MAP_MAX_PINS).toList();
  }

  void _scheduleMapRefresh() {
    _mapRefreshTimer?.cancel();
    _mapRefreshTimer = Timer(const Duration(milliseconds: 200), () {
      _refreshMapPreviews();
      _rebuildMapOverlays();
    });
  }

  void _ensureLiveTickerRealtime() {
    if (!SupabaseGate.isEnabled) return;
    if (_liveTickerChannel != null) return;

    try {
      final supabase = SupabaseGate.client;
      final currentUserId = AuthService.instance.currentUser?.id;
      final channel = supabase.channel('live_ticker');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          try {
            final message = ChatMessage.fromJson(
              Map<String, dynamic>.from(payload.newRecord),
              currentUserId: currentUserId,
            );
            final roomId = message.roomId;
            if (roomId.isEmpty || !_liveTickerRoomIds.contains(roomId)) {
              return;
            }
            final placeIndex = _sortedPlaces.indexWhere(
              (item) => item.roomId == roomId,
            );
            if (placeIndex == -1) return;
            final place = _sortedPlaces[placeIndex];

            final now = DateTime.now();
            final updated = List<_RoomMessagePreview>.from(_mapPreviews);
            final index =
                updated.indexWhere((preview) => preview.place.id == place.id);
            final nextPreview =
                _RoomMessagePreview(place: place, message: message);
            if (index == -1) {
              updated.add(nextPreview);
            } else {
              updated[index] = nextPreview;
            }

            final recentOnly = updated.where((preview) {
              final createdAt = preview.message?.createdAt;
              if (createdAt == null) return false;
              return now.difference(createdAt).inHours < 24;
            }).toList()
              ..sort((a, b) {
                final aTime = a.message?.createdAt;
                final bTime = b.message?.createdAt;
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

            if (!mounted) return;
            setState(() {
              _mapPreviews = recentOnly.take(10).toList();
            });
            _scheduleLiveTickerOverlayRebuild();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ StreamScreen: Live ticker realtime failed: $e');
            }
          }
        },
      ).subscribe();

      _liveTickerChannel = channel;
      if (kDebugMode) {
        debugPrint('✅ StreamScreen: Live ticker realtime subscribed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ StreamScreen: Failed to subscribe live ticker: $e');
      }
    }
  }

  void _syncLiveTickerRoomIds() {
    _liveTickerRoomIds = _sortedPlaces
        .map((place) => place.roomId)
        .where((roomId) => roomId.isNotEmpty)
        .toSet();
  }

  void _scheduleLiveTickerOverlayRebuild() {
    _liveTickerOverlayTimer?.cancel();
    _liveTickerOverlayTimer = Timer(const Duration(milliseconds: 250), () {
      _rebuildMapOverlays();
    });
  }

  Future<void> _refreshMapPreviews() async {
    if (_isMapLoading) return;
    if (!mounted) return;
    final rooms = _sortedPlaces;
    if (rooms.isEmpty) {
      setState(() {
        _mapPreviews = [];
      });
      return;
    }

    setState(() {
      _isMapLoading = true;
    });

    Map<String, ChatMessage> latestByRoom = {};
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final repo = _chatRepository as SupabaseChatRepository;
      latestByRoom = await repo.fetchLatestMessages(
        rooms.map((place) => place.roomId).toList(),
      );
    }

    if (!mounted) return;
    final now = DateTime.now();
    final previews = rooms
        .map(
          (place) => _RoomMessagePreview(
            place: place,
            message: latestByRoom[place.roomId],
          ),
        )
        .toList();

    previews.sort((a, b) {
      final aTime = a.message?.createdAt;
      final bTime = b.message?.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    final recentOnly = previews.where((preview) {
      final createdAt = preview.message?.createdAt;
      if (createdAt == null) return false;
      return now.difference(createdAt).inHours < 24;
    }).toList();

    setState(() {
      _mapPreviews = recentOnly.take(10).toList();
      _isMapLoading = false;
    });
  }

  void _rebuildMapOverlays() {
    _rebuildMapOverlaysAsync();
  }

  Future<void> _rebuildMapOverlaysAsync() async {
    final places = _mapPlaces;
    if (places.isEmpty) {
      setState(() {
        _mapMarkers = {};
        _mapCircles = {};
      });
      return;
    }

    final zoom = _lastMapCamera?.zoom ?? 13.5;
    final shouldCluster = places.length >= 10;
    final clusters = shouldCluster
        ? _clusterPlaces(places, zoom)
        : [for (final place in places) _PlaceCluster.single(place)];

    final markers = <Marker>{};
    final circles = <Circle>{};
    final latestById = <String, ChatMessage?>{
      for (final preview in _mapPreviews) preview.place.id: preview.message,
    };

    for (final cluster in clusters) {
      final activity = _clusterActivityScore(cluster, latestById);
      final isCluster = cluster.places.length > 1;
      final markerColor = _markerColorForActivity(activity, isCluster: isCluster);
      final icon = await _markerIconFor(
        color: markerColor,
        label: isCluster ? '${cluster.places.length}' : null,
        size: isCluster ? 56 : 44,
      );
      if ((_expandedClusterKey != null &&
              _expandedClusterKey == cluster.key) ||
          cluster.places.length > 5) {
        for (final place in cluster.places) {
          final position = LatLng(place.lat!, place.lng!);
          final placeActivity = _activityScoreForPlace(
            place,
            latestById[place.id],
          );
          final placeIcon = await _markerIconFor(
            color: _markerColorForActivity(placeActivity, isCluster: false),
            label: null,
            size: 44,
          );
          markers.add(
            Marker(
              markerId: MarkerId(place.id),
              position: position,
              onTap: () => _showMapRoomPreview(place),
              icon: placeIcon,
              alpha: 0.95,
              zIndex: 3,
            ),
          );
          if (placeActivity > 0) {
            circles.add(
              Circle(
                circleId: CircleId(place.id),
                center: position,
                radius: _heatRadiusForActivity(placeActivity),
                fillColor: _heatColorForActivity(placeActivity),
                strokeColor:
                    _heatColorForActivity(placeActivity).withOpacity(0.4),
                strokeWidth: 1,
              ),
            );
          }
        }
        continue;
      }
      if (cluster.places.length == 1) {
        final place = cluster.places.first;
        final position = LatLng(place.lat!, place.lng!);
        markers.add(
          Marker(
            markerId: MarkerId(place.id),
            position: position,
            onTap: () => _showMapRoomPreview(place),
            icon: icon,
            alpha: 0.9,
          ),
        );
        final placeActivity = _activityScoreForPlace(place, latestById[place.id]);
        if (placeActivity > 0) {
          circles.add(
            Circle(
              circleId: CircleId(place.id),
              center: position,
              radius: _heatRadiusForActivity(placeActivity),
              fillColor: _heatColorForActivity(placeActivity),
              strokeColor: _heatColorForActivity(placeActivity).withOpacity(0.4),
              strokeWidth: 1,
            ),
          );
        }
      } else {
        final position = cluster.center;
        markers.add(
          Marker(
            markerId: MarkerId('cluster_${cluster.key}'),
            position: position,
            icon: icon,
            alpha: 0.95,
            zIndex: 2,
            infoWindow: const InfoWindow(title: '', snippet: ''),
            onTap: () {
              if (_mapController == null) return;
              final bounds = _boundsForPlaces(cluster.places);
              if (bounds != null) {
                final padding = MediaQuery.of(context).size.width * 0.12;
                setState(() {
                  _expandedClusterKey = cluster.key;
                });
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, padding),
                );
                _rebuildMapOverlays();
              } else {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(position, zoom + 1.5),
                );
              }
            },
          ),
        );
        if (activity > 0) {
          circles.add(
            Circle(
              circleId: CircleId('cluster_${cluster.key}'),
              center: position,
              radius: _heatRadiusForActivity(activity),
              fillColor: _heatColorForActivity(activity),
              strokeColor: _heatColorForActivity(activity).withOpacity(0.4),
              strokeWidth: 1,
            ),
          );
        }
      }
    }

    setState(() {
      _mapMarkers = markers;
      _mapCircles = circles;
    });
  }

  List<_PlaceCluster> _clusterPlaces(List<Place> places, double zoom) {
    final cellSize = _clusterCellSize(zoom);
    final buckets = <String, _PlaceCluster>{};
    for (final place in places) {
      final lat = place.lat!;
      final lng = place.lng!;
      final bucketLat = (lat / cellSize).round();
      final bucketLng = (lng / cellSize).round();
      final key = '$bucketLat-$bucketLng';
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = _PlaceCluster(key: key, places: [place]);
      } else {
        existing.places.add(place);
      }
    }
    return buckets.values.toList();
  }

  LatLngBounds? _boundsForPlaces(List<Place> places) {
    if (places.isEmpty) return null;
    double? minLat;
    double? maxLat;
    double? minLng;
    double? maxLng;

    for (final place in places) {
      final lat = place.lat;
      final lng = place.lng;
      if (lat == null || lng == null) continue;
      minLat = minLat == null ? lat : min(minLat, lat);
      maxLat = maxLat == null ? lat : max(maxLat, lat);
      minLng = minLng == null ? lng : min(minLng, lng);
      maxLng = maxLng == null ? lng : max(maxLng, lng);
    }

    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return null;
    }

    final padding = 0.0015;
    return LatLngBounds(
      southwest: LatLng(minLat - padding, minLng - padding),
      northeast: LatLng(maxLat + padding, maxLng + padding),
    );
  }

  double _clusterCellSize(double zoom) {
    if (zoom >= 15) return 0.004;
    if (zoom >= 13) return 0.008;
    if (zoom >= 11) return 0.02;
    return 0.04;
  }

  int _activityScoreForPlace(Place place, ChatMessage? message) {
    final live = place.liveCount;
    if (live > 0) {
      return live;
    }
    if (message == null) return 0;
    final minutes = DateTime.now().difference(message.createdAt).inMinutes;
    if (minutes <= 5) return 6;
    if (minutes <= 30) return 3;
    if (minutes <= 120) return 1;
    return 0;
  }

  int _clusterActivityScore(
    _PlaceCluster cluster,
    Map<String, ChatMessage?> latestById,
  ) {
    var total = 0;
    for (final place in cluster.places) {
      total += _activityScoreForPlace(place, latestById[place.id]);
    }
    return total;
  }

  Color _markerColorForActivity(int activity, {bool isCluster = false}) {
    if (activity <= 0) {
      return const Color(0xFF7B8794);
    }
    if (isCluster) {
      if (activity >= 15) return const Color(0xFF6B4CFF);
      if (activity >= 5) return const Color(0xFF4AA5FF);
      return const Color(0xFF3AD3FF);
    }
    if (activity >= 15) return const Color(0xFF45E1FF);
    if (activity >= 5) return const Color(0xFF4AA5FF);
    return const Color(0xFF7B8794);
  }

  Future<BitmapDescriptor> _markerIconFor({
    required Color color,
    String? label,
    double size = 48,
  }) async {
    final key = '${color.value}_${label ?? 'pin'}_${size.toInt()}';
    final cached = _markerIconCache[key];
    if (cached != null) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;
    final center = Offset(radius, radius);

    final fillPaint = Paint()..color = color;
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = label == null ? 2 : 3;

    canvas.drawCircle(center, radius - 1, fillPaint);
    canvas.drawCircle(center, radius - 1, borderPaint);

    if (label != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: size);
      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2,
        ),
      );
    } else {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.chat_bubble.codePoint),
          style: TextStyle(
            fontFamily: Icons.chat_bubble.fontFamily,
            package: Icons.chat_bubble.fontPackage,
            color: Colors.white.withOpacity(0.95),
            fontSize: size * 0.5,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: size);
      iconPainter.paint(
        canvas,
        Offset(
          center.dx - iconPainter.width / 2,
          center.dy - iconPainter.height / 2,
        ),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return BitmapDescriptor.defaultMarker;
    }
    final descriptor = BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
    _markerIconCache[key] = descriptor;
    return descriptor;
  }

  double _heatRadiusForActivity(int activity) {
    final zoom = _lastMapCamera?.zoom ?? 13.5;
    final zoomFactor = (zoom / 13.5).clamp(0.9, 1.45);
    final base = 220.0 + (activity * 26).clamp(0, 320).toDouble();
    return base * zoomFactor;
  }

  Color _heatColorForActivity(int activity) {
    final zoom = _lastMapCamera?.zoom ?? 13.5;
    final baseOpacity = zoom >= 15
        ? 0.7
        : zoom >= 13
            ? 0.6
            : 0.5;
    if (activity >= 15) {
      return const Color(0xFF6B4CFF).withOpacity(baseOpacity);
    }
    if (activity >= 5) {
      return const Color(0xFF3BD6FF).withOpacity(baseOpacity);
    }
    return const Color(0xFF8FE3FF).withOpacity(baseOpacity * 0.8);
  }

  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.removeListener(_onPageChanged);
    _favoritePrefetchTimer?.cancel();
    _mapRefreshTimer?.cancel();
    _loginGateTimer?.cancel();
    _liveTickerOverlayTimer?.cancel();
    final channel = _liveTickerChannel;
    if (channel != null && SupabaseGate.isEnabled) {
      SupabaseGate.client.removeChannel(channel);
    }
    
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

    final bottomInset = MediaQuery.of(context).padding.bottom + 4;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Offstage(
            offstage: _activeView != StreamView.map,
            child: _buildMapBody(tokens),
          ),
          Offstage(
            offstage: _activeView != StreamView.list,
            child: _buildListBody(tokens, bottomInset),
          ),
          if (_activeView == StreamView.map)
            Positioned(
              top: MediaQuery.of(context).padding.top + tokens.space.s12,
              right: tokens.space.s12,
              child: _buildViewToggle(tokens),
            ),
        ],
      ),
    );
  }


  Widget _buildListBody(AppTokens tokens, double bottomInset) {
    return Padding(
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
    );
  }

  Widget _buildMapBody(AppTokens tokens) {
    return SizedBox.expand(child: _buildMapView());
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

  Widget _buildViewToggle(AppTokens tokens) {
    final isList = _activeView == StreamView.list;
    return GlassSurface(
      radius: tokens.radius.pill,
      blur: tokens.blur.low,
      scrim: tokens.card.glassOverlay,
      borderColor: tokens.colors.border,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleChip(
            label: 'Liste',
            isActive: isList,
            onTap: () => _setStreamView(StreamView.list),
          ),
          _buildToggleChip(
            label: 'Karte',
            isActive: !isList,
            onTap: () => _setStreamView(StreamView.map),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s12,
          vertical: tokens.space.s8,
        ),
        decoration: BoxDecoration(
          color: isActive ? tokens.colors.accent.withOpacity(0.2) : null,
          borderRadius: BorderRadius.circular(tokens.radius.pill),
        ),
        child: Text(
          label,
          style: tokens.type.caption.copyWith(
            color: isActive ? tokens.colors.accent : tokens.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final tokens = context.tokens;
    final center = _hasUserLocation
        ? LatLng(_userLat!, _userLng!)
        : const LatLng(48.137154, 11.576124);
    final initialCamera = _lastMapCamera ??
        CameraPosition(target: center, zoom: 13.5);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: initialCamera,
          onMapCreated: (controller) {
            _mapController = controller;
            _mapStyleReady = false;
            _applyMapStyle();
            if (_activeView == StreamView.map) {
              _scheduleMapRefresh();
            }
          },
          onCameraMove: (position) {
            _lastMapCamera = position;
          },
          onCameraIdle: _rebuildMapOverlays,
          myLocationEnabled: _hasUserLocation,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          zoomGesturesEnabled: !_isTickerExpanded,
          scrollGesturesEnabled: !_isTickerExpanded,
          rotateGesturesEnabled: !_isTickerExpanded,
          tiltGesturesEnabled: !_isTickerExpanded,
          minMaxZoomPreference: MinMaxZoomPreference(_mapMinZoom, _mapMaxZoom),
          cameraTargetBounds: CameraTargetBounds(_munichBounds),
          markers: _mapMarkers,
          circles: _mapCircles,
        ),
        if (!_mapStyleReady)
          Positioned.fill(
            child: Container(
              color: tokens.colors.bg,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        _buildLiveTickerPanel(tokens),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: tokens.space.s12),
            child: _buildMapControls(tokens),
          ),
        ),
      ],
    );
  }

  Widget _buildMapControls(AppTokens tokens) {
    return GlassSurface(
      radius: tokens.radius.md,
      blur: tokens.blur.low,
      scrim: tokens.card.glassOverlay,
      borderColor: tokens.colors.border,
      padding: EdgeInsets.symmetric(
        vertical: tokens.space.s6,
        horizontal: tokens.space.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              if (_mapController == null) return;
              _mapController!.animateCamera(CameraUpdate.zoomIn());
            },
            child: Padding(
              padding: EdgeInsets.all(tokens.space.s4),
              child: Icon(
                Icons.add,
                size: 16,
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: tokens.space.s6),
          InkWell(
            onTap: () {
              if (_mapController == null) return;
              _mapController!.animateCamera(CameraUpdate.zoomOut());
            },
            child: Padding(
              padding: EdgeInsets.all(tokens.space.s4),
              child: Icon(
                Icons.remove,
                size: 16,
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              if (_mapController == null) return;
              if (!_hasUserLocation) return;
              _mapController!.animateCamera(
                CameraUpdate.newLatLng(
                  LatLng(_userLat!, _userLng!),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(tokens.space.s4),
              child: Icon(
                Icons.my_location,
                size: 16,
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPlaceFromMap(Place place) {
    _setStreamView(StreamView.list);
    jumpToPlace(place.id);
  }

  _RoomMessagePreview? _previewForPlace(Place place) {
    return _mapPreviews.firstWhere(
      (preview) => preview.place.id == place.id,
      orElse: () => _RoomMessagePreview(place: place, message: null),
    );
  }

  Future<void> _showMapRoomPreview(Place place) async {
    final preview = _previewForPlace(place);
    if (preview == null) return;
    final tokens = context.tokens;
    final message = preview.message;
    final text = message?.text.trim().isNotEmpty == true
        ? message!.text.trim()
        : 'Noch keine Nachricht';

    await showGlassBottomSheet(
      context: context,
      isScrollControlled: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.title.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
            SizedBox(height: tokens.space.s8),
            Row(
              children: [
                _InfoChip(
                  label: 'Online ${preview.place.liveCount}',
                  variant: GlassBadgeVariant.online,
                ),
                SizedBox(width: tokens.space.s8),
                if (preview.place.distanceKm != null)
                  _InfoChip(
                    label: '${preview.place.distanceKm!.toStringAsFixed(1)} km',
                    variant: GlassBadgeVariant.fresh,
                  ),
              ],
            ),
            SizedBox(height: tokens.space.s12),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.body.copyWith(
                color: tokens.colors.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: tokens.space.s12),
            GlassButton(
              label: 'Chatroom öffnen',
              onPressed: () {
                Navigator.of(context).pop();
                _openPlaceFromMap(preview.place);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTickerPanel(AppTokens tokens) {
    final media = MediaQuery.of(context);
    final minHeight = 120.0;
    final maxHeight = media.size.height * 0.45;
    if (!_tickerInitialized) {
      _tickerExtent = minHeight;
      _tickerInitialized = true;
    }
    _tickerExtent = _tickerExtent.clamp(minHeight, maxHeight);

    final toggleTop = media.padding.top + 40;
    final panelTop = toggleTop + 52 + tokens.space.s8;

    return Positioned(
      left: 16,
      right: 16,
      top: panelTop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: _tickerExtent,
        child: GlassSurface(
          radius: tokens.radius.xl,
          blur: tokens.blur.low,
          scrim: tokens.card.glassOverlay,
          borderColor: tokens.colors.border,
          padding: EdgeInsets.fromLTRB(
            tokens.space.s16,
            tokens.space.s12,
            tokens.space.s16,
            tokens.space.s12,
          ),
          child: Column(
            children: [
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  setState(() {
                    _tickerExtent = (_tickerExtent - details.delta.dy)
                        .clamp(minHeight, maxHeight);
                  });
                },
                onVerticalDragEnd: (_) {
                  final midpoint = (minHeight + maxHeight) / 2;
                  setState(() {
                    _tickerExtent =
                        _tickerExtent < midpoint ? minHeight : maxHeight;
                  });
                },
                child: InkWell(
                  onTap: () {
                    final midpoint = (minHeight + maxHeight) / 2;
                    setState(() {
                      _tickerExtent =
                          _tickerExtent < midpoint ? maxHeight : minHeight;
                    });
                  },
                  borderRadius: BorderRadius.circular(tokens.radius.lg),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: tokens.space.s8),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: tokens.colors.textMuted.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        SizedBox(height: tokens.space.s8),
                        Row(
                          children: [
                            Text(
                              'Live‑Ticker',
                              style: tokens.type.title.copyWith(
                                color: tokens.colors.textPrimary,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            if (_isMapLoading)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.colors.textSecondary,
                                ),
                              ),
                            SizedBox(width: tokens.space.s8),
                            Icon(
                              _tickerExtent > minHeight + 10
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: tokens.colors.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: tokens.space.s8),
              Expanded(
                  child: _mapPreviews.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Nachrichten aktuell.',
                            style: tokens.type.body.copyWith(
                              color: tokens.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _mapPreviews.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: tokens.space.s8),
                        itemBuilder: (context, index) {
                          final preview = _mapPreviews[index];
                          final message = preview.message;
                          return InkWell(
                            onTap: () => _openPlaceFromMap(preview.place),
                            borderRadius:
                                BorderRadius.circular(tokens.radius.md),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: tokens.space.s8,
                                vertical: tokens.space.s6,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: tokens.colors.surfaceStrong
                                          .withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(
                                        tokens.radius.md,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.chat_bubble,
                                      color: tokens.colors.textSecondary,
                                      size: 18,
                                    ),
                                  ),
                                  SizedBox(width: tokens.space.s8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          preview.place.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tokens.type.body.copyWith(
                                            color: tokens.colors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        SizedBox(height: tokens.space.s4),
                                        Text(
                                          message?.text.trim().isNotEmpty == true
                                              ? message!.text.trim()
                                              : 'Noch keine Nachricht',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: tokens.type.caption.copyWith(
                                            color: tokens.colors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: tokens.space.s8),
                                  Text(
                                    _formatRelativeTime(message?.createdAt),
                                    style: tokens.type.caption.copyWith(
                                      color: tokens.colors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Jetzt';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
    return 'vor ${diff.inDays} Tg';
  }

  void _maybeReloadOnVisibility() {
    final isVisible = TickerMode.of(context);
    if (isVisible == _wasVisible) return;
    _wasVisible = isVisible;
    if (isVisible) {
      _locationStore.refreshFromStorage();
    }
  }

  /// Builds a single stream item with strict layout:
  /// - Top: MediaCard (full-width)
  /// - Below: Chat list (text-only)
  /// - Bottom: Chat input
  Widget _buildStreamItem(Place place, int index) {
    final liveCount = place.liveCount;
    final tokens = context.tokens;
    return Container(
      color: tokens.colors.bg,
      child: Column(
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
            onOpenRoomInfo: () => _openRoomInfo(place),
            showBackButton: _isSingleRoomMode,
            onBack: _isSingleRoomMode ? _exitSingleRoomMode : null,
            viewToggle: _buildViewToggle(tokens),
          ),
          Expanded(
            child: StreamChatPane(
              key: ValueKey('chat_${place.id}'),
              place: place,
              liveCount: liveCount,
            ),
          ),
        ],
      ),
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

  void _openRoomInfo(Place place) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomInfoScreen(
          place: place,
          liveCount: place.liveCount,
          presences: const [],
          roster: const [],
        ),
      ),
    );
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
    final nextLabel = location.label;
    final nextSource = location.source;
    final prevLat = _userLat;
    final prevLng = _userLng;
    final prevLabel = _userLabel;
    final prevSource = _userSource;
    final coordsChanged = nextLat != prevLat || nextLng != prevLng;

    debugPrint(
      'USER_LOC lat=$nextLat lng=$nextLng available=$hasLocation source=${location.source}',
    );

    if (!force &&
        !coordsChanged &&
        nextLabel == prevLabel &&
        nextSource == prevSource) {
      return;
    }

    _userLat = nextLat;
    _userLng = nextLng;
    _userLabel = nextLabel;
    _userSource = nextSource;

    final shouldResort =
        force || coordsChanged || nextLabel != prevLabel || nextSource != prevSource;
    if (shouldResort) {
      if (coordsChanged) {
        if (mounted && _didFirstFrame) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (messenger == null) return;
            messenger.showSnackBar(
              SnackBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(milliseconds: 1400),
                content: GlassSurface(
                  radius: 14,
                  blur: context.tokens.blur.low,
                  scrim: context.tokens.card.glassOverlay,
                  borderColor: context.tokens.colors.border,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.tokens.space.s12,
                    vertical: context.tokens.space.s8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: context.tokens.colors.accent,
                      ),
                      SizedBox(width: context.tokens.space.s8),
                      Text(
                        'Aktualisiere Nähe…',
                        style: context.tokens.type.body.copyWith(
                          color: context.tokens.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        }
        _fetchNextPoolChunk(reset: true);
      } else {
        _resortStreamPlaces();
      }
    }

    if (coordsChanged && _activeView == StreamView.map && _mapController != null) {
      final target = LatLng(nextLat, nextLng);
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(target),
      );
    }
    _scheduleMapRefresh();
  }

  void _resortStreamPlaces() {
    if (!mounted) return;
    if (_poolPlaces.isEmpty) return;
    setState(() {
      _isSorting = true;
    });
    final updated = _applyDistanceAndSort(_poolPlaces);
    _logSortTop5(updated);
    _updateSortedPlaces(updated);
    if (!mounted) return;
    setState(() {
      _isSorting = false;
    });
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
  StreamSubscription<List<PresenceProfile>>? _presenceRosterSubscription;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  static const double _sheetCollapsedSize = 0.2;
  static const double _sheetExpandedSize = 0.75;
  static const double _sheetMaxSize = 0.92;
  static const double _sheetToggleThreshold = 0.03;
  bool _isSheetExpanded = true;
  List<ChatMessage> _messages = [];
  final List<ChatMessage> _systemMessages = [];
  List<RoomMediaPost> _mediaPosts = [];
  bool _isReactingToMessage = false;
  final Map<String, UserPresence> _userPresences = {};
  Timer? _reactionRefreshTimer;
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
    _presenceRosterSubscription?.cancel();
    _sheetController.dispose();
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository) {
      final roomId = widget.place.chatRoomId;
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      supabaseRepo.leaveRoomPresence(roomId);
    }
    _reactionRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleChatSheet() async {
    if (!_sheetController.isAttached) return;
    final currentSize = _sheetController.size;
    final target = currentSize >=
            (_sheetExpandedSize - _sheetToggleThreshold)
        ? _sheetCollapsedSize
        : _sheetExpandedSize;
    setState(() {
      _isSheetExpanded = target == _sheetExpandedSize;
    });
    await _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final roomId = widget.place.chatRoomId;
    final textMessages = _messages
        .where((message) => message.mediaUrl == null || message.mediaUrl!.isEmpty)
        .toList();
    final displayMessages = _buildDisplayMessages(textMessages);
    return Stack(
      children: [
        Positioned.fill(
          child: MediaCard(
            place: widget.place,
            mediaPosts: _mediaPosts,
            liveCount: widget.liveCount,
            borderRadius: BorderRadius.zero,
            topRightActions: null,
            useAspectRatio: false,
            useTopSafeArea: false,
          ),
        ),
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            final isExpanded = notification.extent >=
                (_sheetExpandedSize - _sheetToggleThreshold);
            if (isExpanded != _isSheetExpanded && mounted) {
              setState(() {
                _isSheetExpanded = isExpanded;
              });
            }
            return false;
          },
          child: DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _sheetExpandedSize,
            minChildSize: _sheetCollapsedSize,
            maxChildSize: _sheetMaxSize,
            snap: true,
            snapSizes: const [_sheetCollapsedSize, _sheetExpandedSize],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: tokens.colors.bg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(tokens.radius.lg),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(height: tokens.space.s8),
                    GestureDetector(
                      onTap: _toggleChatSheet,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        children: [
                          Container(
                            width: tokens.space.s32,
                            height: tokens.space.s4,
                            decoration: BoxDecoration(
                              color: tokens.colors.textMuted.withOpacity(0.5),
                              borderRadius:
                                  BorderRadius.circular(tokens.radius.pill),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              tokens.space.s16,
                              tokens.space.s12,
                              tokens.space.s16,
                              tokens.space.s8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Live-Chat',
                                    style: tokens.type.title.copyWith(
                                      color: tokens.colors.textPrimary,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${displayMessages.length} Nachrichten',
                                      style: tokens.type.caption.copyWith(
                                        color: tokens.colors.textMuted,
                                      ),
                                    ),
                                    SizedBox(width: tokens.space.s8),
                                    GestureDetector(
                                      onTap: _toggleChatSheet,
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: tokens.colors.surfaceStrong,
                                          borderRadius:
                                              BorderRadius.circular(tokens.radius.pill),
                                          border: Border.all(
                                            color: tokens.colors.borderStrong,
                                          ),
                                        ),
                                        child: Icon(
                                          _isSheetExpanded
                                              ? Icons.keyboard_arrow_down
                                              : Icons.keyboard_arrow_up,
                                          color: tokens.colors.textSecondary,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _buildChatList(displayMessages, scrollController),
                    ),
                    _buildChatInput(roomId),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatList(
    List<ChatMessage> textMessages,
    ScrollController scrollController,
  ) {
    final tokens = context.tokens;
    if (textMessages.isEmpty) {
      return ListView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s16,
          vertical: tokens.space.s12,
        ),
        children: [
          SizedBox(height: tokens.space.s32),
          Center(
            child: Text(
              'Starte den Chat in diesem Raum',
              style: tokens.type.caption.copyWith(
                color: tokens.colors.textMuted,
              ),
            ),
          ),
        ],
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

  Widget _buildChatInput(String roomId) {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return ChatInput(
        roomId: roomId,
        userId: '',
        onSend: (_, __, ___) async {},
        placeholder: 'Nur eingeloggte Mitglieder können teilnehmen.',
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
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaCard(
              place: widget.place,
              mediaPosts: _mediaPosts,
              liveCount: liveCount,
              borderRadius: BorderRadius.zero,
              topRightActions: null,
              useAspectRatio: false,
              useTopSafeArea: true,
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.2,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: tokens.colors.bg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(tokens.radius.lg),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(height: tokens.space.s8),
                    Container(
                      width: tokens.space.s32,
                      height: tokens.space.s4,
                      decoration: BoxDecoration(
                        color: tokens.colors.textMuted.withOpacity(0.5),
                        borderRadius:
                            BorderRadius.circular(tokens.radius.pill),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        tokens.space.s16,
                        tokens.space.s12,
                        tokens.space.s16,
                        tokens.space.s8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Live-Chat',
                            style: tokens.type.title.copyWith(
                              color: tokens.colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${displayMessages.length} Nachrichten',
                            style: tokens.type.caption.copyWith(
                              color: tokens.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
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
                              controller: scrollController,
                              reverse: true,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: tokens.space.s16,
                                vertical: tokens.space.s8,
                              ),
                              itemCount: displayMessages.length,
                              itemBuilder: (context, index) {
                                final message = displayMessages[
                                    displayMessages.length - 1 - index];
                                return AnimatedSwitcher(
                                  duration: tokens.motion.med,
                                  child: ChatMessageTile(
                                    key: ValueKey(message.id),
                                    message: message,
                                    onReact: (reaction) =>
                                        _handleMessageReaction(
                                            message, reaction),
                                  ),
                                );
                              },
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
                                final repo =
                                    _chatRepository as SupabaseChatRepository;
                                await repo.sendTextMessage(
                                    roomId, userId, text);
                              } else {
                                final message = ChatMessage(
                                  id:
                                      'temp_${DateTime.now().millisecondsSinceEpoch}',
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
            },
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
  final VoidCallback onOpenRoomInfo;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget? viewToggle;

  const StreamHeader({
    super.key,
    required this.placeName,
    required this.liveCount,
    this.distanceKm,
    required this.isSaved,
    required this.isSaving,
    required this.onToggleSave,
    required this.onAddToCollab,
    required this.onOpenRoomInfo,
    this.showBackButton = false,
    this.onBack,
    this.viewToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.space.s12,
          tokens.space.s4,
          tokens.space.s12,
          tokens.space.s6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showBackButton) ...[
                  IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back,
                      color: tokens.colors.textPrimary,
                    ),
                    splashRadius: tokens.space.s20,
                  ),
                  SizedBox(width: tokens.space.s4),
                ],
                Expanded(
                  child: Text(
                    placeName,
                    style: tokens.type.title.copyWith(
                      color: tokens.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                    IconButton(
                      icon: Icon(Icons.playlist_add, color: tokens.colors.textPrimary),
                      onPressed: onAddToCollab,
                    ),
                    IconButton(
                      icon: Icon(Icons.group, color: tokens.colors.textPrimary),
                      onPressed: onOpenRoomInfo,
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: tokens.space.s6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: tokens.space.s8,
                    runSpacing: tokens.space.s6,
                    children: [
                      _buildOnlinePill(context, liveCount),
                      if (distanceKm != null)
                        _buildDistancePill(context, distanceKm!),
                    ],
                  ),
                ),
                if (viewToggle != null) ...[
                  SizedBox(width: tokens.space.s8),
                  viewToggle!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistancePill(BuildContext context, double distanceKm) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s12,
        vertical: tokens.space.s6,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.bg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(tokens.radius.pill),
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

  Widget _buildOnlinePill(BuildContext context, int onlineCount) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s12,
        vertical: tokens.space.s6,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.bg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(tokens.radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: tokens.space.s8,
            color: tokens.colors.accent,
          ),
          SizedBox(width: tokens.space.s6),
          Text(
            'Online $onlineCount',
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: tokens.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          splashRadius: tokens.space.s20,
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
