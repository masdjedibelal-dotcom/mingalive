import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';
import '../services/supabase_profile_repository.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_gate.dart';
import '../widgets/collab_grid.dart';
import 'collab_detail_screen.dart';

class CreatorProfileScreen extends StatefulWidget {
  final String userId;

  const CreatorProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
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
      final profile =
          await _profileRepository.fetchUserProfile(widget.userId);
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ CreatorProfileScreen: Failed to load profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        debugPrint('❌ CreatorProfileScreen: Failed to load collabs: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final username = _usernameLabel(profile?.name ?? '');
    final bio = profile?.bio?.trim();
    final hasBio = bio != null && bio.isNotEmpty;

    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MingaTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: MingaTheme.accentGreen,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        GlassSurface(
                          radius: 999,
                          blurSigma: 18,
                          overlayColor: MingaTheme.glassOverlay,
                          child: CircleAvatar(
                            radius: 42,
                            backgroundColor: MingaTheme.transparent,
                            backgroundImage: _avatarImage(profile?.avatar),
                            child: _avatarImage(profile?.avatar) == null
                                ? Icon(
                                    Icons.person,
                                    color: MingaTheme.textSecondary,
                                  )
                                : null,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          username,
                          style: MingaTheme.titleMedium,
                        ),
                        if (hasBio) ...[
                          SizedBox(height: 8),
                          Text(
                            bio,
                            textAlign: TextAlign.center,
                            style: MingaTheme.textMuted.copyWith(
                              color: MingaTheme.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildBadgesSection(profile),
                  SizedBox(height: 24),
                  Text(
                    'Öffentliche Collabs',
                    style: MingaTheme.titleSmall,
                  ),
                  SizedBox(height: 12),
                  if (_collabs.isEmpty)
                    GlassCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.collections_bookmark,
                            size: 40,
                            color: MingaTheme.textSubtle,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Keine öffentlichen Collabs',
                            style: MingaTheme.textMuted,
                          ),
                        ],
                      ),
                    )
                  else
                    CollabGrid(
                      collabs: _collabs,
                      creatorName: (_) => profile?.name ?? '',
                      creatorAvatarUrl: (_) => profile?.avatar,
                      creatorId: (collab) => collab.ownerId,
                      saveCounts: _saveCounts,
                      emptyText: 'Keine öffentlichen Collabs',
                      onCollabTap: (collab) => _openCollabDetail(collab),
                      onCreatorTap: (collab) {},
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                    ),
                ],
              ),
            ),
    );
  }

  ImageProvider? _avatarImage(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return NetworkImage(trimmed);
  }

  String _usernameLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '@unbekannt';
    }
    return trimmed.startsWith('@') ? trimmed : '@$trimmed';
  }

  Widget _buildBadgesSection(UserProfile? profile) {
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

