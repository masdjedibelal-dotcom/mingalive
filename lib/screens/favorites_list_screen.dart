import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';
import '../models/place.dart';
import '../data/place_repository.dart';
import '../services/auth_service.dart';
import '../services/supabase_favorites_repository.dart';
import '../services/supabase_gate.dart';
import '../services/supabase_profile_repository.dart';
import '../widgets/activity_badge.dart';
import 'detail_screen.dart';
import 'user_profile_screen.dart';

/// Screen showing places in a favorite list
class FavoritesListScreen extends StatefulWidget {
  final FavoriteList list;

  const FavoritesListScreen({
    super.key,
    required this.list,
  });

  @override
  State<FavoritesListScreen> createState() => _FavoritesListScreenState();
}

class _FavoritesListScreenState extends State<FavoritesListScreen> {
  final SupabaseFavoritesRepository _favoritesRepository = SupabaseFavoritesRepository();
  final PlaceRepository _placeRepository = PlaceRepository();
  List<Place> _places = [];
  bool _isLoading = true;
  UserProfile? _creatorProfile;
  FavoriteList? _savedList;
  bool _isSaveLoading = true;
  bool _isTogglingSave = false;
  bool _isPublic = false;
  bool _isUpdatingVisibility = false;
  String _title = '';
  String _description = '';

  @override
  void initState() {
    super.initState();
    _isPublic = widget.list.isPublic;
    _title = widget.list.collabTitle;
    _description = widget.list.description?.trim() ?? '';
    _loadPlaces();
    _loadCreatorProfile();
    _loadSavedState();
  }

