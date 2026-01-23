import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import '../models/chat_message.dart';
import 'main_shell.dart';
import 'creator_profile_screen.dart';
import 'collabs_explore_screen.dart';
import 'collab_detail_screen.dart';
import '../models/collab.dart';
import '../data/system_collabs.dart';
import '../models/app_location.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_profile_repository.dart';
import '../services/supabase_gate.dart';
import '../services/supabase_chat_repository.dart';
import '../services/activity_service.dart';
import '../widgets/place_image.dart';
import '../widgets/collab_card.dart';
import '../widgets/collab_carousel.dart';
import '../state/location_store.dart';
import '../utils/distance_utils.dart';
import 'location_picker_sheet.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onStreamTap;
  
  const HomeScreen({super.key, this.onStreamTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlaceRepository _repository = PlaceRepository();
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  final LocationStore _locationStore = LocationStore();
  Place? _streamPreviewPlace;
  List<Place> _hypePlaces = [];
  bool _isHypeLoading = false;
  bool _isStreamPreviewLoading = false;
  bool _isCollabLoading = true;
  List<Collab> _publicCollabs = [];
  final Map<String, int> _collabSaveCounts = {};
  final Map<String, UserProfile> _creatorProfiles = {};
  bool _showQuickIntro = true;
  static const String _quickIntroKey = 'home_quick_intro_dismissed';
  static const double _hypeMaxDistanceKm = 20;
  static const int _hypeLimit = 5;
  final SupabaseChatRepository _chatRepository = SupabaseChatRepository();
  final Map<String, StreamSubscription<List<ChatMessage>>>
      _hypeMessageSubscriptions = {};
  final Map<String, List<String>> _hypeMessagesByRoom = {};
  final Map<String, String?> _hypeMediaByRoom = {};

  @override
  void initState() {
    super.initState();
    _locationStore.init();
    _loadQuickIntroPreference();
    _loadStreamPreviewPlace();
    _loadHypePlaces();
    _checkActivityNotifications();
    _loadDiscoveryCollabs();
    _locationStore.addListener(_handleLocationChange);
  }

  /// Check and show activity notifications
  Future<void> _checkActivityNotifications() async {
    // Wait a bit for UI to settle
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;
    
    final activityService = ActivityService();
    final notification = await activityService.getActivityNotification();
    
    if (notification != null && mounted) {
      // Mark as shown to prevent spam
      await activityService.markNotificationShown();
      
      // Show contextual notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: GlassSurface(
            radius: MingaTheme.radiusSm,
            blurSigma: 18,
            overlayColor: MingaTheme.glassOverlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: MingaTheme.accentGreen,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notification,
                      style: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          backgroundColor: MingaTheme.transparent,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
          ),
        ),
      );
      
      // Update last visit after showing notification
      await activityService.updateLastVisit();
    } else {
      // Update last visit even if no notification
      await activityService.updateLastVisit();
    }
  }

  Future<void> _loadStreamPreviewPlace() async {
    if (_isStreamPreviewLoading) return;
    setState(() {
      _isStreamPreviewLoading = true;
    });
    try {
      final places = await _repository.fetchPlacesPage(
        offset: 0,
        limit: 400,
      );
      if (!mounted) return;

      final location = _locationStore.currentLocation;
      final withDistances = places.map((place) {
        if (place.lat == null || place.lng == null) {
          return place.copyWith(clearDistanceKm: true);
        }
        final distanceKm =
            haversineKm(location.lat, location.lng, place.lat!, place.lng!);
        return place.copyWith(distanceKm: distanceKm);
      }).toList();

      final eligible = withDistances
          .where((place) => place.reviewCount >= 3000)
          .where((place) =>
              place.distanceKm != null && place.distanceKm! <= 20)
          .toList();

      if (eligible.isNotEmpty) {
        eligible.sort((a, b) {
          final scoreA = _streamScore(a);
          final scoreB = _streamScore(b);
          final scoreCompare = scoreB.compareTo(scoreA);
          if (scoreCompare != 0) return scoreCompare;
          return b.reviewCount.compareTo(a.reviewCount);
        });
        setState(() {
          _streamPreviewPlace = eligible.first;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ HomeScreen: Failed to load stream preview: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStreamPreviewLoading = false;
        });
      }
    }
  }

  double _streamScore(Place place) {
    final distanceKm = place.distanceKm;
    if (distanceKm == null) return double.negativeInfinity;
    final reviewsScore = place.reviewCount / 1000.0;
    final distancePenalty = (distanceKm * 20) + (distanceKm * distanceKm * 2);
    return reviewsScore - distancePenalty;
  }

  Future<void> _loadHypePlaces() async {
    if (_isHypeLoading) return;
    setState(() {
      _isHypeLoading = true;
    });
    try {
      final places = await _repository.fetchPlacesPage(
        offset: 0,
        limit: 400,
      );
      if (!mounted) return;
      final location = _locationStore.currentLocation;
      final withDistances = places.map((place) {
        if (place.lat == null || place.lng == null) {
          return place.copyWith(clearDistanceKm: true);
        }
        final distanceKm =
            haversineKm(location.lat, location.lng, place.lat!, place.lng!);
        return place.copyWith(distanceKm: distanceKm);
      }).toList();

      final rooms = withDistances.where((place) => place.socialEnabled).toList();
      final inRange = rooms
          .where(
              (place) => place.distanceKm != null && place.distanceKm! <= _hypeMaxDistanceKm)
          .toList()
        ..sort(_compareHypePlaces);

      var selected = inRange.take(_hypeLimit).toList();
      if (selected.isEmpty) {
        final fallback = List<Place>.from(rooms)
          ..sort(PlaceRepository.compareByDistanceNullable);
        selected = fallback.take(_hypeLimit).toList();
      }
      setState(() {
        _hypePlaces = selected;
      });
      await _attachHypeRoomMediaAndChats(selected);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ HomeScreen: Failed to load hype places: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isHypeLoading = false;
        });
      }
    }
  }

  int _compareHypePlaces(Place a, Place b) {
    final rankA = _repository.getActivityRank(a);
    final rankB = _repository.getActivityRank(b);
    if (rankA != rankB) return rankB.compareTo(rankA);
    final liveCompare = b.liveCount.compareTo(a.liveCount);
    if (liveCompare != 0) return liveCompare;
    final ratingCompare = b.ratingCount.compareTo(a.ratingCount);
    if (ratingCompare != 0) return ratingCompare;
    return PlaceRepository.compareByDistanceNullable(a, b);
  }

  Future<void> _attachHypeRoomMediaAndChats(List<Place> places) async {
    final roomIds = places.map((place) => place.chatRoomId).toList();
    final activeRooms = roomIds.toSet();
    for (final entry in _hypeMessageSubscriptions.entries.toList()) {
      if (!activeRooms.contains(entry.key)) {
        entry.value.cancel();
        _hypeMessageSubscriptions.remove(entry.key);
        _hypeMessagesByRoom.remove(entry.key);
      }
    }

    if (!SupabaseGate.isEnabled) {
      if (!mounted) return;
      setState(() {
        for (final place in places) {
          _hypeMessagesByRoom[place.chatRoomId] = place.chatPreview;
        }
      });
      return;
    }

    final mediaMap = await _chatRepository.fetchRoomLatestMedia(roomIds);
    if (!mounted) return;
    setState(() {
      _hypeMediaByRoom
        ..clear()
        ..addAll(mediaMap);
    });

    for (final place in places) {
      final roomId = place.chatRoomId;
      if (_hypeMessageSubscriptions.containsKey(roomId)) continue;
      _hypeMessageSubscriptions[roomId] = _chatRepository
          .watchMessages(roomId, limit: 5)
          .listen((messages) {
        if (!mounted) return;
        final trimmed = messages
            .where((message) => message.text.trim().isNotEmpty)
            .toList();
        final latestFive = trimmed.take(5).toList();
        final preview = latestFive
            .reversed
            .map((message) =>
                '${message.userName.trim()}: ${message.text.trim()}')
            .toList();
        setState(() {
          _hypeMessagesByRoom[roomId] = preview;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final sub in _hypeMessageSubscriptions.values) {
      sub.cancel();
    }
    _locationStore.removeListener(_handleLocationChange);
    _locationStore.dispose();
    super.dispose();
  }

  void _handleLocationChange() {
    _loadStreamPreviewPlace();
    _loadHypePlaces();
  }

  Future<void> _loadQuickIntroPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_quickIntroKey) ?? false;
    if (!mounted) return;
    setState(() {
      _showQuickIntro = !dismissed;
    });
  }

  Future<void> _dismissQuickIntro() async {
    setState(() {
      _showQuickIntro = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickIntroKey, true);
  }


  Future<void> _loadDiscoveryCollabs() async {
    try {
      final systemDefs = await SystemCollabsStore.load();
      final systemCollabs = _mapSystemCollabs(systemDefs);

      if (!SupabaseGate.isEnabled) {
        if (mounted) {
          setState(() {
            _publicCollabs = systemCollabs;
            _isCollabLoading = false;
          });
        }
        return;
      }

      final collabs = await _collabsRepository.fetchPublicCollabs();
      final combined = [...systemCollabs, ...collabs];

      final userIds = collabs.map((list) => list.ownerId).toSet();
      final profiles = await Future.wait(
        userIds.map((id) => _profileRepository.fetchUserProfile(id)),
      );

      for (final profile in profiles) {
        if (profile != null) {
          _creatorProfiles[profile.id] = profile;
        }
      }

      final counts = await _collabsRepository.fetchCollabSaveCounts(
        collabs.map((collab) => collab.id).toList(),
      );
      _collabSaveCounts.addAll(counts);

      if (mounted) {
        setState(() {
          _publicCollabs = combined;
          _isCollabLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ HomeScreen: Failed to load collabs: $e');
      }
      if (mounted) {
        setState(() {
          _isCollabLoading = false;
        });
      }
    }
  }

  List<Collab> _mapSystemCollabs(List<CollabDefinition> defs) {
    final now = DateTime.now();
    return defs.asMap().entries.map((entry) {
      final index = entry.key;
      final def = entry.value;
      return Collab(
        id: def.id,
        ownerId: 'localspots',
        title: def.title,
        description: def.subtitle,
        isPublic: true,
        coverMediaUrls: const [],
        createdAt: now.subtract(Duration(minutes: index)),
        creatorDisplayName: 'LocalSpots',
        creatorUsername: 'LocalSpots',
        creatorAvatarUrl: null,
        creatorBadge: null,
      );
    }).toList();
  }

  List<Collab> get _popularCollabs {
    final items = List<Collab>.from(_publicCollabs);
    items.sort((a, b) {
      final aSaves = _collabSaveCounts[a.id] ?? 0;
      final bSaves = _collabSaveCounts[b.id] ?? 0;
      final byCount = bSaves.compareTo(aSaves);
      if (byCount != 0) return byCount;
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  List<Collab> get _newestCollabs {
    final items = List<Collab>.from(_publicCollabs);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Widget _buildCollabSection({
    required String title,
    required List<Collab> collabs,
    required CollabsExploreFilter filter,
  }) {
    final limited = collabs.take(6).toList();
    return CollabCarousel(
      title: title,
      isLoading: _isCollabLoading,
      emptyText: 'Noch keine Collabs verfügbar',
      onSeeAll: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CollabsExploreScreen(
              initialFilter: filter,
            ),
          ),
        );
      },
      itemCount: limited.length,
      itemBuilder: (context, index) {
        final collab = limited[index];
        if (kDebugMode && index < 3) {
          debugPrint(
            '🟣 HomeCarousel creatorLabel collab=${collab.id} name=${_resolveCreatorLabel(collab)}',
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            right: index == limited.length - 1 ? 0 : 16,
          ),
          child: _buildCollabCard(collab, collabs: limited),
        );
      },
    );
  }

  Widget _buildCollabCard(
    Collab collab, {
    required List<Collab> collabs,
  }) {
    final profile = _creatorProfiles[collab.ownerId];
    final creatorLabel = _resolveCreatorLabel(collab);
    final creatorAvatar = _resolveCreatorAvatar(collab);
    final mediaUrls = collab.coverMediaUrls;
    final collabIds = collabs.map((item) => item.id).toList();
    final initialIndex = collabIds.indexOf(collab.id);

    return CollabCard(
      title: collab.title,
      username: creatorLabel,
      avatarUrl: creatorAvatar,
      creatorId: collab.ownerId,
      creatorBadge: profile?.badge ?? collab.creatorBadge,
      mediaUrls: mediaUrls,
      imageUrl: mediaUrls.isNotEmpty ? mediaUrls.first : null,
      gradientKey: 'mint',
      onCreatorTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CreatorProfileScreen(userId: collab.ownerId),
          ),
        );
      },
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CollabDetailScreen(
              collabId: collab.id,
              collabIds: collabIds,
              initialIndex: initialIndex < 0 ? 0 : initialIndex,
            ),
          ),
        );
      },
    );
  }

  String _resolveCreatorLabel(Collab collab) {
    final profile = _creatorProfiles[collab.ownerId];
    return CreatorLabelResolver.resolve(
      displayName: profile?.displayName ?? collab.creatorDisplayName,
      username: profile?.username ?? collab.creatorUsername,
    );
  }

  String? _resolveCreatorAvatar(Collab collab) {
    final profile = _creatorProfiles[collab.ownerId];
    return profile?.avatarUrl ?? collab.creatorAvatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 12),
                _buildHomeHeader(),
                SizedBox(height: 20),
                _buildHeroStreamCard(),
                if (_showQuickIntro) ...[
                  SizedBox(height: 16),
                  _buildQuickIntroCard(),
                ],
                SizedBox(height: 28),
                _buildCollabSection(
                  title: 'Beliebte Collabs',
                  collabs: _popularCollabs,
                  filter: CollabsExploreFilter.popular,
                ),
                SizedBox(height: 28),
                _buildCollabSection(
                  title: 'Neue Collabs',
                  collabs: _newestCollabs,
                  filter: CollabsExploreFilter.newest,
                ),
                SizedBox(height: 36),
                _buildSectionTitle("Gerade angesagt"),
                SizedBox(height: 16),
                _buildHypeCarousel(context),
                SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildHomeHeader() {
    return AnimatedBuilder(
      animation: _locationStore,
      builder: (context, _) {
        final location = _locationStore.currentLocation;
        return Row(
          children: [
            _buildLogoMark(),
            SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _openLocationSheet(context, location),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.place,
                      size: 14,
                      color: MingaTheme.textSubtle,
                    ),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        location.label,
                        overflow: TextOverflow.ellipsis,
                        style: MingaTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        );
      },
    );
  }

  Widget _buildLogoMark() {
    return Text(
      'Mingalive',
      style: MingaTheme.titleSmall.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }

  void _openLocationSheet(BuildContext context, AppLocation location) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MingaTheme.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            child: Container(
              color: MingaTheme.surface,
              child: LocationPickerSheet(locationStore: _locationStore),
            ),
          ),
        );
      },
    );
  }


  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: MingaTheme.titleSmall,
    );
  }

  Widget _buildHeroStreamCard() {
    final preview = _streamPreviewPlace;
    final previewName = preview?.name;
    return GestureDetector(
      onTap: () {
        if (preview != null) {
          MainShell.of(context)?.openPlaceChat(preview.id);
          return;
        }
        widget.onStreamTap?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MingaTheme.cardRadius),
          boxShadow: MingaTheme.cardShadowStrong,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MingaTheme.cardRadius),
          child: Stack(
            children: [
              Positioned.fill(
                child: PlaceImage(
                  imageUrl: preview?.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        MingaTheme.darkOverlaySoft,
                        MingaTheme.darkOverlayStrong,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: MingaTheme.accentGreenSoft,
                            borderRadius:
                                BorderRadius.circular(MingaTheme.chipRadius),
                            border: Border.all(
                              color: MingaTheme.accentGreenBorderStrong,
                            ),
                          ),
                          child: Text(
                            'NÄCHSTER RAUM',
                            style: MingaTheme.label.copyWith(
                              color: MingaTheme.accentGreen,
                            ),
                          ),
                        ),
                        if (_isStreamPreviewLoading) ...[
                          SizedBox(width: 10),
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MingaTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 14),
                    Text(
                      previewName == null || previewName.isEmpty
                          ? 'Räume in deiner Nähe'
                          : previewName,
                      style: MingaTheme.titleMedium,
                    ),
                    SizedBox(height: 6),
                    Text(
                      previewName == null || previewName.isEmpty
                          ? 'Wir suchen gerade einen Live‑Room.'
                          : 'Tippe, um beizutreten.',
                      style: MingaTheme.bodySmall,
                    ),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            if (preview != null) {
                              MainShell.of(context)?.openPlaceChat(preview.id);
                              return;
                            }
                            widget.onStreamTap?.call();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MingaTheme.hotOrange,
                            foregroundColor: MingaTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(MingaTheme.radiusMd),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Stream öffnen',
                            style: MingaTheme.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Tippen zum Öffnen',
                          style: MingaTheme.textMuted,
                        ),
                      ],
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

  Widget _buildQuickIntroCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'So funktioniert Minga',
                    style: MingaTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: _dismissQuickIntro,
                  icon: Icon(Icons.close, color: MingaTheme.textSubtle),
                ),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: const [
                Expanded(
                  child: _IntroItem(
                    icon: Icons.play_circle_fill,
                    title: 'Stream',
                    subtitle: 'Swipe Live‑Orte',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _IntroItem(
                    icon: Icons.collections_bookmark,
                    title: 'Collabs',
                    subtitle: 'Listen von Creators',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _IntroItem(
                    icon: Icons.search,
                    title: 'Discovery',
                    subtitle: 'Suche & Ideen',
                  ),
                ),
              ],
            ),
          ],
      ),
    );
  }

  Widget _buildHypeCarousel(BuildContext context) {
    if (_isHypeLoading && _hypePlaces.isEmpty) {
      return SizedBox(
        height: 210,
        child: Center(
          child: CircularProgressIndicator(color: MingaTheme.accentGreen),
        ),
      );
    }
    if (_hypePlaces.isEmpty) {
      return Text(
        'Aktuell keine aktiven Chatrooms in deiner Nähe.',
        style: MingaTheme.bodySmall.copyWith(color: MingaTheme.textSubtle),
      );
    }
    return SizedBox(
      height: 360,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: _hypePlaces.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final place = _hypePlaces[index];
          final mediaUrl =
              _hypeMediaByRoom[place.chatRoomId] ?? place.imageUrl;
          final messages =
              _hypeMessagesByRoom[place.chatRoomId] ?? place.chatPreview;
          return _HypeRoomCard(
            place: place,
            mediaUrl: mediaUrl,
            messages: messages,
            onTap: () => MainShell.of(context)?.openPlaceChat(place.id),
          );
        },
      ),
    );
  }

}

