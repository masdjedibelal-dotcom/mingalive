import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/place.dart';
import '../models/room_media_post.dart';
import '../services/supabase_chat_repository.dart';
import '../services/auth_service.dart';
import '../services/supabase_gate.dart';
import 'live_badge.dart';
import 'reaction_bar.dart';
import 'media/media_carousel.dart';
import 'media/media_viewer.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_badge.dart';
import '../widgets/glass/glass_surface.dart';

/// Media card widget with trending media carousel rotation
///
/// Displays room media posts with auto-advance every 5 seconds.
/// Shows a placeholder when no media is available.
class MediaCard extends StatefulWidget {
  final Place place;
  final List<RoomMediaPost> mediaPosts;
  final int liveCount;
  final Widget? topRightActions;
  final BorderRadius? borderRadius;
  final bool useAspectRatio;

  const MediaCard({
    super.key,
    required this.place,
    required this.mediaPosts,
    required this.liveCount,
    this.topRightActions,
    this.borderRadius,
    this.useAspectRatio = true,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  final SupabaseChatRepository _repository = SupabaseChatRepository();
  List<RoomMediaPost> _rotationMedia = [];
  int _currentIndex = 0;
  static const Duration _liveWindow = Duration(minutes: 60);
  bool _isRefreshingReactions = false;
  bool _showReactions = false;

  @override
  void initState() {
    super.initState();
    _setMedia(widget.mediaPosts);
    _refreshMediaWithReactions();
  }

  @override
  void didUpdateWidget(covariant MediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameMediaList(oldWidget.mediaPosts, widget.mediaPosts)) {
      _setMedia(widget.mediaPosts);
      _refreshMediaWithReactions();
    } else if (oldWidget.place.chatRoomId != widget.place.chatRoomId) {
      _refreshMediaWithReactions();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
  void _toggleReactions() {
    setState(() {
      _showReactions = !_showReactions;
    });
  }

  void _setMedia(List<RoomMediaPost> posts) {
    _rotationMedia = List<RoomMediaPost>.from(posts);
    if (_currentIndex >= _rotationMedia.length) {
      _currentIndex = 0;
    }
  }

  Future<void> _refreshMediaWithReactions() async {
    if (!SupabaseGate.isEnabled) return;
    if (_isRefreshingReactions) return;
    final roomId = widget.place.chatRoomId;
    if (roomId.isEmpty) return;
    _isRefreshingReactions = true;
    try {
      final fetched = await _repository.fetchRoomMediaPosts(
        roomId,
        limit: ROOM_MEDIA_LIMIT,
      );
      if (!mounted) return;
      if (fetched.isEmpty) return;
      final fetchedById = {
        for (final post in fetched) post.id: post,
      };
      setState(() {
        if (_rotationMedia.isEmpty) {
          _rotationMedia = List<RoomMediaPost>.from(fetched);
        } else {
          _rotationMedia = _rotationMedia
              .map((post) => fetchedById[post.id] ?? post)
              .toList();
        }
        if (_currentIndex >= _rotationMedia.length) {
          _currentIndex = 0;
        }
      });
    } catch (_) {
      // Keep existing UI state if refresh fails.
    } finally {
      _isRefreshingReactions = false;
    }
  }

  bool _sameMediaList(List<RoomMediaPost> a, List<RoomMediaPost> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final first = a[i];
      final second = b[i];
      if (first.id != second.id) return false;
      if (first.reactionsCount != second.reactionsCount) return false;
      if (first.currentUserReaction != second.currentUserReaction) return false;
      if (!_sameReactionCounts(first.reactionCounts, second.reactionCounts)) {
        return false;
      }
    }
    return true;
  }

  bool _sameReactionCounts(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Handle reaction button tap
  Future<void> _handleReaction(String reaction) async {
    HapticFeedback.lightImpact();
    final currentMediaPost = _rotationMedia.isNotEmpty && _currentIndex < _rotationMedia.length
        ? _rotationMedia[_currentIndex]
        : null;
    
    if (currentMediaPost == null) return;
    
    // Check if user is logged in
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte einloggen, um zu reagieren.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Store original post for potential revert
    final originalPost = currentMediaPost;
    final wasSelected = originalPost.currentUserReaction == reaction;
    final hadReaction = originalPost.currentUserReaction != null;

    if (kDebugMode) {
      debugPrint(
        '🟣 MediaCard: react tap post=${originalPost.id} current=${originalPost.currentUserReaction} next=$reaction',
      );
    }
    
    // Optimistically update UI
    setState(() {
      int newCount = originalPost.reactionsCount;
      String? newUserReaction;
      
      if (wasSelected) {
        // Removing reaction (tapped same emoji again)
        newCount = (newCount - 1).clamp(0, double.infinity).toInt();
        newUserReaction = null;
      } else if (hadReaction) {
        // Switching reaction (different emoji)
        // Count stays the same (one reaction replaced by another)
        newCount = originalPost.reactionsCount;
        newUserReaction = reaction;
      } else {
        // Adding new reaction
        newCount = originalPost.reactionsCount + 1;
        newUserReaction = reaction;
      }
      
      final updatedCounts = Map<String, int>.from(originalPost.reactionCounts);
      if (wasSelected) {
        updatedCounts[reaction] = (updatedCounts[reaction] ?? 1) - 1;
        if (updatedCounts[reaction] != null && updatedCounts[reaction]! <= 0) {
          updatedCounts.remove(reaction);
        }
      } else if (hadReaction) {
        final previous = originalPost.currentUserReaction!;
        updatedCounts[previous] = (updatedCounts[previous] ?? 1) - 1;
        if (updatedCounts[previous] != null && updatedCounts[previous]! <= 0) {
          updatedCounts.remove(previous);
        }
        updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      } else {
        updatedCounts[reaction] = (updatedCounts[reaction] ?? 0) + 1;
      }

      final updatedPost = RoomMediaPost(
        id: originalPost.id,
        roomId: originalPost.roomId,
        userId: originalPost.userId,
        mediaUrl: originalPost.mediaUrl,
        mediaType: originalPost.mediaType,
        createdAt: originalPost.createdAt,
        reactionsCount: newCount,
        currentUserReaction: newUserReaction,
        reactionCounts: updatedCounts,
      );
      _rotationMedia[_currentIndex] = updatedPost;
    });
    
    // Call repository to save reaction
    _repository.reactToMedia(
      mediaPostId: currentMediaPost.id,
      reaction: reaction,
    ).then((newReaction) {
      if (!mounted) return;
    }).catchError((error) {
      // Revert optimistic update on error
      if (mounted) {
        setState(() {
          // Restore original post
          _rotationMedia[_currentIndex] = originalPost;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Reagieren: $error'),
            duration: const Duration(seconds: 2),
            backgroundColor: context.tokens.colors.danger,
          ),
        );
      }
    });
  }

  Future<void> _handleReactionAndCollapse(String reaction) async {
    await _handleReaction(reaction);
    if (!mounted) return;
    setState(() {
      _showReactions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final currentMediaPost = _rotationMedia.isNotEmpty &&
            _currentIndex < _rotationMedia.length
        ? _rotationMedia[_currentIndex]
        : null;
    final isLiveMedia = currentMediaPost != null &&
        DateTime.now().difference(currentMediaPost.createdAt) <= _liveWindow;

    final carouselItems = _rotationMedia
        .map(
          (post) => MediaCarouselItem(
            url: post.mediaUrl,
            isVideo: post.mediaType == 'video' || _isVideo(post.mediaUrl),
          ),
        )
        .toList();

    final stack = Stack(
        fit: StackFit.expand,
        children: [
          // Media content (full width)
          ClipRRect(
            borderRadius: widget.borderRadius ??
                BorderRadius.only(
                  bottomLeft: Radius.circular(tokens.radius.md),
                  bottomRight: Radius.circular(tokens.radius.md),
                ),
            child: MediaCarousel(
              items: carouselItems,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              onExpand: (index) =>
                  _openMediaViewer(index, carouselItems),
            ),
          ),
          // Overlay: minimal LIVE signal only
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: EdgeInsets.all(tokens.space.s12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tokens.colors.scrimStrong,
                      tokens.colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    LiveBadge(
                      liveCount: widget.liveCount,
                      compact: true,
                    ),
                    if (isLiveMedia)
                      Padding(
                        padding: EdgeInsets.only(left: tokens.space.s8),
                        child: GlassBadge(
                          label: 'Live',
                          variant: GlassBadgeVariant.live,
                        ),
                      ),
                    const Spacer(),
                    SizedBox(width: tokens.space.s8),
                    // Right: optional actions
                    if (widget.topRightActions != null) widget.topRightActions!,
                  ],
                ),
              ),
            ),
          ),
          // Reactions row overlay at bottom-right
          if (currentMediaPost != null)
            Positioned(
            bottom: tokens.space.s12,
            left: tokens.space.s12,
              child: SafeArea(
                top: false,
              child: Padding(
                padding: EdgeInsets.zero,
                child: AnimatedSwitcher(
                  duration: tokens.motion.med,
                  switchInCurve: tokens.motion.curve,
                  switchOutCurve: tokens.motion.curve,
                  child: _showReactions
                      ? ReactionBar(
                          key: const ValueKey('reactions_open'),
                          currentUserReaction:
                              currentMediaPost.currentUserReaction,
                          totalReactionsCount: currentMediaPost.reactionsCount,
                          onReactionTap: _handleReactionAndCollapse,
                        )
                      : GestureDetector(
                          key: const ValueKey('reactions_closed'),
                          onTap: _toggleReactions,
                          child: GlassSurface(
                            radius: tokens.radius.pill,
                            blur: tokens.blur.low,
                            scrim: tokens.card.glassOverlay,
                            borderColor: tokens.colors.border,
                            padding: EdgeInsets.symmetric(
                              horizontal: tokens.space.s8,
                              vertical: tokens.space.s6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '🙂',
                                  style: tokens.type.body.copyWith(
                                    color: tokens.colors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                                if (currentMediaPost.reactionsCount > 0) ...[
                                  SizedBox(width: tokens.space.s6),
                                  Text(
                                    '${currentMediaPost.reactionsCount}',
                                    style: tokens.type.caption.copyWith(
                                      color: tokens.colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              ),
            ),
        ],
      );
    if (widget.useAspectRatio) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: stack,
      );
    }
    return SizedBox.expand(child: stack);
  }


  /// Check if URL is a video
  bool _isVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mp4') ||
        lowerUrl.contains('.mov') ||
        lowerUrl.contains('video') ||
        lowerUrl.contains('.webm') ||
        lowerUrl.contains('.avi');
  }

  void _openMediaViewer(int initialIndex, List<MediaCarouselItem> items) {
    if (items.isEmpty) return;
    MediaViewer.show(
      context,
      items: items,
      initialIndex: initialIndex,
      muted: true,
    );
  }
}

// _MediaItem removed - using RoomMediaPost rotation queue.

