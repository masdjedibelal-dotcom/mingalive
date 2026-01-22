import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import 'glass_surface.dart';

class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final chip = tokens.chip;
    final border = selected ? chip.selectedBorder : chip.border;
    final background = selected ? chip.selectedBg : chip.bg;
    final glow = selected;

    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: chip.radius,
        blur: chip.blur,
        scrim: background,
        borderColor: border,
        glow: glow,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s12,
          vertical: tokens.space.s8,
        ),
        child: Text(
          label,
          style: tokens.type.caption.copyWith(
            color: chip.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

