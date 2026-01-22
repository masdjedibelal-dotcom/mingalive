import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

/// Display-only activity badge (no interactions)
class ActivityBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ActivityBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GlassSurface(
      radius: tokens.radius.sm,
      blur: tokens.blur.low,
      scrim: color.withOpacity(0.15),
      borderColor: color,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s8,
        vertical: tokens.space.s4,
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
}


