import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../services/supabase_profile_repository.dart';
import '../models/collab.dart';
import 'activity_badge.dart';
import 'media/media_carousel.dart';
import 'media/media_viewer.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_card.dart';
import '../widgets/glass/glass_surface.dart';
import '../theme/app_tokens.dart';

class CollabCard extends StatefulWidget {
  final String title;
  final String username;
  final String? avatarUrl;
  final String? creatorId;
  final String? creatorBadge;
  final String? imageUrl;
  final List<String> mediaUrls;
  final String? gradientKey;
  final String? activityLabel;
  final Color? activityColor;
  final int? spotCount;
  final int? saveCount;
  final double aspectRatio;
  final VoidCallback onTap;
  final VoidCallback onCreatorTap;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;
  final VoidCallback? onEditTap;

  const CollabCard({
    super.key,
    required this.title,
    required this.username,
    required this.onCreatorTap,
    required this.onTap,
    this.avatarUrl,
    this.creatorId,
    this.creatorBadge,
    this.imageUrl,
    this.mediaUrls = const [],
    this.gradientKey,
    this.activityLabel,
    this.activityColor,
    this.spotCount,
    this.saveCount,
    this.aspectRatio = 3 / 4,
    this.ctaLabel,
    this.onCtaTap,
    this.onEditTap,
  });

  @override
  State<CollabCard> createState() => _CollabCardState();
}

