import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

class CollabSavedTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const CollabSavedTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: tokens.radius.md,
        blur: tokens.blur.med,
        scrim: tokens.card.glassOverlay,
        borderColor: tokens.colors.border,
        child: Padding(
          padding: EdgeInsets.all(tokens.space.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(
              'COLLAB',
              style: tokens.type.caption.copyWith(
                color: tokens.colors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: tokens.space.s8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.type.title.copyWith(
                color: tokens.colors.textPrimary,
                height: 1.2,
              ),
            ),
            SizedBox(height: tokens.space.s6),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.type.caption.copyWith(
                  color: tokens.colors.textMuted,
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

