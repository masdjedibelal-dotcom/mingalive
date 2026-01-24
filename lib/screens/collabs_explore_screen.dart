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
          SliverToBoxAdapter(child: _buildSystemCollabSection()),
          SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildChip(
                    label: 'Popular',
                    isSelected: _activeFilter == CollabsExploreFilter.popular,
                    onTap: () => _setFilter(CollabsExploreFilter.popular),
                  ),
                  SizedBox(width: 8),
                  _buildChip(
                    label: 'New',
                    isSelected: _activeFilter == CollabsExploreFilter.newest,
                    onTap: () => _setFilter(CollabsExploreFilter.newest),
                  ),
                  SizedBox(width: 8),
                  _buildChip(
                    label: 'Following',
                    isSelected: _activeFilter == CollabsExploreFilter.following,
                    onTap: () => _setFilter(CollabsExploreFilter.following),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_activeFilter == CollabsExploreFilter.following)
            SliverToBoxAdapter(
              child: _buildFollowedSystemCollabSection(),
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
        ],
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

  Widget _buildSystemCollabSection() {
    final items = _systemCollabs.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CollabCarousel(
        title: 'In deiner Nähe',
        isLoading: _isSystemLoading,
        emptyText: 'Noch keine Collabs verfügbar',
        onSeeAll: () {},
        showSeeAll: false,
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
              mediaUrls: mediaUrls,
              imageUrl: mediaUrls.isNotEmpty ? mediaUrls.first : collab.heroImageUrl,
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: CollabCarousel(
          title: 'Gefolgt',
          isLoading: true,
          emptyText: '',
          onSeeAll: () {},
          showSeeAll: false,
          itemCount: 0,
          itemBuilder: (_, __) => const SizedBox.shrink(),
        ),
      );
    }
    if (_followedSystemCollabs.isEmpty) {
      return const SizedBox.shrink();
    }
    final items = _followedSystemCollabs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CollabCarousel(
        title: 'Gefolgt',
        isLoading: false,
        emptyText: '',
        onSeeAll: () {},
        showSeeAll: false,
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
          blurSigma: 14,
          overlayColor: isSelected
              ? MingaTheme.glassOverlayStrong
              : MingaTheme.glassOverlay,
          borderColor:
              isSelected ? MingaTheme.borderStrong : MingaTheme.borderSubtle,
          boxShadow: isSelected ? MingaTheme.cardShadow : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: MingaTheme.label.copyWith(
                color:
                    isSelected ? MingaTheme.accentGreen : MingaTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