class _CollabCardState extends State<CollabCard> {
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  UserProfile? _creatorProfile;
  int _mediaIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCreatorProfile();
  }

  @override
  void didUpdateWidget(CollabCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creatorId != widget.creatorId ||
        oldWidget.username != widget.username ||
        oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.creatorBadge != widget.creatorBadge) {
      _loadCreatorProfile();
    }
  }

  Future<void> _loadCreatorProfile() async {
    final creatorId = widget.creatorId?.trim();
    if (creatorId == null || creatorId.isEmpty) {
      return;
    }
    final cached = _profileRepository.getCachedProfile(creatorId);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _creatorProfile = cached;
        });
      } else {
        _creatorProfile = cached;
      }
      return;
    }
    if (widget.creatorBadge != null &&
        widget.creatorBadge!.trim().isNotEmpty &&
        widget.avatarUrl != null &&
        widget.avatarUrl!.trim().isNotEmpty &&
        widget.username.trim().isNotEmpty &&
        !_isGenericLabel(widget.username)) {
      return;
    }

    final profile = await _profileRepository.fetchUserProfileLite(creatorId);
    if (!mounted || profile == null) return;
    setState(() {
      _creatorProfile = profile;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: GlassCard(
          variant: GlassCardVariant.media,
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(child: _buildHero()),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tokens.colors.transparent,
                        tokens.colors.scrim,
                        tokens.colors.scrimStrong,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              if (widget.activityLabel != null &&
                  widget.activityLabel!.isNotEmpty)
                Positioned(
                  top: tokens.space.s12,
                  left: tokens.space.s12,
                  child: ActivityBadge(
                    label: widget.activityLabel!,
                    color: widget.activityColor ?? tokens.colors.accent,
                  ),
                ),
              Positioned(
                left: tokens.space.s12,
                right: tokens.space.s12,
                bottom: tokens.space.s12,
                child: _buildText(),
              ),
              if (widget.onEditTap != null)
                Positioned(
                  top: tokens.space.s12,
                  right: tokens.space.s12,
                  child: GlassButton(
                    variant: GlassButtonVariant.icon,
                    icon: Icons.edit,
                    onPressed: widget.onEditTap,
                  ),
                ),
              if (widget.ctaLabel != null && widget.ctaLabel!.isNotEmpty)
                Positioned(
                  right: tokens.space.s12,
                  bottom: tokens.space.s12,
                  child: GlassButton(
                    variant: GlassButtonVariant.secondary,
                    label: widget.ctaLabel!,
                    onPressed: widget.onCtaTap ?? widget.onTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final tokens = context.tokens;
    final mediaUrls = widget.mediaUrls.where((url) => url.trim().isNotEmpty).toList();
    if (mediaUrls.isNotEmpty) {
      final items = mediaUrls
          .map((url) => MediaCarouselItem(url: url, isVideo: false))
          .toList();
      return MediaCarousel(
        items: items,
        gradientKey: widget.gradientKey,
        onPageChanged: (index) {
          if (!mounted) return;
          setState(() {
            _mediaIndex = index;
          });
        },
        onExpand: (index) => _openMediaViewer(mediaUrls),
      );
    }

    final heroUrl = widget.imageUrl?.trim();
    if (heroUrl != null && heroUrl.isNotEmpty) {
      return Image.network(
        heroUrl,
        fit: BoxFit.cover,
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: _gradientForKey(tokens.gradients, widget.gradientKey),
      ),
    );
  }

  void _openMediaViewer(List<String> urls) {
    if (urls.isEmpty) return;
    final items = urls
        .map((url) => MediaCarouselItem(url: url, isVideo: false))
        .toList();
    final initialIndex = _mediaIndex.clamp(0, items.length - 1);
    MediaViewer.show(
      context,
      items: items,
      initialIndex: initialIndex,
      muted: true,
    );
  }

  LinearGradient _gradientForKey(AppGradientTokens gradients, String? key) {
    switch (key) {
      case 'mint':
        return gradients.mint;
      case 'calm':
        return gradients.calm;
      case 'sunset':
        return gradients.sunset;
      default:
        return gradients.deep;
    }
  }

  Widget _buildText() {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tokens.type.title.copyWith(
            color: tokens.colors.textPrimary,
            height: 1.2,
          ),
        ),
        SizedBox(height: tokens.space.s6),
        if (widget.spotCount != null)
          Text(
            '${widget.spotCount} Spots',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textMuted,
            ),
          ),
        if (widget.saveCount != null) ...[
          if (widget.spotCount != null) SizedBox(height: tokens.space.s4),
          Text(
            '${widget.saveCount} gespeichert',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textMuted,
            ),
          ),
        ],
        if (widget.spotCount != null || widget.saveCount != null)
          SizedBox(height: tokens.space.s6),
        GestureDetector(
          onTap: widget.onCreatorTap,
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: tokens.colors.scrim,
                backgroundImage: _avatarImage,
                child: _avatarImage == null
                    ? Icon(
                        Icons.person,
                        size: 12,
                        color: tokens.colors.textSecondary,
                      )
                    : null,
              ),
              SizedBox(width: tokens.space.s6),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'von $_resolvedDisplayLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.type.caption.copyWith(
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                    ),
                    if (_resolvedBadge != null &&
                        _resolvedBadge!.trim().isNotEmpty)
                      GlassSurface(
                        radius: tokens.radius.sm,
                        blur: tokens.blur.low,
                        scrim: tokens.card.glassOverlay,
                        borderColor: tokens.colors.border,
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.space.s6,
                          vertical: tokens.space.s2,
                        ),
                        child: Text(
                          _resolvedBadge!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.type.caption.copyWith(
                            color: tokens.colors.textPrimary,
                            fontSize: 10,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ImageProvider? get _avatarImage {
    final trimmed = _resolvedAvatar?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return NetworkImage(trimmed);
  }

  String? get _resolvedAvatar {
    final provided = widget.avatarUrl?.trim();
    if (provided != null && provided.isNotEmpty) {
      return provided;
    }
    return _creatorProfile?.avatarUrl;
  }

  String get _resolvedDisplayLabel {
    final profile = _creatorProfile;
    final profileUsername = profile?.username ?? '';
    return CreatorLabelResolver.resolve(
      displayName: profile?.displayName ?? widget.username,
      username: profileUsername.trim().isNotEmpty ? profileUsername : null,
    );
  }

  bool _isGenericLabel(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'user' ||
        normalized == 'unknown' ||
        normalized.contains('unbekannt');
  }

  String? get _resolvedBadge {
    final provided = widget.creatorBadge?.trim();
    if (provided != null && provided.isNotEmpty) {
      return provided;
    }
    return _creatorProfile?.badge;
  }

  
}

