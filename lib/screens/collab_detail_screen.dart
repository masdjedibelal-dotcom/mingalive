import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:share_plus/share_plus.dart';
import 'theme.dart';
import '../data/collabs.dart';
import '../data/event_repository.dart';
import '../data/place_repository.dart';
import '../models/collab.dart';
import '../models/event.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
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
import '../widgets/glass/glass_badge.dart';
import '../data/system_collabs.dart';
import '../theme/app_theme_extensions.dart';
import '../theme/app_tokens.dart';
import '../utils/bottom_nav_padding.dart';
import '../utils/distance_utils.dart';
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

enum CollabPlacesView { list, map }

class _CollabDetailScreenState extends State<CollabDetailScreen> {
  static const int _noteMaxChars = 120;
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
  final PlaceRepository _repository = PlaceRepository();
  final EventRepository _eventRepository = EventRepository();
  final SupabaseFavoritesRepository _favoritesRepository =
      SupabaseFavoritesRepository();
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  final LocationService _locationService = LocationService();
  final DistanceCache _distanceCache = DistanceCache();
  Future<LatLng>? _originFuture;
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
  bool _isSystemLoading = true;
  final Map<String, List<String>> _fallbackMediaByCollabId = {};
  gmaps.GoogleMapController? _collabMapController;
  final Map<String, gmaps.BitmapDescriptor> _collabMarkerCache = {};

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
    _loadSystemCollabs();
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
      body: ColoredBox(
        color: MingaTheme.background,
        child: _buildCollabContent(_collabIds[_currentIndex]),
      ),
    );
  }

  CollabDefinition? _findCollab(String id) {
    for (final collab in collabDefinitions) {
      if (collab.id == id) {
        return collab;
      }
    }
    final system = SystemCollabsStore.findById(id);
    if (system != null) return system;
    return null;
  }

  Future<void> _loadSystemCollabs() async {
    await SystemCollabsStore.load();
    if (!mounted) return;
    setState(() {
      _isSystemLoading = false;
    });
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
    final mediaItems = _mediaItemsById[collabId] ?? const [];
    final fallbackUrls = _fallbackMediaByCollabId[collabId] ?? const [];

    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildHeroMedia(
              collabId: collabId,
              items: mediaItems,
              fallbackUrls: fallbackUrls,
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
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: MingaTheme.titleMedium.copyWith(
                    fontSize: 20,
                    height: 1.15,
                    shadows: [
                      Shadow(
                        color: MingaTheme.darkOverlay,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildCreatorRow(collab)),
                    SizedBox(width: 12),
                    isOwner
                        ? _buildEditButton(collabId, collab)
                        : _buildFollowButton(collabId),
                  ],
                ),
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

  Widget _buildDescriptionText(
    String collabId,
    String title,
    String description, {
    int collapsedLines = 2,
  }) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();
    final canExpand = trimmed.length > 140;
    final textStyle = MingaTheme.textMuted.copyWith(
      color: MingaTheme.textSecondary,
      fontSize: 14,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trimmed,
          style: textStyle,
          maxLines: collapsedLines,
          overflow: TextOverflow.ellipsis,
        ),
        if (canExpand) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _showCollabTextSheet(
              title: title,
              description: trimmed,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mehr lesen',
                  style: MingaTheme.bodySmall.copyWith(
                    color: MingaTheme.accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: MingaTheme.accentGreen,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showCollabTextSheet({
    required String title,
    required String description,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedDescription = description.trim();
    if (trimmedTitle.isEmpty && trimmedDescription.isEmpty) return;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    await showGlassBottomSheet(
      context: context,
      isScrollControlled: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
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
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  decoration: BoxDecoration(
                    color: MingaTheme.glassOverlaySoft,
                    borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                    border: Border.all(color: MingaTheme.borderEmphasis),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trimmedTitle.isNotEmpty) ...[
                        Text(
                          trimmedTitle,
                          style: MingaTheme.titleMedium.copyWith(height: 1.2),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 3,
                            height: 48,
                            margin: const EdgeInsets.only(right: 10, top: 2),
                            decoration: BoxDecoration(
                              color: MingaTheme.accentGreen,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              trimmedDescription,
                              style: MingaTheme.textMuted.copyWith(
                                color: MingaTheme.textPrimary,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection(
    String collabId,
    String title,
    String description,
  ) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MingaTheme.glassOverlaySoft,
          borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
          border: Border.all(color: MingaTheme.borderEmphasis),
        ),
        child: _buildDescriptionText(
          collabId,
          title,
          trimmed,
          collapsedLines: 3,
        ),
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
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              24 + bottomNavSafePadding(context),
            ),
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
                      collabId: collabId,
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
                      collabId: collabId,
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
    required String collabId,
    required _CollabShareData data,
    required String shareText,
    bool imageOnly = false,
  }) async {
    try {
      final places = await _fetchSharePlaces(collabId);
      final images = await _renderInstagramShareCards(
        data: data,
        places: places,
      );
      final files = images
          .asMap()
          .entries
          .map(
            (entry) => XFile.fromData(
              entry.value,
              mimeType: 'image/png',
              name: 'collab-share-${entry.key + 1}.png',
            ),
          )
          .toList();
      await Share.shareXFiles(
        files,
        text: imageOnly ? null : shareText,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('❌ ShareCard render failed: $error');
      }
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
      } catch (fallbackError) {
        if (kDebugMode) {
          debugPrint('❌ ShareCard fallback failed: $fallbackError');
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
  }

  Future<List<Place>> _fetchSharePlaces(String collabId) async {
    final collabDefinition = _findCollab(collabId);
    if (collabDefinition != null) {
      return _repository.fetchPlacesForCollab(collabDefinition);
    }
    final payload = await _fetchSupabasePlacesPayload(collabId);
    return payload.places;
  }

  Future<List<Uint8List>> _renderInstagramShareCards({
    required _CollabShareData data,
    required List<Place> places,
  }) async {
    const pageSize = 7;
    final chunks = <List<Place>>[];
    if (places.isEmpty) {
      chunks.add(const []);
    } else {
      for (var i = 0; i < places.length; i += pageSize) {
        chunks.add(places.sublist(i, math.min(i + pageSize, places.length)));
      }
    }

    final images = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      final bytes = await _renderInstagramShareCardPage(
        data: data,
        places: chunks[i],
        pageIndex: i,
        totalPages: chunks.length,
      );
      images.add(bytes);
    }
    return images;
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
    await Future.delayed(const Duration(milliseconds: 48));
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundaryContext = key.currentContext;
      if (boundaryContext == null) {
        throw StateError('Share card context missing');
      }
      final renderObject = boundaryContext.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Share card boundary missing');
      }
      await _waitForPaint(renderObject);
      if (renderObject.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 32));
        await WidgetsBinding.instance.endOfFrame;
        await _waitForPaint(renderObject);
      }
      final deviceRatio = MediaQuery.of(context).devicePixelRatio;
      final candidates = <double>{
        deviceRatio.clamp(1.8, 2.5),
        2.0,
        1.5,
      }.toList()
        ..sort((a, b) => b.compareTo(a));
      Object? lastError;
      for (final ratio in candidates) {
        try {
          return await _captureShareCard(renderObject, ratio);
        } catch (error) {
          lastError = error;
        }
      }
      throw lastError ?? StateError('Share card render failed');
    } finally {
      entry.remove();
    }
  }

  Future<Uint8List> _captureShareCard(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Share card image bytes missing');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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

  Future<Uint8List> _renderInstagramShareCardPage({
    required _CollabShareData data,
    required List<Place> places,
    required int pageIndex,
    required int totalPages,
  }) async {
    const pageSize = 7;
    const width = 1080.0;
    const height = 1350.0;
    const padding = 72.0;
    const coverHeight = 600.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final backgroundRect = const Rect.fromLTWH(0, 0, width, height);
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B0F0C),
          Color(0xFF0C1F15),
          Color(0xFF0B0F0C),
        ],
      ).createShader(backgroundRect);
    canvas.drawRect(backgroundRect, backgroundPaint);

    final heroUrl = data.heroImageUrl?.trim();
    ui.Image? coverImage;
    if (heroUrl != null && heroUrl.isNotEmpty) {
      try {
        coverImage = await _loadNetworkImage(heroUrl);
      } catch (_) {
        coverImage = null;
      }
    }

    if (coverImage != null) {
      final coverRect = const Rect.fromLTWH(0, 0, width, coverHeight);
      paintImage(
        canvas: canvas,
        rect: coverRect,
        image: coverImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      final scrimPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x33000000),
            Color(0xCC0B0F0C),
          ],
        ).createShader(coverRect);
      canvas.drawRect(coverRect, scrimPaint);
    }

    final textWidth = width - (padding * 2);
    double cursorY = coverImage != null ? coverHeight - 210 : padding;

    final titleStyle = const TextStyle(
      color: Colors.white,
      fontSize: 56,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: data.title.trim(), style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: textWidth - 24);
    titlePainter.paint(
      canvas,
      Offset(padding + 24, cursorY),
    );
    cursorY += titlePainter.height + 14;

    final description = data.description.trim();
    if (description.isNotEmpty) {
      final descriptionStyle = const TextStyle(
        color: Color(0xFFDCE2DD),
        fontSize: 30,
        height: 1.35,
      );
      final descriptionPainter = TextPainter(
        text: TextSpan(text: description, style: descriptionStyle),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: textWidth);
      descriptionPainter.paint(canvas, Offset(padding, cursorY));
      cursorY += descriptionPainter.height + 12;
    }

    if (coverImage != null) {
      cursorY = coverHeight + 20;
    }

    final metaParts = <String>[];
    if (data.creator.trim().isNotEmpty) {
      metaParts.add('von ${data.creator.trim()}');
    }
    if (data.spotCount != null) {
      metaParts.add('${data.spotCount} Spots');
    }
    final metaText = metaParts.join(' · ');
    if (metaText.isNotEmpty) {
      final metaStyle = const TextStyle(
        color: Color(0xFF8E988F),
        fontSize: 26,
        height: 1.3,
      );
      final metaPainter = TextPainter(
        text: TextSpan(text: metaText, style: metaStyle),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: textWidth);
      metaPainter.paint(canvas, Offset(padding, cursorY));
      cursorY += metaPainter.height + 16;
    }

    final listTop = cursorY + 6;
    final listRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        padding,
        listTop,
        width - (padding * 2),
        height - listTop - padding,
      ),
      const Radius.circular(36),
    );
    final listPaint = Paint()..color = const Color(0xFF0F1412);
    canvas.drawRRect(listRect, listPaint);

    final listTitleStyle = const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w600,
    );
    final listTitle = TextPainter(
      text: TextSpan(text: 'Spots', style: listTitleStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    listTitle.paint(canvas, Offset(padding + 28, listTop + 24));

    if (totalPages > 1) {
      final pageStyle = const TextStyle(
        color: Color(0xFF96A199),
        fontSize: 24,
        fontWeight: FontWeight.w600,
      );
      final pageText = TextPainter(
        text: TextSpan(text: '${pageIndex + 1}/$totalPages', style: pageStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth);
      pageText.paint(
        canvas,
        Offset(width - padding - 28 - pageText.width, listTop + 28),
      );
    }

    double rowY = listTop + 78;
    final rowHeight = 84.0;
    final accentPaint = Paint()..color = MingaTheme.accentGreen;
    if (places.isEmpty) {
      final emptyPainter = TextPainter(
        text: const TextSpan(
          text: 'Keine Spots vorhanden',
          style: TextStyle(
            color: Color(0xFF95A39B),
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth - 56);
      emptyPainter.paint(canvas, Offset(padding + 28, rowY));
    } else {
      for (var i = 0; i < places.length; i++) {
        final place = places[i];
        final index = (pageIndex * pageSize) + i + 1;
        final numberCenter = Offset(padding + 44, rowY + 22);
        canvas.drawCircle(numberCenter, 20, accentPaint);
        final numberPainter = TextPainter(
          text: TextSpan(
            text: '$index',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: 40);
        numberPainter.paint(
          canvas,
          Offset(
            numberCenter.dx - (numberPainter.width / 2),
            numberCenter.dy - (numberPainter.height / 2),
          ),
        );

        final namePainter = TextPainter(
          text: TextSpan(
            text: place.name.trim(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: width - padding - 140);
        namePainter.paint(canvas, Offset(padding + 88, rowY));

        final details = _formatShareSpotDetails(place);
        if (details.isNotEmpty) {
          final detailsPainter = TextPainter(
            text: TextSpan(
              text: details,
            style: const TextStyle(
              color: Color(0xFF95A39B),
              fontSize: 20,
              height: 1.2,
            ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: width - padding - 140);
          detailsPainter.paint(canvas, Offset(padding + 88, rowY + 38));
        }

        if (i < places.length - 1) {
          final dividerPaint = Paint()
            ..color = const Color(0xFF1E2622)
            ..strokeWidth = 1;
          final lineY = rowY + rowHeight - 16;
          canvas.drawLine(
            Offset(padding + 28, lineY),
            Offset(width - padding - 28, lineY),
            dividerPaint,
          );
        }
        rowY += rowHeight;
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Share card bytes missing');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
      coverImage?.dispose();
    }
  }

  String _formatShareSpotDetails(Place place) {
    final parts = <String>[];
    final category = place.category.trim();
    if (category.isNotEmpty) {
      parts.add(category);
    }
    final distance = place.distanceKm;
    if (distance != null) {
      parts.add('${distance.toStringAsFixed(1)} km');
    }
    return parts.join(' · ');
  }

  Future<ui.Image> _loadNetworkImage(String url) async {
    final uri = Uri.parse(url);
    final bundle = NetworkAssetBundle(uri);
    final data = await bundle.load(url);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
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
    final systemCollab = _findCollab(collabId);
    if (systemCollab != null && systemCollab.requiresRuntime) {
      // System collabs are not stored in the user collabs table.
      return;
    }
    if (!_isUuid(collabId)) {
      return;
    }
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

  bool _isUuid(String value) {
    final regex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return regex.hasMatch(value);
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
      final description =
          _descriptionOverrides[collabId] ?? collabDefinition.subtitle;
      final title = _titleOverrides[collabId] ?? collabDefinition.title;
      final isEventsThisWeek = collabDefinition.id == eventsThisWeekCollabId;
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomNavSafePadding(context)),
        child: Column(
          children: [
            _buildHero(collabId, collabDefinition),
            _buildOwnerActions(collabId, collabDefinition.creatorId),
            _buildDescriptionSection(collabId, title, description),
            if (isEventsThisWeek)
              _buildEventsThisWeekList()
            else
              _buildPlacesList(collabDefinition),
          ],
        ),
      );
    }

    if (_isSystemLoading) {
      return Center(
        child: CircularProgressIndicator(color: MingaTheme.accentGreen),
      );
    }

    final collab = _collabDataById[collabId];
    if (collab == null) {
      return _buildMissingCollab();
    }
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomNavSafePadding(context)),
      child: Column(
        children: [
          _buildSupabaseHero(collabId, collab),
          _buildOwnerActions(collabId, collab.ownerId),
          _buildDescriptionSection(
            collabId,
            collab.title,
            collab.description ?? '',
          ),
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
    final fallbackUrls = _fallbackMediaByCollabId[collabId] ?? const [];

    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildHeroMedia(
              collabId: collabId,
              items: mediaItems,
              fallbackUrls: fallbackUrls,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  collab.title,
                  style: MingaTheme.titleLarge.copyWith(height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isOwnerById(collab.ownerId)
                      ? _buildSupabaseEditButton(collabId, collab)
                      : _buildFollowButton(collabId),
                ),
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
        _scheduleFallbackUpdate(collabId, places);
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

        final ownerId = _collabDataById[collabId]?.ownerId;
        final canEditNotes =
            ownerId != null && _isOwnerById(ownerId);
        final list = ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          itemCount: limitedPlaces.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => Divider(
            color: MingaTheme.borderSubtle,
            height: 24,
          ),
          itemBuilder: (context, index) {
            final place = limitedPlaces[index];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlaceNumberBadge(index + 1),
                const SizedBox(width: 12),
                Expanded(
                  child: PlaceListTile(
                    place: place,
                    note: notes[place.id],
                    isNoteExpanded:
                        _expandedNoteKeys.contains(_noteKey(collabId, place.id)),
                    onToggleNote: () => _toggleNote(collabId, place.id),
                    onEditNote: canEditNotes
                        ? () => _showPlaceNoteSheet(
                              collabId: collabId,
                              placeId: place.id,
                              initialNote: notes[place.id],
                              isSupabase: true,
                            )
                        : null,
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
                  ),
                ),
              ],
            );
          },
        );

        return Column(
          children: [
            _buildPlacesMap(limitedPlaces),
            list,
          ],
        );
      },
    );
  }

  Widget _buildEventsThisWeekList() {
    return FutureBuilder<List<Event>>(
      future: _eventRepository.fetchEventsThisWeek(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: MingaTheme.accentGreen,
            ),
          );
        }

        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return Center(
            child: Text(
              'Keine Events diese Woche',
              style: MingaTheme.body.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          );
        }

        final limitedEvents =
            events.length > 30 ? events.take(30).toList() : events;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: limitedEvents.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _buildEventCard(limitedEvents[index]);
          },
        );
      },
    );
  }

  Widget _buildEventCard(Event event) {
    final dateText = _formatEventDateLine(event);
    final locationText = _formatEventLocation(event);
    final descriptionText = _sanitizeEventDescription(event.description);
    return GlassSurface(
      radius: MingaTheme.cardRadius,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlay,
      boxShadow: MingaTheme.cardShadow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title.trim(),
              style: MingaTheme.titleSmall.copyWith(fontSize: 16),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              dateText,
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSecondary,
              ),
            ),
            if (locationText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                locationText,
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
              ),
            ],
            if (descriptionText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                descriptionText,
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSecondary,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatEventDateLine(Event event) {
    DateTime? start = event.effectiveStart;
    if (start == null && event.startDate != null) {
      start = DateTime.tryParse(event.startDate!.trim());
    }
    if (start == null) return 'Datum folgt';
    final local = start.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final time = event.startTime?.trim();
    if (time != null && time.isNotEmpty) {
      final hhmm = time.length >= 5 ? time.substring(0, 5) : time;
      return '$day.$month.$year · $hhmm';
    }
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year · $hour:$minute';
  }

  String _formatEventLocation(Event event) {
    final venue = event.venueName?.trim();
    if (venue != null && venue.isNotEmpty) return venue;
    final venueId = event.venueId?.trim();
    if (venueId != null && venueId.isNotEmpty) return venueId;
    return '';
  }

  String _sanitizeEventDescription(String description) {
    return description.replaceAll(RegExp(r'\s+'), ' ').trim();
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
    var places = await _fetchSupabaseCollabPlaces(collabId);
    places = await _applyDistances(places);
    final notes =
        await _collabsRepository.fetchCollabPlaceNotes(collabId: collabId);
    _supabaseNotesByCollabId[collabId] = notes;
    _updateFallbackMedia(collabId, places);
    return _CollabPlacesPayload(places: places, notes: notes);
  }

  Future<LatLng> _getOrigin() {
    return _originFuture ??= _locationService.getOriginOrFallback();
  }

  Future<List<Place>> _applyDistances(List<Place> places) async {
    if (places.isEmpty) return places;
    final origin = await _getOrigin();
    return places.map((place) {
      final distanceKm = _distanceCache.getOrCompute(
        placeId: place.id,
        userLat: origin.lat,
        userLng: origin.lng,
        placeLat: place.lat,
        placeLng: place.lng,
      );
      if (distanceKm == null) {
        return place.copyWith(clearDistanceKm: true);
      }
      return place.copyWith(distanceKm: distanceKm);
    }).toList();
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

  Widget _buildFallbackCarousel({
    required List<String> urls,
    String? gradientKey,
  }) {
    final carouselItems = urls
        .map((url) => MediaCarouselItem(url: url, isVideo: false))
        .toList();
    return MediaCarousel(
      items: carouselItems,
      gradientKey: gradientKey,
    );
  }

  Widget _buildHeroMedia({
    required String collabId,
    required List<CollabMediaItem> items,
    required List<String> fallbackUrls,
    String? gradientKey,
  }) {
    if (items.isNotEmpty) {
      return _buildMediaCarousel(items: items, gradientKey: gradientKey);
    }
    if (fallbackUrls.isNotEmpty) {
      return _buildFallbackCarousel(
        urls: fallbackUrls,
        gradientKey: gradientKey,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: _gradientForKey(
          context.tokens.gradients,
          gradientKey,
        ),
      ),
    );
  }

  LinearGradient _gradientForKey(AppGradientTokens gradients, String? key) {
    switch (key) {
      case 'calm':
        return gradients.calm;
      case 'sunset':
        return gradients.sunset;
      case 'deep':
        return gradients.deep;
      case 'mint':
      default:
        return gradients.mint;
    }
  }

  void _updateFallbackMedia(String collabId, List<Place> places) {
    final urls = _extractPlaceImages(places);
    if (urls.isEmpty) return;
    final current = _fallbackMediaByCollabId[collabId] ?? const [];
    if (_listEquals(current, urls)) return;
    _fallbackMediaByCollabId[collabId] = urls;
  }

  void _scheduleFallbackUpdate(String collabId, List<Place> places) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final urls = _extractPlaceImages(places);
      if (urls.isEmpty) return;
      final current = _fallbackMediaByCollabId[collabId] ?? const [];
      if (_listEquals(current, urls)) return;
      setState(() {
        _fallbackMediaByCollabId[collabId] = urls;
      });
    });
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

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
        _scheduleFallbackUpdate(collab.id, limitedPlaces);

        final canEditNotes = _isOwnerById(collab.creatorId);
        final list = ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          itemCount: limitedPlaces.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, __) => Divider(
            color: MingaTheme.borderSubtle,
            height: 24,
          ),
          itemBuilder: (context, index) {
            final place = limitedPlaces[index];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlaceNumberBadge(index + 1),
                const SizedBox(width: 12),
                Expanded(
                  child: PlaceListTile(
                    place: place,
                    note: notes[place.id],
                    isNoteExpanded:
                        _expandedNoteKeys.contains(_noteKey(collab.id, place.id)),
                    onToggleNote: () => _toggleNote(collab.id, place.id),
                    onEditNote: canEditNotes
                        ? () => _showPlaceNoteSheet(
                              collabId: collab.id,
                              placeId: place.id,
                              initialNote: notes[place.id],
                              isSupabase: false,
                            )
                        : null,
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
                  ),
                ),
              ],
            );
          },
        );

        return Column(
          children: [
            _buildPlacesMap(limitedPlaces),
            list,
          ],
        );
      },
    );
  }


  Widget _buildPlacesMap(List<Place> places) {
    final tokens = context.tokens;
    final placesWithCoords =
        places.where((place) => place.lat != null && place.lng != null).toList();
    if (placesWithCoords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Text(
          'Keine Standorte für die Karte verfügbar',
          style: tokens.type.body.copyWith(color: tokens.colors.textSecondary),
        ),
      );
    }

    final bounds = _boundsForPlaces(placesWithCoords);
    final center = bounds == null
        ? gmaps.LatLng(48.137154, 11.576124)
        : gmaps.LatLng(
            (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
            (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        child: SizedBox(
          height: 260,
          child: FutureBuilder<Set<gmaps.Marker>>(
            future: _buildNumberedMarkers(placesWithCoords),
            builder: (context, snapshot) {
              final markers = snapshot.data ?? const <gmaps.Marker>{};
              return gmaps.GoogleMap(
                initialCameraPosition: gmaps.CameraPosition(
                  target: center,
                  zoom: 13.2,
                ),
                onMapCreated: (controller) {
                  _collabMapController = controller;
                  _collabMapController?.setMapStyle(_darkMapStyle);
                  if (bounds != null) {
                    controller.animateCamera(
                      gmaps.CameraUpdate.newLatLngBounds(bounds, 60),
                    );
                  }
                },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                markers: markers,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceNumberBadge(int number) {
    final tokens = context.tokens;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: tokens.colors.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: tokens.type.caption.copyWith(
          color: tokens.colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<Set<gmaps.Marker>> _buildNumberedMarkers(
    List<Place> places,
  ) async {
    final markers = <gmaps.Marker>{};
    for (var i = 0; i < places.length; i++) {
      final place = places[i];
      final icon = await _numberedMarkerIcon(i + 1);
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId(place.id),
          position: gmaps.LatLng(place.lat!, place.lng!),
          icon: icon,
          onTap: () => _showCollabMapPreview(place),
        ),
      );
    }
    return markers;
  }

  Future<gmaps.BitmapDescriptor> _numberedMarkerIcon(int number) async {
    final key = 'collab_$number';
    final cached = _collabMarkerCache[key];
    if (cached != null) return cached;

    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final paint = Paint()..color = MingaTheme.accentGreen;
    canvas.drawCircle(center, size / 2 - 4, paint);
    canvas.drawCircle(
      center,
      size / 2 - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withOpacity(0.9),
    );

    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size);
    painter.paint(
      canvas,
      Offset(
        center.dx - painter.width / 2,
        center.dy - painter.height / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return gmaps.BitmapDescriptor.defaultMarker;
    }
    final descriptor = gmaps.BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
    _collabMarkerCache[key] = descriptor;
    return descriptor;
  }

  Future<void> _showCollabMapPreview(Place place) async {
    final tokens = context.tokens;
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
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.title.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
            SizedBox(height: tokens.space.s8),
            Wrap(
              spacing: tokens.space.s8,
              runSpacing: tokens.space.s6,
              children: [
                if (place.category.isNotEmpty)
                  GlassBadge(
                    label: place.category,
                    variant: GlassBadgeVariant.fresh,
                  ),
                if (place.distanceKm != null)
                  GlassBadge(
                    label: '${place.distanceKm!.toStringAsFixed(1)} km',
                    variant: GlassBadgeVariant.online,
                  ),
              ],
            ),
            SizedBox(height: tokens.space.s12),
            if (place.address != null && place.address!.trim().isNotEmpty)
              Text(
                place.address!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.type.body.copyWith(
                  color: tokens.colors.textSecondary,
                  height: 1.4,
                ),
              ),
            SizedBox(height: tokens.space.s16),
            GlassButton(
              label: 'Spot öffnen',
              onPressed: () {
                Navigator.of(context).pop();
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
            ),
          ],
        ),
      ),
    );
  }

  gmaps.LatLngBounds? _boundsForPlaces(List<Place> places) {
    double? minLat;
    double? maxLat;
    double? minLng;
    double? maxLng;
    for (final place in places) {
      final lat = place.lat;
      final lng = place.lng;
      if (lat == null || lng == null) continue;
      minLat = minLat == null ? lat : math.min(minLat, lat);
      maxLat = maxLat == null ? lat : math.max(maxLat, lat);
      minLng = minLng == null ? lng : math.min(minLng, lng);
      maxLng = maxLng == null ? lng : math.max(maxLng, lng);
    }
    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return null;
    }
    return gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
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
                  child: Text('Beschreibung', style: MingaTheme.titleSmall),
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
              hintText: 'Kurze Beschreibung zum Spot…',
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
                        content: Text(
                          'Beschreibung konnte nicht gespeichert werden',
                        ),
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

    try {
      if (_followedLists[collabId] != null) {
        await _favoritesRepository.deleteFavoriteList(
          listId: _followedLists[collabId]!.id,
        );
        if (mounted) {
          setState(() {
            _followedLists[collabId] = null;
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konnte Collab nicht folgen.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFollowById[collabId] = false;
        });
      }
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

