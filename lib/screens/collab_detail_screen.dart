import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'theme.dart';
import '../data/collabs.dart';
import '../data/place_repository.dart';
import '../models/collab.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/supabase_favorites_repository.dart';
import '../services/supabase_gate.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_profile_repository.dart';
import '../widgets/place_list_tile.dart';
import '../widgets/media/media_carousel.dart';
import '../widgets/media/media_viewer.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_text_field.dart';
import '../widgets/glass/glass_bottom_sheet.dart';
import 'add_spots_to_collab_sheet.dart';
import 'detail_screen.dart';
import 'main_shell.dart';
import 'creator_profile_screen.dart';
import 'collab_edit_screen.dart';

class CollabDetailScreen extends StatefulWidget {
  final String collabId;
  final List<String> collabIds;
  final int initialIndex;

  const CollabDetailScreen({
    super.key,
    required this.collabId,
    this.collabIds = const [],
    this.initialIndex = 0,
  });

  @override
  State<CollabDetailScreen> createState() => _CollabDetailScreenState();
}

class _CollabPlacesPayload {
  final List<Place> places;
  final Map<String, String> notes;

  const _CollabPlacesPayload({
    required this.places,
    required this.notes,
  });
}

class _CollabShareData {
  final String title;
  final String description;
  final String creator;
  final String? heroImageUrl;
  final int? spotCount;

  const _CollabShareData({
    required this.title,
    required this.description,
    required this.creator,
    this.heroImageUrl,
    this.spotCount,
  });
}

class _CollabDetailScreenState extends State<CollabDetailScreen> {
  static const int _noteMaxChars = 120;
  final PlaceRepository _repository = PlaceRepository();
  final SupabaseFavoritesRepository _favoritesRepository =
      SupabaseFavoritesRepository();
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  late final List<String> _collabIds;
  int _currentIndex = 0;

  final Map<String, FavoriteList?> _followedLists = {};
  final Map<String, bool> _isFollowLoadingById = {};
  final Map<String, bool> _isTogglingFollowById = {};
  final Map<String, String?> _titleOverrides = {};
  final Map<String, String?> _descriptionOverrides = {};
  final Map<String, bool> _isPublicById = {};
  final Map<String, Collab> _collabDataById = {};
  final Map<String, UserProfile> _creatorProfilesById = {};
  final Map<String, List<CollabMediaItem>> _mediaItemsById = {};
  final Map<String, Map<String, String>> _localNotesByCollabId = {};
  final Map<String, Map<String, String>> _supabaseNotesByCollabId = {};
  final Set<String> _expandedNoteKeys = {};

