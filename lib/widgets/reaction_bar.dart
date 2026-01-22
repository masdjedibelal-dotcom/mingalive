import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

/// Reaction bar widget for displaying and interacting with reactions
class ReactionBar extends StatelessWidget {
  final List<String> availableReactions;
  final String? currentUserReaction; // Current user's selected reaction
  final int totalReactionsCount;
  final Function(String) onReactionTap;

  const ReactionBar({
    super.key,
    this.availableReactions = const ['🔥', '❤️', '😂', '👀'],
    this.currentUserReaction,
    this.totalReactionsCount = 0,
    required this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Total reactions count (if > 0)
        if (totalReactionsCount > 0) ...[
          GlassSurface(
            radius: tokens.radius.pill,
            blur: tokens.blur.low,
            scrim: tokens.card.glassOverlay,
            borderColor: tokens.colors.border,
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space.s8,
              vertical: tokens.space.s4,
            ),
            child: Text(
              '$totalReactionsCount',
              style: tokens.type.caption.copyWith(
                color: tokens.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: tokens.space.s8),
        ],
        // Reaction buttons
        ...availableReactions.map((reaction) {
          final isSelected = currentUserReaction == reaction;
          return Padding(
            padding: EdgeInsets.only(right: tokens.space.s6),
            child: GestureDetector(
              onTap: () => onReactionTap(reaction),
              child: AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: tokens.motion.fast,
                curve: tokens.motion.curve,
                child: GlassSurface(
                  radius: tokens.radius.pill,
                  blur: tokens.blur.low,
                  scrim: isSelected
                      ? tokens.colors.accent.withOpacity(0.2)
                      : tokens.card.glassOverlay,
                  borderColor: isSelected
                      ? tokens.colors.accent
                      : tokens.colors.border,
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space.s12,
                    vertical: tokens.space.s6,
                  ),
                  child: Text(
                    reaction,
                    style: tokens.type.body.copyWith(
                      color: tokens.colors.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

















