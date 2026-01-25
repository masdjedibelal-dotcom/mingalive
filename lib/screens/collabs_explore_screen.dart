import 'package:flutter/material.dart';
import 'theme.dart';
import '../services/auth_service.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_profile_repository.dart';
import '../services/supabase_favorites_repository.dart';
import '../services/supabase_gate.dart';
import '../data/place_repository.dart';
import '../data/system_collabs.dart';
import '../widgets/collab_card.dart';
import '../widgets/collab_carousel.dart';
import '../theme/app_theme_extensions.dart';
import '../models/collab.dart';
import '../models/place.dart';
import '../utils/bottom_nav_padding.dart';
import 'collab_detail_screen.dart';
import 'creator_profile_screen.dart';
import 'collab_create_screen.dart';

enum CollabsExploreFilter { popular, newest, following }

class CollabsExploreScreen extends StatefulWidget {
  final CollabsExploreFilter initialFilter;

  const CollabsExploreScreen({
    super.key,
    this.initialFilter = CollabsExploreFilter.popular,
  });

  @override
  State<CollabsExploreScreen> createState() => _CollabsExploreScreenState();
}

class _CollabsExploreScreenState extends State<CollabsExploreScreen> {
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  final SupabaseFavoritesRepository _favoritesRepository =
      SupabaseFavoritesRepository();
  final PlaceRepository _placeRepository = PlaceRepository();
  bool _isLoading = true;
  bool _isSystemLoading = true;
  bool _isFollowedSystemLoading = true;
  CollabsExploreFilter _activeFilter = CollabsExploreFilter.popular;
  final Map<String, int> _saveCounts = {};
  final Map<String, UserProfile> _creatorProfiles = {};
  List<Collab> _publicCollabs = [];
  List<Collab> _savedCollabs = [];
  List<CollabDefinition> _systemCollabs = [];
  List<CollabDefinition> _followedSystemCollabs = [];
  final Map<String, List<String>> _fallbackMediaByCollabId = {};

  List<CollabDefinition> get _eventSystemCollabs {
    return _systemCollabs
        .where((collab) => collab.id == 'events_this_week')
        .toList();
  }

  List<CollabDefinition> get _nearbySystemCollabs {
    return _systemCollabs
        .where((collab) => collab.id != 'events_this_week')
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (!SupabaseGate.isEnabled) {
        if (mounted) {
          setState(() {
            _publicCollabs = [];
            _savedCollabs = [];
            _isLoading = false;
          });
        }
        return;
      }

      _publicCollabs = await _collabsRepository.fetchPublicCollabs();

      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        _savedCollabs =
            await _collabsRepository.fetchSavedCollabs(userId: currentUser.id);
      }

      final userIds = _publicCollabs.map((list) => list.ownerId).toSet();
      final profiles = await Future.wait(
        userIds.map((id) => _profileRepository.fetchUserProfileLite(id)),
      );
      for (final profile in profiles) {
        if (profile != null) {
          _creatorProfiles[profile.id] = profile;
        }
      }

