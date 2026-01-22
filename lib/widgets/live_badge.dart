import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

/// Reusable live badge with pulsing animation
class LiveBadge extends StatefulWidget {
  final int liveCount;
  final bool compact;
  final Color? badgeColor;
  final Color? dotColor;
  final bool showIcon;
  final bool reverseText; // For "X LEUTE LIVE" format

  const LiveBadge({
    super.key,
    required this.liveCount,
    this.compact = false,
    this.badgeColor,
    this.dotColor,
    this.showIcon = false,
    this.reverseText = false,
  });

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Slower, more subtle
    )..repeat(reverse: true);

    // Subtle scale animation (0.95 to 1.0 for very gentle pulse)
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Subtle opacity animation (0.85 to 1.0)
    _opacityAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolvedBadgeColor = widget.badgeColor ?? tokens.badge.live;
    final resolvedDotColor = widget.dotColor ?? tokens.colors.textPrimary;
    if (widget.compact) {
      // Compact version: just dot + "Live" text
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: GlassSurface(
                    radius: tokens.radius.pill,
                    blur: tokens.blur.low,
                    scrim: resolvedBadgeColor.withOpacity(0.2),
                    borderColor: resolvedBadgeColor,
                    glow: true,
                    child: SizedBox(
                      width: tokens.space.s8,
                      height: tokens.space.s8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: resolvedBadgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const SizedBox.shrink(), // Child cached for performance
          ),
          SizedBox(width: tokens.space.s6),
          Text(
            'Live',
            style: tokens.type.caption.copyWith(
              color: resolvedBadgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // Full version: badge with "LIVE • X" or "LIVE • X LEUTE" or "X LEUTE LIVE"
    final text = widget.reverseText
        ? (widget.liveCount > 0 ? "${widget.liveCount} LEUTE LIVE" : "LIVE")
        : (widget.liveCount > 0
            ? "LIVE • ${widget.liveCount} LEUTE"
            : "LIVE");

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: GlassSurface(
              radius: widget.reverseText ? tokens.radius.pill : tokens.radius.lg,
              blur: tokens.blur.low,
              scrim: resolvedBadgeColor.withOpacity(0.18),
              borderColor: resolvedBadgeColor,
              glow: true,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space.s12,
                vertical: tokens.space.s6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showIcon) ...[
                    Icon(
                      Icons.whatshot,
                      size: tokens.space.s16,
                      color: resolvedDotColor,
                    ),
                    SizedBox(width: tokens.space.s8),
                  ],
                  if (!widget.reverseText) ...[
                    SizedBox(
                      width: tokens.space.s8,
                      height: tokens.space.s8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: resolvedDotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.space.s6),
                  ],
                  Text(
                    text,
                    style: tokens.type.caption.copyWith(
                      color: resolvedDotColor,
                      fontWeight:
                          widget.reverseText ? FontWeight.w800 : FontWeight.w700,
                      letterSpacing: widget.reverseText ? 1.2 : 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: const SizedBox.shrink(), // Child cached for performance
    );
  }
}

