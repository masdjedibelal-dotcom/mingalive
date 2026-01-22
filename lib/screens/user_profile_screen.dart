import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';
import '../services/supabase_profile_repository.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_gate.dart';
import '../widgets/collab_grid.dart';
import 'collab_detail_screen.dart';

/// Screen showing another user's profile
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final SupabaseProfileRepository _profileRepository = SupabaseProfileRepository();
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  UserProfile? _profile;
  List<Collab> _collabs = [];
  Map<String, int> _saveCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadCollabs();
  }

  Future<void> _loadProfile() async {
    if (!SupabaseGate.isEnabled) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final profile = await _profileRepository.fetchUserProfile(widget.userId);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ UserProfileScreen: Failed to load profile: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCollabs() async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    try {
      final collabs = await _collabsRepository.fetchCollabsByOwner(
        ownerId: widget.userId,
        isPublic: true,
      );
      final saveCounts = await _collabsRepository.fetchCollabSaveCounts(
        collabs.map((collab) => collab.id).toList(),
      );
      if (mounted) {
        setState(() {
          _collabs = collabs;
          _saveCounts = saveCounts;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ UserProfileScreen: Failed to load collabs: $e');
      }
    }
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
          'Profil',
          style: MingaTheme.titleMedium,
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: MingaTheme.accentGreen,
              ),
            )
          : _profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off,
                          size: 64,
                          color: MingaTheme.textSubtle,
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Profil nicht gefunden',
                          style: MingaTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      // Avatar
                      GlassSurface(
                        radius: 999,
                        blurSigma: 18,
                        overlayColor: MingaTheme.glassOverlay,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: MingaTheme.transparent,
                          backgroundImage: _profile!.avatar != null &&
                                  _profile!.avatar!.isNotEmpty
                              ? NetworkImage(_profile!.avatar!)
                              : null,
                          child:
                              _profile!.avatar == null || _profile!.avatar!.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      size: 60,
                                      color: MingaTheme.textPrimary,
                                    )
                                  : null,
                        ),
                      ),
                      SizedBox(height: 24),
                      // Name
                      Text(
                        _profile!.name.trim().isEmpty
                            ? 'Unbekannter Benutzer'
                            : _profile!.name,
                        style: MingaTheme.titleLarge,
                      ),
                      if (_profile!.bio != null &&
                          _profile!.bio!.trim().isNotEmpty) ...[
                      SizedBox(height: 8),
                        Text(
                          _profile!.bio!.trim(),
                          textAlign: TextAlign.center,
                          style: MingaTheme.textMuted.copyWith(
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                      SizedBox(height: 24),
                      _buildBadgesSection(),
                      SizedBox(height: 24),
                      // Public favorite lists section
                      _buildPublicListsSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBadgesSection() {
    if (_collabs.isEmpty) {
      return SizedBox.shrink();
    }

    final totalSaves =
        _saveCounts.values.fold<int>(0, (sum, value) => sum + value);
    final badgeLabels = _buildBadgeLabels(
      publicCount: _collabs.length,
      totalSaves: totalSaves,
      hasRecent: _hasRecentCollab(_collabs, const Duration(days: 30)),
    );
    if (badgeLabels.isEmpty) {
      return SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: badgeLabels.map(_buildBadgeChip).toList(),
    );
  }

  Widget _buildPublicListsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Öffentliche Collabs',
          style: MingaTheme.titleMedium,
        ),
        SizedBox(height: 16),
        if (_collabs.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.collections_bookmark,
                  size: 48,
                  color: MingaTheme.textSubtle,
                ),
                SizedBox(height: 16),
                Text(
                  'Keine öffentlichen Collabs',
                  style: MingaTheme.textMuted,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          CollabGrid(
            collabs: _collabs,
            creatorName: (_) => _profile?.name ?? '',
            creatorAvatarUrl: (_) => _profile?.avatar,
            creatorId: (collab) => collab.ownerId,
            saveCounts: _saveCounts,
            emptyText: 'Keine öffentlichen Collabs',
            onCollabTap: (collab) => _openCollabDetail(collab),
            onCreatorTap: (collab) {},
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
        ),
      ],
    );
  }

  void _openCollabDetail(Collab collab) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CollabDetailScreen(
          collabId: collab.id,
          collabIds: _collabs.map((item) => item.id).toList(),
          initialIndex: _collabs.indexOf(collab),
        ),
      ),
    );
  }

  bool _hasRecentCollab(List<Collab> collabs, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return collabs.any((collab) => collab.createdAt.isAfter(cutoff));
  }

  List<String> _buildBadgeLabels({
    required int publicCount,
    required int totalSaves,
    required bool hasRecent,
  }) {
    final labels = <String>[];
    if (publicCount >= 3) {
      labels.add('Local Curator');
    }
    if (totalSaves >= 10) {
      labels.add('Top Collector');
    }
    if (hasRecent) {
      labels.add('Munich Insider');
    }
    return labels;
  }

  Widget _buildBadgeChip(String label) {
    return GlassSurface(
      radius: 18,
      blurSigma: 16,
      overlayColor: MingaTheme.glassOverlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: MingaTheme.textMuted.copyWith(
            color: MingaTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

}