  @override
  void initState() {
    super.initState();
    _collabIds = widget.collabIds.isNotEmpty
        ? widget.collabIds
        : [widget.collabId];
    _currentIndex = widget.initialIndex.clamp(0, _collabIds.length - 1);

    for (final collabId in _collabIds) {
      final collab = _findCollab(collabId);
      if (collab != null) {
        _initCollabStateFor(collabId, collab);
      }
      _loadCollabDataFor(collabId);
    }
    _loadFollowStateFor(_collabIds[_currentIndex]);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: MingaTheme.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.ios_share, color: MingaTheme.textPrimary),
            onPressed: () => _showShareSheet(_collabIds[_currentIndex]),
          ),
        ],
      ),
      body: _buildCollabContent(_collabIds[_currentIndex]),
    );
  }

  CollabDefinition? _findCollab(String id) {
    for (final collab in collabDefinitions) {
      if (collab.id == id) {
        return collab;
      }
    }
    return null;
  }

  Future<void> _loadFollowStateFor(String collabId) async {
    final collab = _findCollab(collabId);
    if (collab == null || !SupabaseGate.isEnabled) {
      if (mounted) {
        setState(() {
          _isFollowLoadingById[collabId] = false;
        });
      }
      return;
    }

    setState(() {
      _isFollowLoadingById[collabId] = true;
    });

    final list = await _favoritesRepository.fetchCollabList(
      title: collab.title,
    );

    if (mounted) {
      setState(() {
        _followedLists[collabId] = list;
        _isFollowLoadingById[collabId] = false;
      });
    }
  }

  Widget _buildMissingCollab() {
    return Center(
      child: Text(
        'Sammlung nicht gefunden',
        style: MingaTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildHero(String collabId, CollabDefinition collab) {
    final ownerId =
        _collabDataById[collabId]?.ownerId ?? collab.creatorId;
    final isOwner = _isOwnerById(ownerId);
    final title = _titleOverrides[collabId] ?? collab.title;
    final description = _descriptionOverrides[collabId] ?? collab.subtitle;
    final mediaItems = _mediaItemsById[collabId] ?? const [];

    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildMediaCarousel(
              items: mediaItems,
              gradientKey: 'mint',
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MingaTheme.transparent,
                      MingaTheme.darkOverlay,
                      MingaTheme.darkOverlayStrong,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: MingaTheme.titleLarge.copyWith(height: 1.2),
                      ),
                      SizedBox(height: 8),
                      _buildCreatorRow(collab),
                      SizedBox(height: 6),
                      Text(
                        description,
                        style: MingaTheme.textMuted.copyWith(
                          color: MingaTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                isOwner
                    ? _buildEditButton(collabId, collab)
                    : _buildFollowButton(collabId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorRow(CollabDefinition collab) {
    final avatarUrl = collab.creatorAvatarUrl?.trim();
    final username = _creatorLabel(collab.creatorName);

    return GestureDetector(
      onTap: () => _openCreatorProfile(collab.creatorId),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: MingaTheme.darkOverlay,
            backgroundImage:
                avatarUrl == null || avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Icon(
                    Icons.person,
                    size: 14,
                    color: MingaTheme.textSecondary,
                  )
                : null,
          ),
          SizedBox(width: 8),
          Text(
            'von $username',
            style: MingaTheme.textMuted.copyWith(
            color: MingaTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(String collabId) {
    final isFollowed = _followedLists[collabId] != null;
    final isLoading = _isFollowLoadingById[collabId] ?? true;
    final isToggling = _isTogglingFollowById[collabId] ?? false;
    return TextButton(
      onPressed: isLoading || isToggling
          ? null
          : () => _toggleFollow(collabId),
      style: TextButton.styleFrom(
        foregroundColor: isFollowed
            ? MingaTheme.buttonLightForeground
            : MingaTheme.textPrimary,
        backgroundColor:
            isFollowed ? MingaTheme.buttonLightBackground : MingaTheme.glassOverlaySoft,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
          side: BorderSide(
            color: isFollowed
                ? MingaTheme.buttonLightBackground
                : MingaTheme.borderEmphasis,
          ),
        ),
      ),
      child: Text(
        isLoading
            ? '...'
            : isFollowed
                ? 'Gefolgt'
                : 'Folgen',
        style: MingaTheme.textMuted.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildEditButton(String collabId, CollabDefinition collab) {
    return TextButton.icon(
      onPressed: () => _openEditCollab(collabId, collab),
      style: TextButton.styleFrom(
        foregroundColor: MingaTheme.textPrimary,
        backgroundColor: MingaTheme.glassOverlaySoft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
          side: BorderSide(color: MingaTheme.borderEmphasis),
        ),
      ),
      icon: Icon(Icons.edit, size: 16),
      label: Text(
        'Bearbeiten',
        style: MingaTheme.body.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSupabaseEditButton(String collabId, Collab collab) {
    return TextButton.icon(
      onPressed: () async {
        final result = await Navigator.of(context).push<CollabEditResult>(
          MaterialPageRoute(
            builder: (context) => CollabEditScreen(
              collabId: collabId,
              ownerId: collab.ownerId,
              initialTitle: collab.title,
              initialDescription: collab.description ?? '',
              initialIsPublic: collab.isPublic,
            ),
          ),
        );

        if (!mounted || result == null) return;
        setState(() {
          _titleOverrides[collabId] = result.title;
          _descriptionOverrides[collabId] = result.description;
          _isPublicById[collabId] = result.isPublic;
        });
      },
      style: TextButton.styleFrom(
        foregroundColor: MingaTheme.textPrimary,
        backgroundColor: MingaTheme.glassOverlaySoft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
          side: BorderSide(color: MingaTheme.borderEmphasis),
        ),
      ),
      icon: Icon(Icons.edit, size: 16),
      label: Text(
        'Bearbeiten',
        style: MingaTheme.body.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  String _creatorLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'User';
    }
    return trimmed;
  }

  Future<void> _showShareSheet(String collabId) async {
    final data = _shareDataFor(collabId);
    final shareUrl = _buildShareUrl(collabId, data.title);
    final shareText = _buildShareText(data, shareUrl);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: MingaTheme.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MingaTheme.radiusLg),
        ),
      ),
      builder: (context) {
        return GlassSurface(
          radius: 20,
          blurSigma: 18,
          overlayColor: MingaTheme.glassOverlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collab teilen',
                  style: MingaTheme.titleSmall,
                ),
                SizedBox(height: 6),
                Text(
                  'Deine kuratierte Liste als Share Card.',
                  style: MingaTheme.textMuted,
                ),
                SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome,
                      color: MingaTheme.textPrimary),
                  title: Text(
                    'In Story teilen',
                    style: MingaTheme.body,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _shareCollabCard(
                      data: data,
                      shareText: shareText,
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link,
                      color: MingaTheme.textPrimary),
                  title: Text(
                    'Link kopieren',
                    style: MingaTheme.body,
                  ),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: shareUrl));
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Link kopiert'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.image,
                      color: MingaTheme.textPrimary),
                  title: Text(
                    'Bild speichern',
                    style: MingaTheme.body,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _shareCollabCard(
                      data: data,
                      shareText: shareUrl,
                      imageOnly: true,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _CollabShareData _shareDataFor(String collabId) {
    final collabDefinition = _findCollab(collabId);
    if (collabDefinition != null) {
      final title = _titleOverrides[collabId] ?? collabDefinition.title;
      final description =
          _descriptionOverrides[collabId] ?? collabDefinition.subtitle;
      return _CollabShareData(
        title: title,
        description: description,
        creator: _creatorLabel(collabDefinition.creatorName),
        heroImageUrl: collabDefinition.heroImageUrl,
        spotCount: collabDefinition.limit,
      );
    }
    final collab = _collabDataById[collabId];
    if (collab != null) {
      final creatorProfile = _creatorProfilesById[collab.ownerId];
      final creator = _creatorLabel(_displayNameForProfile(creatorProfile));
      final mediaItems = _mediaItemsById[collabId] ?? const [];
      return _CollabShareData(
        title: collab.title,
        description: collab.description ?? '',
        creator: creator,
        heroImageUrl:
            mediaItems.isNotEmpty ? mediaItems.first.publicUrl : null,
      );
    }
    return const _CollabShareData(
      title: 'Minga Collab',
      description: '',
      creator: 'User',
    );
  }

  String _buildShareUrl(String collabId, String title) {
    final slug = _slugify(title);
    return 'https://mingalive.app/collab/$slug-$collabId';
  }

  String _buildShareText(_CollabShareData data, String url) {
    final buffer = StringBuffer();
    buffer.write('✨ ${data.title}');
    if (data.description.trim().isNotEmpty) {
      buffer.write('\n${data.description.trim()}');
    }
    buffer.write('\nKuratiert von ${data.creator}');
    buffer.write('\n$url');
    return buffer.toString();
  }

  String _slugify(String value) {
    final lowered = value
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ß', 'ss');
    final slug =
        lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll('-', '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _shareCollabCard({
    required _CollabShareData data,
    required String shareText,
    bool imageOnly = false,
  }) async {
    try {
      final bytes = await _renderShareCard(data);
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'collab-share.png',
      );
      await Share.shareXFiles(
        [file],
        text: imageOnly ? null : shareText,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('❌ ShareCard render failed: $error');
      }
      if (!mounted) return;
      if (!imageOnly) {
        await Share.share(shareText);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share Card konnte nicht erstellt werden.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<Uint8List> _renderShareCard(_CollabShareData data) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final key = GlobalKey();

    final heroUrl = data.heroImageUrl?.trim();
    if (heroUrl != null && heroUrl.isNotEmpty) {
      try {
        await precacheImage(NetworkImage(heroUrl), context);
      } catch (_) {
        // Ignore hero image preload failures; fallback to gradient.
      }
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: Material(
            color: MingaTheme.transparent,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: _CollabShareCard(data: data),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 32));
    await WidgetsBinding.instance.endOfFrame;

    final boundaryContext = key.currentContext;
    if (boundaryContext == null) {
      entry.remove();
      throw StateError('Share card context missing');
    }
    final boundary =
        boundaryContext.findRenderObject() as RenderRepaintBoundary;
    await _waitForPaint(boundary);
    if (boundary.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 16));
      await WidgetsBinding.instance.endOfFrame;
      await _waitForPaint(boundary);
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    entry.remove();
    if (byteData == null) {
      throw StateError('Share card image bytes missing');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _waitForPaint(RenderRepaintBoundary boundary) async {
    if (!boundary.debugNeedsPaint) return;
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (boundary.debugNeedsPaint && DateTime.now().isBefore(deadline)) {
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      await completer.future;
    }
  }

  void _openCreatorProfile(String userId) {
    if (userId.trim().isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatorProfileScreen(userId: userId),
      ),
    );
  }

  bool _isOwnerById(String ownerId) {
    final currentUser = AuthService.instance.currentUser;
    return currentUser != null && currentUser.id == ownerId;
  }

  void _initCollabStateFor(String collabId, CollabDefinition collab) {
    _titleOverrides[collabId] = collab.title;
    _descriptionOverrides[collabId] = collab.subtitle;
    _isPublicById[collabId] = false;
  }

  Future<void> _loadCollabDataFor(String collabId) async {
    final collab = await _collabsRepository.fetchCollabById(collabId);
    if (!mounted || collab == null) return;
    setState(() {
      _collabDataById[collabId] = collab;
      _titleOverrides[collabId] = collab.title;
      _descriptionOverrides[collabId] = collab.description ?? '';
      _isPublicById[collabId] = collab.isPublic;
    });
    _loadCreatorProfile(collab.ownerId);
    _loadMediaItemsFor(collabId);
  }

  Future<void> _loadMediaItemsFor(String collabId) async {
    final items = await _collabsRepository.fetchCollabMediaItems(collabId);
    if (!mounted) return;
    setState(() {
      _mediaItemsById[collabId] = items;
    });
  }

  Future<void> _loadCreatorProfile(String userId) async {
    if (_creatorProfilesById.containsKey(userId)) return;
    final cached = _profileRepository.getCachedProfile(userId);
    if (cached != null) {
      _creatorProfilesById[userId] = cached;
      return;
    }
    final profile = await _profileRepository.fetchUserProfileLite(userId);
    if (!mounted || profile == null) return;
    setState(() {
      _creatorProfilesById[userId] = profile;
    });
  }

  String _displayNameForProfile(UserProfile? profile) {
    if (profile == null) return 'User';
    final display = profile.displayName.trim();
    if (display.isNotEmpty) return display;
    return 'User';
  }

  Future<void> _openEditCollab(String collabId, CollabDefinition collab) async {
    final ownerId =
        _collabDataById[collabId]?.ownerId ?? collab.creatorId;
    final result = await Navigator.of(context).push<CollabEditResult>(
      MaterialPageRoute(
        builder: (context) => CollabEditScreen(
          collabId: collabId,
          ownerId: ownerId,
          initialTitle: _titleOverrides[collabId] ?? collab.title,
          initialDescription:
              _descriptionOverrides[collabId] ?? collab.subtitle,
          initialIsPublic: _isPublicById[collabId] ?? false,
        ),
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _titleOverrides[collabId] = result.title;
      _descriptionOverrides[collabId] = result.description;
      _isPublicById[collabId] = result.isPublic;
    });
  }

  Widget _buildCollabContent(String collabId) {
    final collabDefinition = _findCollab(collabId);
    if (collabDefinition != null) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(collabId, collabDefinition),
            _buildOwnerActions(collabId, collabDefinition.creatorId),
            _buildPlacesList(collabDefinition),
          ],
        ),
      );
    }

    final collab = _collabDataById[collabId];
    if (collab == null) {
      return _buildMissingCollab();
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSupabaseHero(collabId, collab),
          _buildOwnerActions(collabId, collab.ownerId),
          _buildSupabasePlacesList(collabId),
        ],
      ),
    );
  }

  Widget _buildOwnerActions(String collabId, String ownerId) {
    final isOwner = _isOwnerById(ownerId);
    if (!isOwner) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: GlassButton(
          variant: GlassButtonVariant.ghost,
          icon: Icons.add,
          label: 'Spot hinzufügen',
          onPressed: () => _showAddSpotsSheet(collabId),
        ),
      ),
    );
  }

  Widget _buildSupabaseHero(String collabId, Collab collab) {
    final creatorProfile = _creatorProfilesById[collab.ownerId];
    final username = _creatorLabel(_displayNameForProfile(creatorProfile));
    final avatarUrl = creatorProfile?.avatarUrl?.trim();
    final mediaItems = _mediaItemsById[collabId] ?? [];

    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildMediaCarousel(
              items: mediaItems,
              gradientKey: 'mint',
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MingaTheme.transparent,
                      MingaTheme.darkOverlay,
                      MingaTheme.darkOverlayStrong,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        collab.title,
                        style: MingaTheme.titleLarge.copyWith(height: 1.2),
                      ),
                      SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _openCreatorProfile(collab.ownerId),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: MingaTheme.darkOverlay,
                              backgroundImage: avatarUrl == null || avatarUrl.isEmpty
                                  ? null
                                  : NetworkImage(avatarUrl),
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? Icon(Icons.person,
                                      size: 14,
                                      color: MingaTheme.textSecondary)
                                  : null,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'von $username',
                              style: MingaTheme.textMuted.copyWith(
                                color: MingaTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((collab.description ?? '').trim().isNotEmpty) ...[
                        SizedBox(height: 6),
                        Text(
                          collab.description!.trim(),
                          style: MingaTheme.textMuted.copyWith(
                            color: MingaTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12),
                _isOwnerById(collab.ownerId)
                    ? _buildSupabaseEditButton(collabId, collab)
                    : _buildFollowButton(collabId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupabasePlacesList(String collabId) {
    return FutureBuilder<_CollabPlacesPayload>(
      future: _fetchSupabasePlacesPayload(collabId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: MingaTheme.accentGreen,
            ),
          );
        }

        final payload = snapshot.data;
        final places = payload?.places ?? [];
        final notes = payload?.notes ?? {};
        if (places.isEmpty) {
          return Center(
            child: Text(
              'Keine Orte verfügbar',
              style: MingaTheme.body.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          );
        }

        final limitedPlaces =
            places.length > 20 ? places.take(20).toList() : places;

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: limitedPlaces.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            final place = limitedPlaces[index];
            return PlaceListTile(
              place: place,
              note: notes[place.id],
              isNoteExpanded:
                  _expandedNoteKeys.contains(_noteKey(collabId, place.id)),
              onToggleNote: () => _toggleNote(collabId, place.id),
              onEditNote: () => _showPlaceNoteSheet(
                collabId: collabId,
                placeId: place.id,
                initialNote: notes[place.id],
                isSupabase: true,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DetailScreen(
                      placeId: place.id,
                      openPlaceChat: (placeId) {
                        MainShell.of(context)?.openPlaceChat(placeId);
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<Place>> _fetchSupabaseCollabPlaces(String collabId) async {
    final placeIds =
        await _collabsRepository.fetchCollabPlaceIds(collabId: collabId);
    if (placeIds.isEmpty) return [];
    final places = await Future.wait(
      placeIds.map((id) => _repository.fetchById(id)),
    );
    final resolved = places.whereType<Place>().toList();
    resolved.sort((a, b) {
      final aActive = a.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bActive = b.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final activeCompare = bActive.compareTo(aActive);
      if (activeCompare != 0) return activeCompare;
      return PlaceRepository.compareByDistanceNullable(a, b);
    });
    return resolved;
  }

  Future<_CollabPlacesPayload> _fetchSupabasePlacesPayload(
    String collabId,
  ) async {
    final places = await _fetchSupabaseCollabPlaces(collabId);
    final notes =
        await _collabsRepository.fetchCollabPlaceNotes(collabId: collabId);
    _supabaseNotesByCollabId[collabId] = notes;
    return _CollabPlacesPayload(places: places, notes: notes);
  }

  Future<void> _showAddSpotsSheet(String collabId) async {
    final added = await showAddSpotsToCollabSheet(
      context: context,
      collabId: collabId,
    );
    if (!mounted || !added) return;
    setState(() {});
  }

  void _openMediaViewer(int initialIndex, List<CollabMediaItem> items) {
    if (items.isEmpty) return;
    final viewerItems = items
        .map(
          (item) => MediaCarouselItem(
            url: item.publicUrl,
            isVideo: item.kind == 'video',
          ),
        )
        .toList();
    MediaViewer.show(
      context,
      items: viewerItems,
      initialIndex: initialIndex,
      muted: true,
    );
  }

  Widget _buildMediaCarousel({
    required List<CollabMediaItem> items,
    String? gradientKey,
  }) {
    final carouselItems = items
        .map(
          (item) => MediaCarouselItem(
            url: item.publicUrl,
            isVideo: item.kind == 'video',
          ),
        )
        .toList();
    return MediaCarousel(
      items: carouselItems,
      gradientKey: gradientKey,
      onExpand: (index) => _openMediaViewer(index, items),
    );
  }

  Widget _buildPlacesList(CollabDefinition collab) {
    return FutureBuilder<List<Place>>(
      future: _repository.fetchPlacesForCollab(collab),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: MingaTheme.accentGreen,
            ),
          );
        }

        final places = snapshot.data ?? [];
        if (places.isEmpty) {
          return Center(
            child: Text(
              'Keine Orte verfügbar',
              style: MingaTheme.body.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          );
        }

        final limitedPlaces = places.length > collab.limit
            ? places.take(collab.limit).toList()
            : places;
        final notes = _localNotesByCollabId[collab.id] ?? {};

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: limitedPlaces.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            final place = limitedPlaces[index];
            return PlaceListTile(
              place: place,
              note: notes[place.id],
              isNoteExpanded:
                  _expandedNoteKeys.contains(_noteKey(collab.id, place.id)),
              onToggleNote: () => _toggleNote(collab.id, place.id),
              onEditNote: () => _showPlaceNoteSheet(
                collabId: collab.id,
                placeId: place.id,
                initialNote: notes[place.id],
                isSupabase: false,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DetailScreen(
                      placeId: place.id,
                      openPlaceChat: (placeId) {
                        MainShell.of(context)?.openPlaceChat(placeId);
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _noteKey(String collabId, String placeId) => '$collabId::$placeId';

  void _toggleNote(String collabId, String placeId) {
    final key = _noteKey(collabId, placeId);
    setState(() {
      if (_expandedNoteKeys.contains(key)) {
        _expandedNoteKeys.remove(key);
      } else {
        _expandedNoteKeys.add(key);
      }
    });
  }

  Future<void> _showPlaceNoteSheet({
    required String collabId,
    required String placeId,
    required String? initialNote,
    required bool isSupabase,
  }) async {
    final controller = TextEditingController(text: initialNote ?? '');
    final focusNode = FocusNode();

    await showGlassBottomSheet(
      context: context,
      isScrollControlled: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Notiz', style: MingaTheme.titleSmall),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: MingaTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: 8),
            GlassTextField(
              controller: controller,
              focusNode: focusNode,
              hintText: 'Kurze Notiz zum Spot…',
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              onChanged: (value) {
                if (value.length <= _noteMaxChars) return;
                final trimmed = value.substring(0, _noteMaxChars);
                controller.value = controller.value.copyWith(
                  text: trimmed,
                  selection: TextSelection.collapsed(offset: trimmed.length),
                );
              },
            ),
            SizedBox(height: 8),
            Text(
              '${controller.text.length}/$_noteMaxChars',
              style: MingaTheme.bodySmall.copyWith(color: MingaTheme.textSubtle),
            ),
            SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: GlassButton(
                variant: GlassButtonVariant.primary,
                label: 'Speichern',
                onPressed: () async {
                  final note = controller.text.trim();
                  try {
                    if (isSupabase) {
                      await _collabsRepository.updateCollabPlaceNote(
                        collabId: collabId,
                        placeId: placeId,
                        note: note,
                      );
                      final notes = _supabaseNotesByCollabId[collabId] ?? {};
                      if (note.isEmpty) {
                        notes.remove(placeId);
                      } else {
                        notes[placeId] = note;
                      }
                      _supabaseNotesByCollabId[collabId] = notes;
                    } else {
                      final notes = _localNotesByCollabId[collabId] ?? {};
                      if (note.isEmpty) {
                        notes.remove(placeId);
                      } else {
                        notes[placeId] = note;
                      }
                      _localNotesByCollabId[collabId] = notes;
                    }
                    if (!mounted) return;
                    setState(() {});
                    Navigator.of(context).pop();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notiz konnte nicht gespeichert werden'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    focusNode.dispose();
  }

  Future<void> _toggleFollow(String collabId) async {
    final collab = _findCollab(collabId);
    if (collab == null) return;

    if (!SupabaseGate.isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Favoriten-Collabs sind nur mit Supabase verfügbar.'),
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
            content: Text('Bitte einloggen, um zu folgen.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isTogglingFollowById[collabId] = true;
    });

    if (_followedLists[collabId] != null) {
      await _favoritesRepository.deleteFavoriteList(
        listId: _followedLists[collabId]!.id,
      );
      if (mounted) {
        setState(() {
          _followedLists[collabId] = null;
          _isTogglingFollowById[collabId] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sammlung entfernt'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final list = await _favoritesRepository.ensureCollabList(
      title: collab.title,
      subtitle: collab.subtitle,
    );

    if (mounted) {
      setState(() {
        _followedLists[collabId] = list;
        _isTogglingFollowById[collabId] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            list == null ? 'Fehler beim Folgen' : 'Sammlung gespeichert',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _CollabShareCard extends StatelessWidget {
  final _CollabShareData data;

  const _CollabShareCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final heroUrl = data.heroImageUrl?.trim();
    return SizedBox(
      width: 1080,
      height: 1920,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: MingaTheme.shareGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          image: heroUrl != null && heroUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(heroUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    MingaTheme.darkOverlay,
                    BlendMode.darken,
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SharePill(
                text: 'MINGA COLLAB',
                color: MingaTheme.glowGreen,
              ),
              SizedBox(height: 48),
              Text(
                data.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MingaTheme.displayLarge.copyWith(
                  fontSize: 86,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.05,
                ),
              ),
              SizedBox(height: 28),
              if (data.description.trim().isNotEmpty)
                Text(
                  data.description.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: MingaTheme.titleMedium.copyWith(
                    color: MingaTheme.textSecondary,
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (data.spotCount != null && data.spotCount! > 0)
                    _ShareBadge(text: '${data.spotCount} Spots'),
                  _ShareBadge(text: 'Kuratiert'),
                  _ShareBadge(text: 'Lokal'),
                ],
              ),
              const Spacer(),
              Text(
                'Kuratiert von ${data.creator}',
                style: MingaTheme.titleMedium.copyWith(
                  color: MingaTheme.textSecondary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'minga.live',
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharePill extends StatelessWidget {
  final String text;
  final Color color;

  const _SharePill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(MingaTheme.radiusXl),
        border: Border.all(color: color.withOpacity(0.8), width: 2),
      ),
      child: Text(
        text,
        style: MingaTheme.label.copyWith(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ShareBadge extends StatelessWidget {
  final String text;

  const _ShareBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: MingaTheme.glassOverlaySoft,
        borderRadius: BorderRadius.circular(MingaTheme.radiusLg),
        border: Border.all(color: MingaTheme.borderStrong),
      ),
      child: Text(
        text,
        style: MingaTheme.body.copyWith(
          color: MingaTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

