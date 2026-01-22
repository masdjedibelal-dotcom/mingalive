import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';
import '../models/app_user.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/supabase_gate.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_profile_repository.dart';
import '../data/place_repository.dart';
import 'creator_profile_screen.dart';
import 'detail_screen.dart';
import 'main_shell.dart';
import 'collab_create_screen.dart';
import 'collab_edit_screen.dart';
import 'collab_detail_screen.dart';
import '../widgets/collab_grid.dart';
import '../widgets/place_grid.dart';

/// User profile screen with authentication
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  Future<UserProfile?>? _profileFuture;
  UserProfile? _currentProfile;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _avatarUrlOverride;
  String? _avatarCacheBuster;
  String? _lastUserId;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _loadProfile(String userId) {
    if (!SupabaseGate.isEnabled) {
      _profileFuture = Future.value(null);
      return;
    }
    if (_lastUserId != userId || _profileFuture == null) {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        _profileRepository.ensureProfileRow(
          userId: currentUser.id,
          name: currentUser.name,
          avatarUrl: currentUser.photoUrl,
        );
      }
      _profileFuture = _profileRepository.fetchUserProfile(userId);
      _lastUserId = userId;
    }
  }

  void _refreshProfile(String userId) {
    if (!SupabaseGate.isEnabled) {
      _profileFuture = Future.value(null);
      return;
    }
    final currentUser = AuthService.instance.currentUser;
    if (currentUser != null) {
      _profileRepository.ensureProfileRow(
        userId: currentUser.id,
        name: currentUser.name,
        avatarUrl: currentUser.photoUrl,
      );
    }
    _profileFuture = _profileRepository.fetchUserProfile(userId);
    _lastUserId = userId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: SafeArea(
        child: ValueListenableBuilder<AppUser?>(
          valueListenable: AuthService.instance.currentUserNotifier,
          builder: (context, currentUser, _) {
            if (currentUser != null) {
              _loadProfile(currentUser.id);
            }
            if (currentUser == null) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: _buildLoggedOutView(context),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Expanded(
                    child: _buildLoggedInView(context, currentUser),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoggedOutView(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 60),
        // Avatar Circle
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                MingaTheme.accentGreen,
                MingaTheme.accentGreenBorderStrong,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: MingaTheme.avatarGlowShadow,
          ),
          child: Center(
            child: Icon(
              Icons.person,
              size: 60,
              color: MingaTheme.textPrimary,
            ),
          ),
        ),
        SizedBox(height: 40),
        Text(
          "Nicht angemeldet",
          style: MingaTheme.titleMedium,
        ),
        SizedBox(height: 8),
        Text(
          "Melde dich an, um dein Profil zu sehen",
          style: MingaTheme.textMuted.copyWith(fontSize: 15),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 40),
        // Login mit Google Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (!SupabaseGate.isEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Supabase noch nicht konfiguriert. Bitte Demo Login verwenden.'),
                    duration: Duration(seconds: 3),
                    backgroundColor: MingaTheme.warningOrange,
                  ),
                );
                return;
              }

              AuthService.instance.signInWithGoogle().catchError((e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Fehler beim Google Login: $e'),
                      duration: const Duration(seconds: 3),
                      backgroundColor: MingaTheme.dangerRed,
                    ),
                  );
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MingaTheme.buttonLightBackground,
              foregroundColor: MingaTheme.buttonLightForeground,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.login, size: 24);
                  },
                ),
                SizedBox(width: 12),
                Text('Login mit Google', style: MingaTheme.body),
              ],
            ),
          ),
        ),
        SizedBox(height: 16),
        // Demo Login Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              AuthService.instance.signInMock().catchError((e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Fehler beim Demo Login: $e'),
                      duration: const Duration(seconds: 3),
                      backgroundColor: MingaTheme.dangerRed,
                    ),
                  );
                }
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: MingaTheme.accentGreen,
              side: BorderSide(color: MingaTheme.accentGreen, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
              ),
            ),
            child: Text(
              SupabaseGate.isEnabled
                  ? 'Demo Login (Supabase)'
                  : 'Demo Login',
              style: MingaTheme.body,
            ),
          ),
        ),
        SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLoggedInView(BuildContext context, AppUser currentUser) {
    final collabsRepository = SupabaseCollabsRepository();
    final placeRepository = PlaceRepository();
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        final bio = profile?.bio?.trim();
        final hasBio = bio != null && bio.isNotEmpty;
        _currentProfile = profile;
        final displayName = profile?.displayLabel ?? 'User';
        final avatarUrl = _avatarUrlOverride ??
            ((profile?.avatarUrl?.trim().isNotEmpty == true)
                ? profile?.avatarUrl
                : currentUser.photoUrl);
        final displayAvatarUrl = _withCacheBuster(avatarUrl, _avatarCacheBuster);

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              SizedBox(height: 20),
              // Avatar
              GestureDetector(
                onTap: _isEditing ? () => _pickAvatar(currentUser.id) : null,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: MingaTheme.accentGreen,
                      backgroundImage:
                          displayAvatarUrl != null && displayAvatarUrl.isNotEmpty
                              ? NetworkImage(displayAvatarUrl)
                          : null,
                      child: displayAvatarUrl == null || displayAvatarUrl.isEmpty
                          ? Icon(
                              Icons.person,
                              size: 60,
                              color: MingaTheme.textPrimary,
                            )
                          : null,
                    ),
                    if (_isEditing)
                      Container(
                        margin: const EdgeInsets.only(right: 4, bottom: 4),
                        child: GlassSurface(
                          radius: 999,
                          blurSigma: 16,
                          overlayColor: MingaTheme.glassOverlay,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: MingaTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              // Name
              Text(
                displayName,
                style: MingaTheme.titleLarge,
              ),
              if (_isEditing) ...[
                SizedBox(height: 12),
                GlassSurface(
                  radius: 16,
                  blurSigma: 16,
                  overlayColor: MingaTheme.glassOverlayXSoft,
                  child: TextField(
                    controller: _displayNameController,
                    style: MingaTheme.body,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
                      filled: true,
                      fillColor: MingaTheme.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                GlassSurface(
                  radius: 16,
                  blurSigma: 16,
                  overlayColor: MingaTheme.glassOverlayXSoft,
                  child: TextField(
                    controller: _bioController,
                    style: MingaTheme.body,
                    maxLength: 160,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Bio',
                      labelStyle: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
                      hintText: 'Kurz über dich…',
                      hintStyle: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
                      filled: true,
                      fillColor: MingaTheme.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _saveProfile(currentUser.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MingaTheme.accentGreen,
                    ),
                    child:
                        Text(_isSaving ? 'Speichern…' : 'Änderungen speichern'),
                  ),
                ),
                SizedBox(height: 12),
              ] else if (hasBio) ...[
                SizedBox(height: 8),
                Text(
                  bio,
                  textAlign: TextAlign.center,
                  style: MingaTheme.textMuted.copyWith(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _toggleEditing(profile),
                    child: Text(
                      _isEditing ? 'Abbrechen' : 'Profil bearbeiten',
                      style: MingaTheme.bodySmall.copyWith(
                        color: MingaTheme.accentGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!_isEditing) ...[
                    SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () async {
                      final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => const CollabCreateScreen(),
                        ),
                      );
                      if (!mounted || created != true) return;
                      setState(() {});
                    },
                      icon: Icon(
                        Icons.add,
                        color: MingaTheme.accentGreen,
                        size: 18,
                      ),
                      label: Text(
                        'Collab erstellen',
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.accentGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 20),
              FutureBuilder<List<List<Collab>>>(
                future: Future.wait([
                  collabsRepository.fetchCollabsByOwner(
                    ownerId: currentUser.id,
                    isPublic: true,
                  ),
                  collabsRepository.fetchCollabsByOwner(
                    ownerId: currentUser.id,
                    isPublic: false,
                  ),
                  collabsRepository.fetchSavedCollabs(userId: currentUser.id),
                ]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(
                        color: MingaTheme.accentGreen,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Fehler beim Laden der Collabs',
                        style: MingaTheme.textMuted,
                      ),
                    );
                  }

                  final results = snapshot.data ?? [[], [], []];
                  final publicCollabs = results[0];
                  final privateCollabs = results[1];
                  final savedCollabs = results[2];

                  final allCollabs = [
                    ...publicCollabs,
                    ...privateCollabs,
                    ...savedCollabs,
                  ];
                  final saveCountsFuture = allCollabs.isEmpty
                      ? Future.value(<String, int>{})
                      : collabsRepository.fetchCollabSaveCounts(
                          allCollabs.map((collab) => collab.id).toList(),
                        );

                  return FutureBuilder<Map<String, int>>(
                    future: saveCountsFuture,
                    builder: (context, saveSnapshot) {
                      final saveCounts = saveSnapshot.data ?? {};
                      final totalSaves = publicCollabs.fold<int>(
                        0,
                        (sum, collab) => sum + (saveCounts[collab.id] ?? 0),
                      );
                      final badgeLabels = _buildBadgeLabels(
                        publicCount: publicCollabs.length,
                        totalSaves: totalSaves,
                        hasRecent: _hasRecentCollab(
                          publicCollabs,
                          const Duration(days: 30),
                        ),
                      );

                      return Expanded(
                        child: Column(
                          children: [
                            if (badgeLabels.isNotEmpty) ...[
                              _buildBadgesRow(badgeLabels),
                              SizedBox(height: 16),
                            ],
                            TabBar(
                              indicatorColor: MingaTheme.accentGreen,
                              labelColor: MingaTheme.textPrimary,
                              unselectedLabelColor:
                                  MingaTheme.textSubtle,
                              labelStyle: MingaTheme.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              tabs: const [
                                Tab(text: 'Meine Collabs (Public)'),
                                Tab(text: 'Meine Collabs (Private)'),
                                Tab(text: 'Gespeicherte Collabs'),
                                Tab(text: 'Gespeicherte Orte'),
                              ],
                            ),
                            SizedBox(height: 12),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  CollabGrid(
                                    collabs: publicCollabs,
                                    creatorName: (_) => currentUser.name,
                                    creatorAvatarUrl: (_) => currentUser.photoUrl,
                                    creatorId: (collab) => collab.ownerId,
                                    saveCounts: saveCounts,
                                    emptyText:
                                        'Öffentliche Collabs sind für alle sichtbar und können entdeckt werden.',
                                    onCollabTap: (collab) => _openCollabDetail(
                                      publicCollabs,
                                      publicCollabs.indexOf(collab),
                                    ),
                                    onCreatorTap: (collab) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreatorProfileScreen(
                                            userId: collab.ownerId,
                                          ),
                                        ),
                                      );
                                    },
                                    showEditIcon: (collab) =>
                                        collab.ownerId == currentUser.id,
                                    onEditTap: (collab) async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => CollabEditScreen(
                                            collabId: collab.id,
                                            ownerId: collab.ownerId,
                                            initialTitle: collab.title,
                                            initialDescription:
                                                collab.description ?? '',
                                            initialIsPublic: collab.isPublic,
                                          ),
                                        ),
                                      );
                                      _refreshProfile(currentUser.id);
                                    },
                                  ),
                                  CollabGrid(
                                    collabs: privateCollabs,
                                    creatorName: (_) => currentUser.name,
                                    creatorAvatarUrl: (_) => currentUser.photoUrl,
                                    creatorId: (collab) => collab.ownerId,
                                    saveCounts: saveCounts,
                                    emptyText:
                                        'Private Collabs siehst nur du, sie bleiben verborgen.',
                                    onCollabTap: (collab) => _openCollabDetail(
                                      privateCollabs,
                                      privateCollabs.indexOf(collab),
                                    ),
                                    onCreatorTap: (collab) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreatorProfileScreen(
                                            userId: collab.ownerId,
                                          ),
                                        ),
                                      );
                                    },
                                    showEditIcon: (collab) =>
                                        collab.ownerId == currentUser.id,
                                    onEditTap: (collab) async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => CollabEditScreen(
                                            collabId: collab.id,
                                            ownerId: collab.ownerId,
                                            initialTitle: collab.title,
                                            initialDescription:
                                                collab.description ?? '',
                                            initialIsPublic: collab.isPublic,
                                          ),
                                        ),
                                      );
                                      _refreshProfile(currentUser.id);
                                    },
                                  ),
                                  CollabGrid(
                                    collabs: savedCollabs,
                                    creatorName: (_) => '',
                                    creatorAvatarUrl: (_) => null,
                                    creatorId: (collab) => collab.ownerId,
                                    saveCounts: saveCounts,
                                    emptyText:
                                        'Gespeicherte Collabs sind Sammlungen, denen du folgst.',
                                    onCollabTap: (collab) => _openCollabDetail(
                                      savedCollabs,
                                      savedCollabs.indexOf(collab),
                                    ),
                                    onCreatorTap: (collab) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreatorProfileScreen(
                                            userId: collab.ownerId,
                                          ),
                                        ),
                                      );
                                    },
                                    showEditIcon: (_) => false,
                                  ),
                                  FutureBuilder<List<Place>>(
                                    future: placeRepository.fetchFavorites(
                                      userId: currentUser.id,
                                    ),
                                    builder: (context, placesSnapshot) {
                                      if (placesSnapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return Center(
                                          child: CircularProgressIndicator(
                                            color: MingaTheme.accentGreen,
                                          ),
                                        );
                                      }

                                      if (placesSnapshot.hasError) {
                                        return Center(
                                          child: Text(
                                            'Fehler beim Laden der Orte',
                                            style: MingaTheme.bodySmall.copyWith(
                                              color: MingaTheme.textSubtle,
                                            ),
                                          ),
                                        );
                                      }

                                      return PlaceGrid(
                                        places: placesSnapshot.data ?? [],
                                        emptyText:
                                            'Gespeicherte Orte sind deine persönlichen Favoriten.',
                                        onPlaceTap: (place) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => DetailScreen(
                                                place: place,
                                                openPlaceChat: (placeId) {
                                                  MainShell.of(context)
                                                      ?.openPlaceChat(placeId);
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openCollabDetail(List<Collab> collabs, int index) {
    if (index < 0 || index >= collabs.length) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CollabDetailScreen(
          collabId: collabs[index].id,
          collabIds: collabs.map((collab) => collab.id).toList(),
          initialIndex: index,
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

  Widget _buildBadgesRow(List<String> labels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: labels.map(_buildBadgeChip).toList(),
    );
  }

  Widget _buildBadgeChip(String label) {
    return GlassSurface(
      radius: MingaTheme.chipRadius,
      blurSigma: 12,
      overlayColor: MingaTheme.glassOverlayXXSoft,
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

  void _toggleEditing(UserProfile? profile) {
    setState(() {
      _isEditing = !_isEditing;
      if (_isEditing) {
        _bioController.text = profile?.bio?.trim() ?? '';
        _displayNameController.text = profile?.displayName ?? '';
      } else {
        _avatarUrlOverride = null;
      }
    });
  }

  Future<void> _pickAvatar(String userId) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }

    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final filename = file.name.isNotEmpty ? file.name : 'avatar.jpg';
    final url = await _profileRepository.uploadAvatar(
      userId: userId,
      bytes: bytes,
      filename: filename,
    );
    if (!mounted) return;
    if (url != null) {
      await _profileRepository.updateUserProfile(
        userId: userId,
        avatarUrl: url,
      );
      setState(() {
        _avatarUrlOverride = url;
        _avatarCacheBuster =
            DateTime.now().millisecondsSinceEpoch.toString();
      });
    }
  }

  Future<void> _saveProfile(String userId) async {
    if (!SupabaseGate.isEnabled) {
      return;
    }
    setState(() {
      _isSaving = true;
    });

    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();
    final avatarUrl = _avatarUrlOverride;
    final success = await _profileRepository.updateUserProfile(
      userId: userId,
      name: displayName.isEmpty ? null : displayName,
      avatarUrl: avatarUrl,
      bio: bio.isEmpty ? null : bio,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (success) {
        _isEditing = false;
        _avatarUrlOverride = null;
        _profileFuture = Future.value(
          UserProfile(
            id: userId,
            displayName: displayName,
            username: _currentProfile?.username ?? '',
            avatarUrl: avatarUrl,
            bio: bio.isEmpty ? null : bio,
          ),
        );
        _refreshProfile(userId);
      }
    });
  }

  String? _withCacheBuster(String? url, String? buster) {
    if (url == null || url.isEmpty || buster == null || buster.isEmpty) {
      return url;
    }
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$buster';
  }

}