  Future<void> _loadPlaces() async {
    if (!SupabaseGate.isEnabled) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final placeIds =
          await _favoritesRepository.fetchPlacesInList(widget.list.id);

      if (placeIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final places = <Place>[];
      for (final placeId in placeIds) {
        try {
          final place = await _placeRepository.fetchById(placeId);
          if (place != null) {
            places.add(place);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ FavoritesListScreen: Failed to load place $placeId: $e',
            );
          }
        }
      }

      places.sort(_comparePlaces);
      final limitedPlaces =
          places.length > 20 ? places.take(20).toList() : places;

      setState(() {
        _places = limitedPlaces;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FavoritesListScreen: Failed to load places: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDescription = _description.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: MingaTheme.accentGreen,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  if (_isOwner)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: SwitchListTile(
                        title: Text(
                          'Collab öffentlich machen',
                          style: MingaTheme.body.copyWith(
                            color: MingaTheme.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Öffentliche Collabs können von anderen entdeckt werden.',
                          style: MingaTheme.bodySmall.copyWith(
                            color: MingaTheme.textSubtle,
                          ),
                        ),
                        value: _isPublic,
                        onChanged: _isUpdatingVisibility
                            ? null
                            : (value) => _toggleVisibility(value),
                      ),
                    ),
                  if (hasDescription)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        _description,
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSecondary,
                        ),
                      ),
                    ),
                  SizedBox(height: 4),
                  Expanded(
                    child: _places.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.favorite_border,
                                    size: 64,
                                    color: MingaTheme.textSubtle,
                                  ),
                                  SizedBox(height: 24),
                                  Text(
                                    'Noch keine Spots in diesem Collab',
                                    style: MingaTheme.titleSmall.copyWith(
                                      color: MingaTheme.textSubtle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            itemCount: _places.length,
                            itemBuilder: (context, index) {
                              final place = _places[index];
                              return _buildSpotCard(context, place);
                            },
                          ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final creatorLabel = _creatorLabel;
    final mediaUrls = _headerMediaUrls;

    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: mediaUrls.isEmpty
                ? _buildGradientPlaceholder()
                : PageView.builder(
                    itemCount: mediaUrls.length,
                    itemBuilder: (context, index) {
                      return Image.network(
                        mediaUrls[index],
                        fit: BoxFit.cover,
                      );
                    },
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
                    MingaTheme.darkOverlay,
                    MingaTheme.darkOverlayStrong,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: MingaTheme.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_isOwner)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: Icon(Icons.edit, color: MingaTheme.textPrimary),
                onPressed: _showEditDialog,
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: MingaTheme.titleLarge.copyWith(height: 1.2),
                ),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: _openCreatorProfile,
                  child: Text(
                    'von $creatorLabel',
                    style: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: MingaTheme.shareGradient.length >= 2
            ? LinearGradient(
                colors: MingaTheme.shareGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
    );
  }

  Widget _buildSpotCard(BuildContext context, Place place) {
    final activityLabel = _activityLabel(place);
    final activityColor = _activityColor(place);

    return GlassSurface(
      radius: 16,
      blurSigma: 16,
      overlayColor: MingaTheme.glassOverlayXXSoft,
      child: InkWell(
        borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DetailScreen(
                placeId: place.id,
                openPlaceChat: (placeId) {},
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                child: Image.network(
                  place.imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 72,
                      height: 72,
                      color: MingaTheme.skeletonFill,
                      child: Icon(
                        Icons.image,
                        color: MingaTheme.textSubtle,
                        size: 32,
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            place.name,
                            style: MingaTheme.titleSmall.copyWith(height: 1.2),
                          ),
                        ),
                        ActivityBadge(
                          label: activityLabel,
                          color: activityColor,
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      place.category,
                      style: MingaTheme.textMuted.copyWith(
                        color: MingaTheme.textSubtle,
                      ),
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

  Widget _buildSaveBar() {
    final isOwner = _isOwner;
    final isSaved = _savedList != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaveLoading || _isTogglingSave || isOwner
                ? null
                : _toggleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isSaved ? MingaTheme.buttonLightBackground : MingaTheme.accentGreen,
              foregroundColor:
                  isSaved ? MingaTheme.buttonLightForeground : MingaTheme.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
              ),
            ),
            child: Text(
              isOwner
                  ? 'Dein Collab'
                  : _isSaveLoading
                      ? '...'
                      : isSaved
                          ? 'Collab entfernen'
                          : 'Collab speichern',
              style: MingaTheme.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadCreatorProfile() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser != null && currentUser.id == widget.list.userId) {
      setState(() {
        _creatorProfile = UserProfile(
          id: currentUser.id,
          name: currentUser.name,
          avatar: currentUser.photoUrl,
        );
      });
      return;
    }

    final profile =
        await SupabaseProfileRepository().fetchUserProfile(widget.list.userId);
    if (mounted) {
      setState(() {
        _creatorProfile = profile;
      });
    }
  }

  Future<void> _loadSavedState() async {
    if (!SupabaseGate.isEnabled) {
      setState(() {
        _isSaveLoading = false;
      });
      return;
    }

    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isSaveLoading = false;
      });
      return;
    }

    if (currentUser.id == widget.list.userId) {
      setState(() {
        _isSaveLoading = false;
      });
      return;
    }

    final saved = await _favoritesRepository.fetchCollabList(
      title: _title,
    );

    if (mounted) {
      setState(() {
        _savedList = saved;
        _isSaveLoading = false;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_isOwner) {
      return;
    }

    if (!SupabaseGate.isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Collabs sind nur mit Supabase verfügbar.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bitte einloggen, um Collabs zu speichern.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isTogglingSave = true;
    });

    if (_savedList != null) {
      await _favoritesRepository.deleteFavoriteList(listId: _savedList!.id);
      if (mounted) {
        setState(() {
          _savedList = null;
          _isTogglingSave = false;
        });
      }
      return;
    }

    final list = await _favoritesRepository.ensureCollabList(
      title: _title,
      subtitle: _description.trim().isNotEmpty
          ? _description.trim()
          : '',
    );

    if (mounted) {
      setState(() {
        _savedList = list;
        _isTogglingSave = false;
      });
    }
  }

  void _openCreatorProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: widget.list.userId),
      ),
    );
  }

  Future<void> _toggleVisibility(bool value) async {
    if (!SupabaseGate.isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Collabs sind nur mit Supabase verfügbar.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null || currentUser.id != widget.list.userId) {
      return;
    }

    setState(() {
      _isUpdatingVisibility = true;
      _isPublic = value;
    });

    await _favoritesRepository.updateFavoriteListVisibility(
      listId: widget.list.id,
      isPublic: value,
    );

    if (mounted) {
      setState(() {
        _isUpdatingVisibility = false;
      });
    }
  }

  void _showEditDialog() {
    final titleController = TextEditingController(text: _title);
    final descriptionController = TextEditingController(text: _description);
    bool isPublic = _isPublic;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: MingaTheme.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                  Text(
                    'Collab bearbeiten',
                    style: MingaTheme.titleMedium,
                  ),
                  SizedBox(height: 16),
                  GlassSurface(
                    radius: 16,
                    blurSigma: 16,
                    overlayColor: MingaTheme.glassOverlayXSoft,
                    child: TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'Titel',
                        labelStyle: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                        filled: true,
                        fillColor: MingaTheme.transparent,
                        border:
                            const OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      style: MingaTheme.body,
                    ),
                  ),
                  SizedBox(height: 16),
                  GlassSurface(
                    radius: 16,
                    blurSigma: 16,
                    overlayColor: MingaTheme.glassOverlayXSoft,
                    child: TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Short description',
                        labelStyle: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                        hintText: 'Why did you create this collection?',
                        hintStyle: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                        filled: true,
                        fillColor: MingaTheme.transparent,
                        border:
                            const OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      style: MingaTheme.body,
                      maxLines: 3,
                      maxLength: 160,
                    ),
                  ),
                  SizedBox(height: 16),
                  GlassSurface(
                    radius: 16,
                    blurSigma: 16,
                    overlayColor: MingaTheme.glassOverlayXSoft,
                    child: SwitchListTile(
                      title: Text(
                        'Collab öffentlich machen',
                        style: MingaTheme.body.copyWith(
                          color: MingaTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Öffentliche Collabs können von anderen entdeckt werden.',
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                      ),
                      value: isPublic,
                      onChanged: (value) {
                        setDialogState(() {
                          isPublic = value;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text('Abbrechen'),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          final description = descriptionController.text.trim();

                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Bitte einen Titel eingeben'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }

                          await _favoritesRepository.updateFavoriteList(
                            listId: widget.list.id,
                            title: title,
                            description: description.isEmpty ? null : description,
                            isPublic: isPublic,
                          );

                          if (!mounted) return;
                          setState(() {
                            _title = title;
                            _description = description;
                            _isPublic = isPublic;
                          });
                          Navigator.of(dialogContext).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MingaTheme.accentGreen,
                        ),
                        child: Text('Speichern'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _comparePlaces(Place a, Place b) {
    final activityComparison = _compareActivity(a, b);
    if (activityComparison != 0) {
      return activityComparison;
    }
    return _compareDistance(a, b);
  }

  int _compareActivity(Place a, Place b) {
    final aTime = a.lastActiveAt;
    final bTime = b.lastActiveAt;
    if (aTime != null || bTime != null) {
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final timeCompare = bTime.compareTo(aTime);
      if (timeCompare != 0) return timeCompare;
    }

    if (a.liveCount != b.liveCount) {
      return b.liveCount.compareTo(a.liveCount);
    }
    if (a.isLive != b.isLive) {
      return a.isLive ? -1 : 1;
    }
    return 0;
  }

  int _compareDistance(Place a, Place b) {
    return PlaceRepository.compareByDistanceNullable(a, b);
  }

  String get _creatorLabel {
    final name = _creatorProfile?.name.trim();
    if (name == null || name.isEmpty) {
      return '@unbekannt';
    }
    return name.startsWith('@') ? name : '@$name';
  }

  List<String> get _headerMediaUrls {
    final urls = <String>[];
    for (final place in _places) {
      final url = place.imageUrl.trim();
      if (url.isNotEmpty) {
        urls.add(url);
      }
      if (urls.length >= 5) break;
    }
    return urls;
  }

  bool get _isOwner =>
      AuthService.instance.currentUser?.id == widget.list.userId;

  String _activityLabel(Place place) {
    if (place.isLive && place.liveCount > 0) {
      return 'Aktiv ${place.liveCount}';
    }
    if (place.isLive || place.liveCount > 0) {
      return 'Aktiv';
    }
    return 'Ruhig';
  }

  Color _activityColor(Place place) {
    if (place.isLive || place.liveCount > 0) {
      return MingaTheme.successGreen;
    }
    return MingaTheme.textSubtle;
  }
}

