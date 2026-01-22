import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../models/user_presence.dart';
import '../services/presence_service.dart';
import '../services/supabase_profile_repository.dart';
import '../screens/creator_profile_screen.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

/// Chat message tile widget (text-only)
/// 
/// Media is NOT rendered in chat messages.
/// Media only appears in the top MediaCard.
class ChatMessageTile extends StatefulWidget {
  final ChatMessage message;
  final bool showAvatar;
  final Map<String, UserPresence>? userPresences; // Optional: for badge calculation
  final ValueChanged<String>? onReact;
  final List<String> availableReactions;

  const ChatMessageTile({
    super.key,
    required this.message,
    this.showAvatar = true,
    this.userPresences,
    this.onReact,
    this.availableReactions = const ['🔥', '❤️', '😂', '👀'],
  });

  @override
  State<ChatMessageTile> createState() => _ChatMessageTileState();
}

class _ChatMessageTileState extends State<ChatMessageTile> {
  final SupabaseProfileRepository _profileRepository =
      SupabaseProfileRepository();
  String? _resolvedName;
  String? _resolvedAvatar;

  @override
  void initState() {
    super.initState();
    if (!_isSystemMessage) {
      _resolveProfile();
    }
  }

  @override
  void didUpdateWidget(ChatMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.userId != widget.message.userId ||
        oldWidget.message.userName != widget.message.userName ||
        oldWidget.message.userAvatar != widget.message.userAvatar) {
      if (!_isSystemMessage) {
        _resolveProfile();
      }
    }
  }

  Future<void> _resolveProfile() async {
    final providedName = widget.message.userName.trim();
    if (providedName.isNotEmpty &&
        !providedName.toLowerCase().contains('unbekannt')) {
      setState(() {
        _resolvedName = providedName;
        _resolvedAvatar = widget.message.userAvatar;
      });
      return;
    }

    final cached = _profileRepository.getCachedProfile(widget.message.userId);
    if (cached != null) {
      setState(() {
        _resolvedName = _displayNameForProfile(cached);
        _resolvedAvatar = widget.message.userAvatar ?? cached.avatarUrl;
      });
      return;
    }

    final profile =
        await _profileRepository.fetchUserProfileLite(widget.message.userId);
    if (!mounted || profile == null) return;
    setState(() {
      _resolvedName = _displayNameForProfile(profile);
      _resolvedAvatar = widget.message.userAvatar ?? profile.avatarUrl;
    });
  }

  String _displayNameForProfile(UserProfile profile) {
    final display = profile.displayName.trim();
    if (display.isNotEmpty) return display;
    final username = profile.username.trim();
    if (username.isNotEmpty) return username;
    return 'User';
  }

  String get _displayName {
    if (_isSystemMessage) return 'System';
    final resolved = _resolvedName?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    final fallback = widget.message.userName.trim();
    if (fallback.isNotEmpty) return fallback;
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_isSystemMessage) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.space.s8),
        child: Center(
          child: GlassSurface(
            radius: tokens.radius.pill,
            blur: tokens.blur.low,
            scrim: tokens.card.glassOverlay,
            borderColor: tokens.colors.border,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space.s12,
                vertical: tokens.space.s6,
              ),
              child: Text(
                widget.message.text,
                style: tokens.type.caption.copyWith(
                  color: tokens.colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: widget.message.isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!widget.message.isMine && widget.showAvatar) ...[
            GestureDetector(
              onTap: () => _openProfile(context, widget.message.userId),
              child: _buildAvatar(),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: widget.message.isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPressStart: widget.onReact == null
                      ? null
                      : (details) => _showReactionPickerAt(
                            context,
                            details.globalPosition,
                          ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GlassSurface(
                        radius: tokens.radius.md,
                        blur: tokens.blur.med,
                        scrim: widget.message.isMine
                            ? tokens.colors.accent.withOpacity(0.22)
                            : tokens.colors.bg.withOpacity(0.75),
                        borderColor: tokens.colors.transparent,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.space.s12,
                            vertical: tokens.space.s8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Username with badge
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => _openProfile(
                                      context,
                                      widget.message.userId,
                                    ),
                                    child: Text(
                                      _displayName,
                                      style: tokens.type.caption.copyWith(
                                        color: widget.message.isMine
                                            ? tokens.colors.accent
                                            : tokens.colors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                        decoration: widget.message.isMine
                                            ? null
                                            : TextDecoration.underline,
                                        decorationColor:
                                            tokens.colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (widget.userPresences != null) ...[
                                    SizedBox(width: tokens.space.s6),
                                    _buildPresenceBadge(
                                      widget.message.userId,
                                      widget.userPresences!,
                                    ),
                                  ],
                                ],
                              ),
                              if (widget.message.text.isNotEmpty) ...[
                                SizedBox(height: tokens.space.s4),
                                // Text
                                Text(
                                  widget.message.text,
                                  style: tokens.type.body.copyWith(
                                    color: tokens.colors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (widget.message.reactionCounts.isNotEmpty)
                        Positioned(
                          bottom: -14,
                          right: widget.message.isMine ? 0 : null,
                          left: widget.message.isMine ? null : 0,
                          child: _buildReactionSummary(),
                        ),
                    ],
                  ),
                ),
                // Media is NOT rendered inline in chat messages
                // Media only appears in the top MediaCard
              ],
            ),
          ),
          if (widget.message.isMine && widget.showAvatar) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _openProfile(context, widget.message.userId),
              child: _buildAvatar(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReactionSummary() {
    final tokens = context.tokens;
    final entries = widget.message.reactionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: tokens.space.s6,
      runSpacing: tokens.space.s6,
      children: entries.map((entry) {
        return GlassSurface(
          radius: tokens.radius.pill,
          blur: tokens.blur.low,
          scrim: tokens.card.glassOverlay,
          borderColor: tokens.colors.border,
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.s8,
            vertical: tokens.space.s4,
          ),
          child: Text(
            '${entry.key} ${entry.value}',
            style: tokens.type.caption.copyWith(
              color: tokens.colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showReactionPickerAt(BuildContext context, Offset position) {
    if (widget.onReact == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: widget.availableReactions
          .map(
            (reaction) => PopupMenuItem<String>(
              value: reaction,
              child: Text(
                reaction,
                style: context.tokens.type.body.copyWith(fontSize: 18),
              ),
            ),
          )
          .toList(),
    ).then((selected) {
      if (selected != null) {
        HapticFeedback.selectionClick();
        widget.onReact?.call(selected);
      }
    });
  }

  Widget _buildAvatar() {
    final avatarUrl = _resolvedAvatar ?? widget.message.userAvatar;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar();
          },
        ),
      );
    }
    return _buildDefaultAvatar();
  }

  bool get _isSystemMessage {
    return widget.message.userId == 'system';
  }

  Widget _buildDefaultAvatar() {
    final tokens = context.tokens;
    final avatarEmojis = ['👤', '🍜', '🌟', '🔥', '💚', '👍', '🍺', '☕', '🎨'];
    final avatarIndex = _displayName.hashCode % avatarEmojis.length;
    final avatar = avatarEmojis[avatarIndex.abs()];

    return GlassSurface(
      radius: tokens.radius.pill,
      blur: tokens.blur.low,
      scrim: tokens.colors.accent.withOpacity(0.18),
      borderColor: tokens.colors.accent,
      child: SizedBox(
        width: tokens.space.s32,
        height: tokens.space.s32,
        child: Center(
          child: Text(
            avatar,
            style: tokens.type.body.copyWith(fontSize: 16),
          ),
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, String userId) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatorProfileScreen(userId: userId),
      ),
    );
  }

  /// Build presence badge for user
  Widget _buildPresenceBadge(String userId, Map<String, UserPresence> presences) {
    final tokens = context.tokens;
    final presence = presences[userId];
    if (presence == null) return const SizedBox.shrink();
    
    final service = PresenceService();
    final score = service.calculateScore(presence);
    final badgeType = service.getBadgeType(presence, score, presences);
    
    if (badgeType == null) return const SizedBox.shrink();
    
    return GlassSurface(
      radius: tokens.radius.sm,
      blur: tokens.blur.low,
      scrim: badgeType.color.withOpacity(0.2),
      borderColor: badgeType.color.withOpacity(0.5),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s6,
        vertical: tokens.space.s2,
      ),
      child: Text(
        badgeType.label,
        style: tokens.type.caption.copyWith(
          color: badgeType.color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

