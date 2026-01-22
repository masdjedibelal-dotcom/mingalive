import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

export '../widgets/glass/glass_surface.dart';
export '../widgets/glass/glass_card.dart';
export '../widgets/glass/glass_chip.dart';
export '../widgets/glass/glass_button.dart';

/// Backwards-compatible theme accessors mapping to AppTokens.
/// This keeps legacy screens working while using the single token source.
class MingaTheme {
  static final AppTokens _tokens = AppTokens.dark();

  // Colors
  static Color get background => _tokens.colors.bg;
  static Color get transparent => _tokens.colors.transparent;
  static Color get accentGreen => _tokens.colors.accent;
  static Color get surface => _tokens.colors.surface;
  static Color get hotOrange => _tokens.colors.warning;
  static Color get glowGreen => _tokens.colors.success;
  static Color get glowOrange => _tokens.colors.warning;
  static Color get accentGreenSoft => _tokens.colors.accent.withOpacity(0.18);
  static Color get accentGreenMuted => _tokens.colors.accent.withOpacity(0.12);
  static Color get accentGreenBorder => _tokens.colors.accent.withOpacity(0.35);
  static Color get accentGreenStrong => _tokens.colors.accent;
  static Color get accentGreenOverlay => _tokens.colors.accent.withOpacity(0.22);
  static Color get accentGreenBorderStrong => _tokens.colors.accent.withOpacity(0.7);
  static Color get accentGreenBorderSoft => _tokens.colors.accent.withOpacity(0.3);
  static Color get accentGreenFill => _tokens.colors.accent.withOpacity(0.25);
  static Color get glowGreenStrong => _tokens.colors.success;
  static Color get infoBlue => _tokens.colors.info;
  static Color get dangerRed => _tokens.colors.danger;
  static Color get successGreen => _tokens.colors.success;
  static Color get warningOrange => _tokens.colors.warning;
  static Color get buttonLightBackground => _tokens.colors.surfaceStrong;
  static Color get buttonLightForeground => _tokens.colors.textPrimary;
  static Color get textPrimary => _tokens.colors.textPrimary;
  static Color get textSecondary => _tokens.colors.textSecondary;
  static Color get textSubtle => _tokens.colors.textMuted;
  static Color get borderSubtle => _tokens.colors.border;
  static Color get borderMuted => _tokens.colors.border;
  static Color get borderStrong => _tokens.colors.borderStrong;
  static Color get borderEmphasis => _tokens.colors.borderStrong;
  static Color get glassOverlaySoft => _tokens.card.glassOverlay.withOpacity(0.6);
  static Color get glassOverlay => _tokens.card.glassOverlay;
  static Color get glassOverlayStrong => _tokens.card.glassOverlay.withOpacity(1.0);
  static Color get glassOverlayUltraSoft => _tokens.card.glassOverlay.withOpacity(0.4);
  static Color get glassOverlayXSoft => _tokens.card.glassOverlay.withOpacity(0.5);
  static Color get glassOverlayXXSoft => _tokens.card.glassOverlay.withOpacity(0.45);
  static Color get darkOverlaySoft => _tokens.colors.scrim;
  static Color get darkOverlay => _tokens.colors.scrimStrong;
  static Color get darkOverlayMedium => _tokens.colors.scrimStrong;
  static Color get darkOverlayStrong => _tokens.colors.scrimStrong;
  static Color get skeletonFill => _tokens.colors.border;
  static Color get skeletonFillStrong => _tokens.colors.borderStrong;

  // Radii
  static double get cardRadius => _tokens.card.radius;
  static double get chipRadius => _tokens.chip.radius;
  static double get pillRadius => _tokens.radius.pill;
  static double get radiusSm => _tokens.radius.sm;
  static double get radiusMd => _tokens.radius.md;
  static double get radiusLg => _tokens.radius.lg;
  static double get radiusXl => _tokens.radius.xl;
  static double get radiusRound => _tokens.radius.pill;
  static double get radiusXs => _tokens.radius.xs;
  static double get bottomNavHeight => _tokens.nav.bottomBarHeight;

  // Motion
  static Duration get motionFast => _tokens.motion.fast;
  static Duration get motionStandard => _tokens.motion.med;
  static Curve get motionCurve => _tokens.motion.curve;

  // Shadows
  static List<BoxShadow> get cardShadow => _tokens.shadow.med;
  static List<BoxShadow> get cardShadowStrong => _tokens.shadow.strong;
  static List<BoxShadow> get glowShadowGreen => _tokens.shadow.glow;
  static List<BoxShadow> get avatarGlowShadow => _tokens.shadow.glow;

  // Typography
  static TextStyle get titleLarge => _tokens.type.headline;
  static TextStyle get displayLarge => _tokens.type.headline;
  static TextStyle get titleMedium => _tokens.type.title;
  static TextStyle get titleSmall =>
      _tokens.type.body.copyWith(fontWeight: FontWeight.w700);
  static TextStyle get textMuted =>
      _tokens.type.caption.copyWith(color: _tokens.colors.textMuted);
  static TextStyle get body => _tokens.type.body;
  static TextStyle get bodySmall =>
      _tokens.type.caption.copyWith(color: _tokens.colors.textSecondary);
  static TextStyle get label => _tokens.type.caption.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      );

  static List<Color> get shareGradient => _tokens.gradients.deep.colors;

  static ThemeData get darkTheme => AppTheme.dark();
}

