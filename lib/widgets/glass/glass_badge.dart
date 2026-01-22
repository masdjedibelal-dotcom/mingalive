import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import '../../theme/app_tokens.dart';
import 'glass_surface.dart';

enum GlassBadgeVariant { live, online, verified, fresh }

class GlassBadge extends StatelessWidget {
  final String label;
  final GlassBadgeVariant variant;

  const GlassBadge({
    super.key,
    required this.label,
    this.variant = GlassBadgeVariant.live,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = _resolveColor(tokens);

    return GlassSurface(
      radius: tokens.radius.pill,
      blur: tokens.blur.low,
      scrim: color.withOpacity(0.18),
      borderColor: color,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s12,
        vertical: tokens.space.s6,
      ),
      child: Text(
        label,
        style: tokens.type.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Color _resolveColor(AppTokens tokens) {
    switch (variant) {
      case GlassBadgeVariant.online:
        return tokens.badge.online;
      case GlassBadgeVariant.verified:
        return tokens.badge.verified;
      case GlassBadgeVariant.fresh:
        return tokens.badge.fresh;
      case GlassBadgeVariant.live:
        return tokens.badge.live;
    }
  }
}