      final counts = await _collabsRepository.fetchCollabSaveCounts(
        _publicCollabs.map((collab) => collab.id).toList(),
      );
      _saveCounts.addAll(counts);
      _systemCollabs = await SystemCollabsStore.load();
      if (currentUser != null) {
        _followedSystemCollabs =
            await _loadFollowedSystemCollabs(currentUser.id);
      }
    } catch (_) {
      // keep defaults on error
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isSystemLoading = false;
        _isFollowedSystemLoading = false;
      });
    }
    await _loadFallbackMediaForCollabs();
    await _loadFallbackMediaForSystemCollabs();
  }

  Future<List<CollabDefinition>> _loadFollowedSystemCollabs(
    String userId,
  ) async {
    try {
      final lists = await _favoritesRepository.fetchCollabLists(userId: userId);
      if (lists.isEmpty) return [];
      await SystemCollabsStore.load();
      final matched = <String, CollabDefinition>{};
      for (final list in lists) {
        final collab = SystemCollabsStore.findByTitle(list.collabTitle);
        if (collab != null) {
          matched[collab.id] = collab;
        }
      }
      return matched.values.toList();
    } catch (_) {
      return [];
    }
  }

  List<Collab> get _filteredCollabs {
    switch (_activeFilter) {
      case CollabsExploreFilter.popular:
        final items = List<Collab>.from(_publicCollabs);
        items.sort((a, b) {
          final aSaves = _saveCounts[a.id] ?? 0;
          final bSaves = _saveCounts[b.id] ?? 0;
          final bySaves = bSaves.compareTo(aSaves);
          if (bySaves != 0) return bySaves;
          return b.createdAt.compareTo(a.createdAt);
        });
        return items;
      case CollabsExploreFilter.newest:
        final items = List<Collab>.from(_publicCollabs);
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return items;
      case CollabsExploreFilter.following:
        return List<Collab>.from(_savedCollabs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collabs = _filteredCollabs;
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: MingaTheme.textPrimary),
        title: Text(
          'Collabs entdecken',
          style: MingaTheme.titleMedium,
        ),
        actions: [
          TextButton.icon(
            onPressed: _openCreateCollab,
            icon: Icon(Icons.add, color: MingaTheme.accentGreen),
            label: Text(
              'Erstellen',
              style: MingaTheme.body.copyWith(
                color: MingaTheme.accentGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: _buildSectionPanel(
              tint: tokens.colors.info.withOpacity(0.04),
              radius: tokens.radius.xl,
              child: _buildSystemCollabSection(
                title: 'In deiner Nähe',
                items: _nearbySystemCollabs,
                isLoading: _isSystemLoading,
                subtitle: 'Kuratiert für deine Umgebung',
                titleIcon: Icons.near_me,
                height: 115,
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _buildSectionPanel(
              tint: tokens.colors.warning.withOpacity(0.04),
              radius: tokens.radius.xl,
              child: _buildSystemCollabSection(
                title: 'Events diese Woche',
                items: _eventSystemCollabs,
                isLoading: _isSystemLoading,
                subtitle: 'Alle kommenden Highlights der Woche',
                titleIcon: Icons.event,
                height: 115,
                emptyText: 'Keine Events diese Woche',
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _buildFilterBar(),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_activeFilter == CollabsExploreFilter.following)
            SliverToBoxAdapter(
              child: _buildSectionPanel(
                tint: tokens.colors.surfaceStrong.withOpacity(0.06),
                child: _buildFollowedSystemCollabSection(),
              ),
            ),
          if (_activeFilter == CollabsExploreFilter.following)
            SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                  color: MingaTheme.accentGreen,
                ),
              ),
            )
          else if (collabs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Noch keine Collabs verfügbar.',
                  style: MingaTheme.bodySmall,
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                bottomNavSafePadding(context),
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final collab = collabs[index];
                    final profile = _creatorProfiles[collab.ownerId];
                    final username = profile?.name ?? 'Unbekannt';
                    final fallbackUrls =
                        _fallbackMediaByCollabId[collab.id] ?? const [];
                    final mediaUrls = collab.coverMediaUrls.isNotEmpty
                        ? collab.coverMediaUrls
                        : fallbackUrls;
                    final imageUrl = collab.coverMediaUrls.isNotEmpty
                        ? null
                        : (fallbackUrls.isNotEmpty ? fallbackUrls.first : null);
                    final collabIds = collabs.map((item) => item.id).toList();
                    return CollabCard(
                      title: collab.title,
                      username: username,
                      avatarUrl: profile?.avatar,
                      creatorId: collab.ownerId,
                      creatorBadge: profile?.badge,
                      mediaUrls: mediaUrls,
                      imageUrl: imageUrl,
                      gradientKey: 'mint',
                      onCreatorTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                CreatorProfileScreen(userId: collab.ownerId),
                          ),
                        );
                      },
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CollabDetailScreen(
                              collabId: collab.id,
                              collabIds: collabIds,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: collabs.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: bottomNavSafePadding(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPanel({
    required Widget child,
    Color? tint,
    double? radius,
  }) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: tint ?? tokens.colors.surface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(radius ?? tokens.radius.lg),
        ),
        padding: EdgeInsets.all(tokens.space.s12),
        child: child,
      ),
    );
  }

  Widget _buildFilterBar() {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassSurface(
        radius: tokens.radius.lg,
        blur: tokens.blur.low,
        scrim: tokens.colors.surfaceStrong.withOpacity(0.06),
        borderColor: Colors.transparent,
        padding: EdgeInsets.all(tokens.space.s12),
        child: Row(
          children: [
            _buildChip(
              label: 'Beliebt',
              icon: Icons.trending_up,
              isSelected: _activeFilter == CollabsExploreFilter.popular,
              onTap: () => _setFilter(CollabsExploreFilter.popular),
            ),
            SizedBox(width: 8),
            _buildChip(
              label: 'Neu',
              icon: Icons.fiber_new,
              isSelected: _activeFilter == CollabsExploreFilter.newest,
              onTap: () => _setFilter(CollabsExploreFilter.newest),
            ),
            SizedBox(width: 8),
            _buildChip(
              label: 'Gefolgt',
              icon: Icons.bookmark,
              isSelected: _activeFilter == CollabsExploreFilter.following,
              onTap: () => _setFilter(CollabsExploreFilter.following),
            ),
          ],
        ),
      ),
    );
  }

  void _setFilter(CollabsExploreFilter filter) {
    if (_activeFilter == filter) return;
    setState(() {
      _activeFilter = filter;
    });
  }

  Future<void> _loadFallbackMediaForCollabs() async {
    final collabs = List<Collab>.from(_publicCollabs);
    if (collabs.isEmpty) return;
    final updated = Map<String, List<String>>.from(_fallbackMediaByCollabId);

    for (final collab in collabs) {
      if (collab.coverMediaUrls.isNotEmpty) continue;
      if (updated.containsKey(collab.id)) continue;
      List<Place> places = [];
      final placeIds =
          await _collabsRepository.fetchCollabPlaceIds(collabId: collab.id);
      if (placeIds.isEmpty) continue;
      places = await _placeRepository.fetchPlacesByIds(placeIds);
      places = _orderPlacesByIds(places, placeIds);

      final urls = _extractPlaceImages(places);
      if (urls.isNotEmpty) {
        updated[collab.id] = urls;
      }
    }

    if (!mounted) return;
    setState(() {
      _fallbackMediaByCollabId
        ..clear()
        ..addAll(updated);
    });
  }

  Future<void> _loadFallbackMediaForSystemCollabs() async {
    if (_systemCollabs.isEmpty) return;
    final updated = Map<String, List<String>>.from(_fallbackMediaByCollabId);
    for (final collab in _systemCollabs) {
      if (updated.containsKey(collab.id)) continue;
      final placeIds = collab.spotPoolIds;
      if (placeIds.isEmpty) continue;
      final places = await _placeRepository.fetchPlacesByIds(placeIds);
      final ordered = _orderPlacesByIds(places, placeIds);
      final urls = _extractPlaceImages(ordered);
      if (urls.isNotEmpty) {
        updated[collab.id] = urls;
      }
    }
    if (!mounted) return;
    setState(() {
      _fallbackMediaByCollabId
        ..clear()
        ..addAll(updated);
    });
  }

  Widget _buildSystemCollabSection({
    required String title,
    required List<CollabDefinition> items,
    required bool isLoading,
    String emptyText = 'Noch keine Collabs verfügbar',
    String? subtitle,
    IconData? titleIcon,
    double height = 115,
  }) {
    final limited = items.take(8).toList();
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.all(tokens.space.s2),
      child: CollabCarousel(
        title: title,
        subtitle: subtitle,
        titleIcon: titleIcon,
        isLoading: isLoading,
        emptyText: emptyText,
        onSeeAll: () {},
        showSeeAll: false,
        height: height,
        itemCount: limited.length,
        itemBuilder: (context, index) {
          final collab = limited[index];
          final fallbackUrls = _fallbackMediaByCollabId[collab.id] ?? const [];
          final mediaUrls = fallbackUrls;
          final collabIds = limited.map((item) => item.id).toList();
          final initialIndex = collabIds.indexOf(collab.id);
          return Padding(
            padding: EdgeInsets.only(
              right: index == limited.length - 1 ? 0 : 16,
            ),
            child: CollabCard(
              title: collab.title,
              username: collab.creatorName,
              avatarUrl: collab.creatorAvatarUrl,
              creatorId: collab.creatorId,
              creatorBadge: null,
              activityLabel: null,
              activityColor: null,
              aspectRatio: 16 / 10,
              mediaUrls: mediaUrls,
              imageUrl:
                  mediaUrls.isNotEmpty ? mediaUrls.first : collab.heroImageUrl,
              gradientKey: collab.gradientKey,
              onCreatorTap: () {},
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildFollowedSystemCollabSection() {
    if (_isFollowedSystemLoading) {
      return CollabCarousel(
        title: 'Gefolgt',
        subtitle: 'Deine System‑Listen',
        titleIcon: Icons.bookmark,
        isLoading: true,
        emptyText: '',
        onSeeAll: () {},
        showSeeAll: false,
        height: 115,
        itemCount: 0,
        itemBuilder: (_, __) => const SizedBox.shrink(),
      );
    }
    if (_followedSystemCollabs.isEmpty) {
      return const SizedBox.shrink();
    }
    final items = _followedSystemCollabs;
    return CollabCarousel(
      title: 'Gefolgt',
      subtitle: 'Deine System‑Listen',
      titleIcon: Icons.bookmark,
      isLoading: false,
      emptyText: '',
      onSeeAll: () {},
      showSeeAll: false,
      height: 115,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final collab = items[index];
        final fallbackUrls = _fallbackMediaByCollabId[collab.id] ?? const [];
        final mediaUrls = fallbackUrls;
        final collabIds = items.map((item) => item.id).toList();
        final initialIndex = collabIds.indexOf(collab.id);
        return Padding(
          padding: EdgeInsets.only(
            right: index == items.length - 1 ? 0 : 16,
          ),
          child: CollabCard(
            title: collab.title,
            username: collab.creatorName,
            avatarUrl: collab.creatorAvatarUrl,
            creatorId: collab.creatorId,
            creatorBadge: null,
            activityLabel: null,
            activityColor: null,
            aspectRatio: 16 / 10,
            mediaUrls: mediaUrls,
            imageUrl:
                mediaUrls.isNotEmpty ? mediaUrls.first : collab.heroImageUrl,
            gradientKey: collab.gradientKey,
            onCreatorTap: () {},
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
          ),
        );
      },
    );
  }

  List<Place> _orderPlacesByIds(List<Place> places, List<String> ids) {
    final map = {for (final place in places) place.id: place};
    return ids.map((id) => map[id]).whereType<Place>().toList();
  }

  List<String> _extractPlaceImages(List<Place> places) {
    final urls = <String>[];
    for (final place in places) {
      final url = place.imageUrl.trim();
      if (url.isEmpty) continue;
      urls.add(url);
      if (urls.length >= 5) break;
    }
    return urls;
  }

  Future<void> _openCreateCollab() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einloggen, um einen Collab zu erstellen.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const CollabCreateScreen(),
      ),
    );
    if (!mounted || created != true) return;
    setState(() {
      _isLoading = true;
      _publicCollabs = [];
      _savedCollabs = [];
      _saveCounts.clear();
      _creatorProfiles.clear();
    });
    await _loadData();
  }


  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MingaTheme.motionStandard,
        curve: MingaTheme.motionCurve,
        child: GlassSurface(
          radius: MingaTheme.chipRadius,
          blurSigma: 12,
          overlayColor: isSelected
              ? MingaTheme.glassOverlayStrong
              : MingaTheme.glassOverlaySoft,
          borderColor: Colors.transparent,
          boxShadow: isSelected ? MingaTheme.cardShadow : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? MingaTheme.accentGreen
                      : MingaTheme.textSubtle,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: MingaTheme.label.copyWith(
                    color: isSelected
                        ? MingaTheme.accentGreen
                        : MingaTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

