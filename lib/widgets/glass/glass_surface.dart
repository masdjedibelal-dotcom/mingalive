import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool blurEnabled;
  final double? blur;
  final double? blurSigma;
  final Color? scrim;
  final Color? overlayColor;
  final Color? borderColor;
  final bool glow;
  final double? radius;
  final List<BoxShadow>? boxShadow;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.blurEnabled = true,
    this.blur,
    this.blurSigma,
    this.scrim,
    this.overlayColor,
    this.borderColor,
    this.glow = false,
    this.radius,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolvedBlur =
        blurEnabled ? (blur ?? blurSigma ?? tokens.blur.med) : 0.0;
    final resolvedRadius = radius ?? tokens.card.radius;
    final resolvedScrim = scrim ?? overlayColor ?? tokens.card.glassOverlay;
    final resolvedBorder = borderColor ?? tokens.colors.border;
    final resolvedShadow = boxShadow ?? (glow ? tokens.shadow.glow : null);

    return ClipRRect(
      borderRadius: BorderRadius.circular(resolvedRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: resolvedBlur, sigmaY: resolvedBlur),
        child: Container(
          decoration: BoxDecoration(
            color: resolvedScrim,
            borderRadius: BorderRadius.circular(resolvedRadius),
            border: Border.all(color: resolvedBorder),
            boxShadow: resolvedShadow,
          ),
          child: padding == null
              ? child
              : Padding(
                  padding: padding!,
                  child: child,
                ),
        ),
      ),
    );
  }
}