class _IntroItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _IntroItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: MingaTheme.accentGreen, size: 22),
        SizedBox(height: 6),
        Text(
          title,
          style: MingaTheme.textMuted.copyWith(
            color: MingaTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: MingaTheme.bodySmall.copyWith(
            color: MingaTheme.textSubtle,
          ),
        ),
      ],
    );
  }
}

class _HypeRoomCard extends StatelessWidget {
  final Place place;
  final String? mediaUrl;
  final List<String> messages;
  final VoidCallback onTap;

  const _HypeRoomCard({
    required this.place,
    required this.mediaUrl,
    required this.messages,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 260,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MingaTheme.radiusLg),
          child: Stack(
            children: [
              Positioned.fill(
                child: PlaceImage(
                  imageUrl: mediaUrl ?? place.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        MingaTheme.transparent,
                        MingaTheme.darkOverlaySoft,
                        MingaTheme.darkOverlayStrong,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MingaTheme.titleSmall.copyWith(
                        color: MingaTheme.textPrimary,
                        shadows: [
                          Shadow(
                            color: MingaTheme.darkOverlay,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ChatPreviewList(
                      messages: messages,
                      fallback: place.shortStatus,
                    ),
                  const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatPreviewList extends StatelessWidget {
  final List<String> messages;
  final String? fallback;

  const _ChatPreviewList({
    required this.messages,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final hasMessages = messages.isNotEmpty;
    final lastMessages = hasMessages
        ? (messages.length > 5
            ? messages.sublist(messages.length - 5)
            : messages)
        : <String>[
            (fallback?.isNotEmpty == true) ? fallback! : 'Noch keine Chats',
          ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lastMessages.map((text) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MingaTheme.bodySmall.copyWith(
              color: MingaTheme.textSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }
}
