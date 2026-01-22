import 'package:flutter/material.dart';
import 'theme.dart';
import '../services/auth_service.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_profile_repository.dart';
import '../services/supabase_gate.dart';
import '../widgets/collab_card.dart';
import 'collab_detail_screen.dart';
import 'creator_profile_screen.dart';

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
  bool _isLoading = true;
  CollabsExploreFilter _activeFilter = CollabsExploreFilter.popular;
  final Map<String, int> _saveCounts = {};
  final Map<String, UserProfile> _creatorProfiles = {};
  List<Collab> _publicCollabs = [];
  List<Collab> _savedCollabs = [];

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _loadData();
  }

  Future<void> _loadData() async {
    if (!SupabaseGate.isEnabled) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
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
    } catch (_) {
      // keep defaults on error
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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
      ),
      body: Column(
        children: [
          SizedBox(height: 8),
          Padding(
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
          SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: MingaTheme.accentGreen,
                    ),
                  )
                : collabs.isEmpty
                    ? Center(
                        child: Text(
                          'Noch keine Collabs verfügbar.',
                          style: MingaTheme.bodySmall,
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        itemCount: collabs.length,
                        itemBuilder: (context, index) {
                          final collab = collabs[index];
                          final profile = _creatorProfiles[collab.ownerId];
                          final username = profile?.name ?? 'Unbekannt';
                          final mediaUrls = collab.coverMediaUrls;
                          final collabIds =
                              collabs.map((item) => item.id).toList();
                          return CollabCard(
                            title: collab.title,
                            username: username,
                            avatarUrl: profile?.avatar,
                            creatorId: collab.ownerId,
                            creatorBadge: profile?.badge,
                            mediaUrls: mediaUrls,
                            imageUrl: mediaUrls.isNotEmpty ? mediaUrls.first : null,
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

