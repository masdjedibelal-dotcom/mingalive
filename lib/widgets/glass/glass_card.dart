import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import '../../theme/app_tokens.dart';
import 'glass_surface.dart';

enum GlassCardVariant { glass, solid, media }

class GlassCard extends StatelessWidget {
  final Widget child;
  final GlassCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final bool glow;
  final double? radius;
  final double? blurSigma;
  final Color? overlayColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.variant = GlassCardVariant.glass,
    this.padding,
    this.glow = false,
    this.radius,
    this.blurSigma,
    this.overlayColor,
    this.borderColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolvedPadding = padding ?? _paddingFor(tokens);
    final resolvedRadius = radius ?? tokens.card.radius;
    final resolvedBlur = blurSigma ?? tokens.card.blur;
    final resolvedOverlay = overlayColor ?? tokens.card.glassOverlay;
    final resolvedBorder = borderColor ?? tokens.colors.border;
    final resolvedShadow = boxShadow ?? (glow ? tokens.shadow.glow : null);

    switch (variant) {
      case GlassCardVariant.solid:
        return Container(
          padding: resolvedPadding,
          decoration: BoxDecoration(
            color: tokens.card.solidBg,
            borderRadius: BorderRadius.circular(resolvedRadius),
            border: Border.all(color: resolvedBorder),
            boxShadow: resolvedShadow ?? tokens.shadow.soft,
          ),
          child: child,
        );
      case GlassCardVariant.media:
        return GlassSurface(
          radius: resolvedRadius,
          blur: resolvedBlur,
          scrim: resolvedOverlay,
          borderColor: resolvedBorder,
          boxShadow: resolvedShadow,
          glow: glow,
          padding: resolvedPadding,
          child: child,
        );
      case GlassCardVariant.glass:
        return GlassSurface(
          radius: resolvedRadius,
          blur: resolvedBlur,
          scrim: resolvedOverlay,
          borderColor: resolvedBorder,
          boxShadow: resolvedShadow,
          glow: glow,
          padding: resolvedPadding,
          child: child,
        );
    }
  }

  EdgeInsetsGeometry _paddingFor(AppTokens tokens) {
    switch (variant) {
      case GlassCardVariant.media:
        return EdgeInsets.all(tokens.space.s12);
      case GlassCardVariant.solid:
      case GlassCardVariant.glass:
        return EdgeInsets.all(tokens.space.s16);
    }
  }
}

