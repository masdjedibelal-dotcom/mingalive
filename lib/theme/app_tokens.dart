import 'package:flutter/material.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final AppColorTokens colors;
  final AppBlurTokens blur;
  final AppRadiusTokens radius;
  final AppSpacingTokens space;
  final AppShadowTokens shadow;
  final AppMotionTokens motion;
  final AppTypographyTokens type;
  final ButtonTokens button;
  final CardTokens card;
  final ChipTokens chip;
  final InputTokens input;
  final NavTokens nav;
  final SheetTokens sheet;
  final BadgeTokens badge;
  final AppGradientTokens gradients;

  const AppTokens({
    required this.colors,
    required this.blur,
    required this.radius,
    required this.space,
    required this.shadow,
    required this.motion,
    required this.type,
    required this.button,
    required this.card,
    required this.chip,
    required this.input,
    required this.nav,
    required this.sheet,
    required this.badge,
    required this.gradients,
  });

  factory AppTokens.dark() {
    const colors = AppColorTokens.dark();
    const blur = AppBlurTokens(low: 12, med: 22, high: 32);
    const radius = AppRadiusTokens(
      xs: 6,
      sm: 10,
      md: 14,
      lg: 20,
      xl: 28,
      pill: 999,
    );
    const space = AppSpacingTokens();
    final shadow = AppShadowTokens.dark(colors);
    const motion = AppMotionTokens(
      fast: Duration(milliseconds: 140),
      med: Duration(milliseconds: 220),
      slow: Duration(milliseconds: 360),
      curve: Curves.easeOut,
    );
    final type = AppTypographyTokens.dark(colors);
    final button = ButtonTokens.dark(colors, radius, space);
    final card = CardTokens.dark(colors, radius, blur, shadow);
    final chip = ChipTokens.dark(colors, radius, blur);
    final input = InputTokens.dark(colors, radius);
    final nav = NavTokens.dark(colors, radius, blur);
    final sheet = SheetTokens.dark(colors, radius, blur);
    final badge = BadgeTokens.dark(colors);
    final gradients = AppGradientTokens.dark(colors);

    return AppTokens(
      colors: colors,
      blur: blur,
      radius: radius,
      space: space,
      shadow: shadow,
      motion: motion,
      type: type,
      button: button,
      card: card,
      chip: chip,
      input: input,
      nav: nav,
      sheet: sheet,
      badge: badge,
      gradients: gradients,
    );
  }

  factory AppTokens.light() {
    const colors = AppColorTokens.light();
    const blur = AppBlurTokens(low: 10, med: 18, high: 28);
    const radius = AppRadiusTokens(
      xs: 6,
      sm: 10,
      md: 14,
      lg: 20,
      xl: 28,
      pill: 999,
    );
    const space = AppSpacingTokens();
    final shadow = AppShadowTokens.light(colors);
    const motion = AppMotionTokens(
      fast: Duration(milliseconds: 140),
      med: Duration(milliseconds: 220),
      slow: Duration(milliseconds: 360),
      curve: Curves.easeOut,
    );
    final type = AppTypographyTokens.light(colors);
    final button = ButtonTokens.light(colors, radius, space);
    final card = CardTokens.light(colors, radius, blur, shadow);
    final chip = ChipTokens.light(colors, radius, blur);
    final input = InputTokens.light(colors, radius);
    final nav = NavTokens.light(colors, radius, blur);
    final sheet = SheetTokens.light(colors, radius, blur);
    final badge = BadgeTokens.light(colors);
    final gradients = AppGradientTokens.light(colors);

    return AppTokens(
      colors: colors,
      blur: blur,
      radius: radius,
      space: space,
      shadow: shadow,
      motion: motion,
      type: type,
      button: button,
      card: card,
      chip: chip,
      input: input,
      nav: nav,
      sheet: sheet,
      badge: badge,
      gradients: gradients,
    );
  }

  @override
  AppTokens copyWith({
    AppColorTokens? colors,
    AppBlurTokens? blur,
    AppRadiusTokens? radius,
    AppSpacingTokens? space,
    AppShadowTokens? shadow,
    AppMotionTokens? motion,
    AppTypographyTokens? type,
    ButtonTokens? button,
    CardTokens? card,
    ChipTokens? chip,
    InputTokens? input,
    NavTokens? nav,
    SheetTokens? sheet,
    BadgeTokens? badge,
    AppGradientTokens? gradients,
  }) {
    return AppTokens(
      colors: colors ?? this.colors,
      blur: blur ?? this.blur,
      radius: radius ?? this.radius,
      space: space ?? this.space,
      shadow: shadow ?? this.shadow,
      motion: motion ?? this.motion,
      type: type ?? this.type,
      button: button ?? this.button,
      card: card ?? this.card,
      chip: chip ?? this.chip,
      input: input ?? this.input,
      nav: nav ?? this.nav,
      sheet: sheet ?? this.sheet,
      badge: badge ?? this.badge,
      gradients: gradients ?? this.gradients,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      colors: colors.lerp(other.colors, t),
      blur: blur,
      radius: radius,
      space: space,
      shadow: shadow,
      motion: motion,
      type: type,
      button: button,
      card: card,
      chip: chip,
      input: input,
      nav: nav,
      sheet: sheet,
      badge: badge,
      gradients: gradients,
    );
  }
}

@immutable
class AppGradientTokens {
  final LinearGradient mint;
  final LinearGradient calm;
  final LinearGradient sunset;
  final LinearGradient deep;

  const AppGradientTokens({
    required this.mint,
    required this.calm,
    required this.sunset,
    required this.deep,
  });

  factory AppGradientTokens.dark(AppColorTokens colors) {
    return AppGradientTokens(
      mint: LinearGradient(
        colors: [
          colors.accent.withOpacity(0.9),
          colors.accent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      calm: LinearGradient(
        colors: [
          colors.primary.withOpacity(0.8),
          colors.accent.withOpacity(0.6),
          colors.surfaceStrong,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      sunset: LinearGradient(
        colors: [
          colors.warning.withOpacity(0.85),
          colors.accent.withOpacity(0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      deep: LinearGradient(
        colors: [
          colors.surfaceStrong,
          colors.bg,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }

  factory AppGradientTokens.light(AppColorTokens colors) {
    return AppGradientTokens(
      mint: LinearGradient(
        colors: [
          colors.accent.withOpacity(0.8),
          colors.accent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      calm: LinearGradient(
        colors: [
          colors.primary.withOpacity(0.7),
          colors.accent.withOpacity(0.5),
          colors.surfaceStrong,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      sunset: LinearGradient(
        colors: [
          colors.warning.withOpacity(0.8),
          colors.accent.withOpacity(0.6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      deep: LinearGradient(
        colors: [
          colors.surfaceStrong,
          colors.bg,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }
}

@immutable
class AppColorTokens {
  final Color bg;
  final Color surface;
  final Color surfaceStrong;
  final Color primary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderStrong;
  final Color scrim;
  final Color scrimStrong;
  final Color glow;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color transparent;

  const AppColorTokens({
    required this.bg,
    required this.surface,
    required this.surfaceStrong,
    required this.primary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.scrim,
    required this.scrimStrong,
    required this.glow,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.transparent,
  });

  const AppColorTokens.dark()
      : bg = const Color(0xFF0B0D12),
        surface = const Color(0xFF12161D),
        surfaceStrong = const Color(0xFF18202A),
        primary = const Color(0xFF2E7D5A),
        accent = const Color(0xFF45C27E),
        textPrimary = Colors.white,
        textSecondary = const Color(0xD9FFFFFF),
        textMuted = const Color(0x99FFFFFF),
        border = const Color(0x22FFFFFF),
        borderStrong = const Color(0x3DFFFFFF),
        scrim = const Color(0xB3000000),
        scrimStrong = const Color(0xE6000000),
        glow = const Color(0xFF45C27E),
        success = const Color(0xFF45C27E),
        warning = const Color(0xFFFF8A3D),
        danger = const Color(0xFFFF5A5F),
        info = const Color(0xFF4DA3FF),
        transparent = Colors.transparent;

  const AppColorTokens.light()
      : bg = const Color(0xFFF6F7F9),
        surface = const Color(0xFFFFFFFF),
        surfaceStrong = const Color(0xFFF0F2F5),
        primary = const Color(0xFF2D5A27),
        accent = const Color(0xFF2D8A4F),
        textPrimary = const Color(0xFF0F1115),
        textSecondary = const Color(0xB3000000),
        textMuted = const Color(0x80000000),
        border = const Color(0x1A000000),
        borderStrong = const Color(0x33000000),
        scrim = const Color(0x66000000),
        scrimStrong = const Color(0x99000000),
        glow = const Color(0xFF2D8A4F),
        success = const Color(0xFF2D8A4F),
        warning = const Color(0xFFFF7A1A),
        danger = const Color(0xFFE5484D),
        info = const Color(0xFF4DA3FF),
        transparent = Colors.transparent;

  AppColorTokens lerp(AppColorTokens other, double t) {
    return AppColorTokens(
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceStrong:
          Color.lerp(surfaceStrong, other.surfaceStrong, t) ?? surfaceStrong,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      textPrimary:
          Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      border: Color.lerp(border, other.border, t) ?? border,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      scrim: Color.lerp(scrim, other.scrim, t) ?? scrim,
      scrimStrong:
          Color.lerp(scrimStrong, other.scrimStrong, t) ?? scrimStrong,
      glow: Color.lerp(glow, other.glow, t) ?? glow,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      info: Color.lerp(info, other.info, t) ?? info,
      transparent: Colors.transparent,
    );
  }
}

@immutable
class AppBlurTokens {
  final double low;
  final double med;
  final double high;

  const AppBlurTokens({required this.low, required this.med, required this.high});
}

@immutable
class AppRadiusTokens {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double pill;

  const AppRadiusTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
  });
}

@immutable
class AppSpacingTokens {
  final double s2;
  final double s4;
  final double s6;
  final double s8;
  final double s12;
  final double s16;
  final double s20;
  final double s24;
  final double s32;

  const AppSpacingTokens({
    this.s2 = 2,
    this.s4 = 4,
    this.s6 = 6,
    this.s8 = 8,
    this.s12 = 12,
    this.s16 = 16,
    this.s20 = 20,
    this.s24 = 24,
    this.s32 = 32,
  });
}

@immutable
class AppShadowTokens {
  final List<BoxShadow> soft;
  final List<BoxShadow> med;
  final List<BoxShadow> strong;
  final List<BoxShadow> glow;

  const AppShadowTokens({
    required this.soft,
    required this.med,
    required this.strong,
    required this.glow,
  });

  factory AppShadowTokens.dark(AppColorTokens colors) {
    return AppShadowTokens(
      soft: [
        BoxShadow(
          color: colors.scrim.withOpacity(0.22),
          blurRadius: 10,
          offset: const Offset(0, 6),
        ),
      ],
      med: [
        BoxShadow(
          color: colors.scrim.withOpacity(0.32),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
      strong: [
        BoxShadow(
          color: colors.scrim.withOpacity(0.45),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
      glow: [
        BoxShadow(
          color: colors.glow.withOpacity(0.18),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  factory AppShadowTokens.light(AppColorTokens colors) {
    return AppShadowTokens(
      soft: [
        BoxShadow(
          color: colors.borderStrong,
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
      med: [
        BoxShadow(
          color: colors.borderStrong,
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
      strong: [
        BoxShadow(
          color: colors.borderStrong,
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      glow: [
        BoxShadow(
          color: colors.glow.withOpacity(0.16),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}

@immutable
class AppMotionTokens {
  final Duration fast;
  final Duration med;
  final Duration slow;
  final Curve curve;

  const AppMotionTokens({
    required this.fast,
    required this.med,
    required this.slow,
    required this.curve,
  });
}

@immutable
class AppTypographyTokens {
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle caption;

  const AppTypographyTokens({
    required this.title,
    required this.headline,
    required this.body,
    required this.caption,
  });

  factory AppTypographyTokens.dark(AppColorTokens colors) {
    return AppTypographyTokens(
      title: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.3,
      ),
      headline: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
        letterSpacing: -0.5,
      ),
      body: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: colors.textPrimary,
      ),
      caption: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textMuted,
      ),
    );
  }

  factory AppTypographyTokens.light(AppColorTokens colors) {
    return AppTypographyTokens(
      title: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.3,
      ),
      headline: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
        letterSpacing: -0.5,
      ),
      body: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: colors.textPrimary,
      ),
      caption: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textMuted,
      ),
    );
  }
}

@immutable
class ButtonTokens {
  final double height;
  final EdgeInsets padding;
  final double radius;
  final Color primaryBg;
  final Color primaryFg;
  final Color secondaryBg;
  final Color secondaryFg;
  final Color disabledBg;
  final Color disabledFg;

  const ButtonTokens({
    required this.height,
    required this.padding,
    required this.radius,
    required this.primaryBg,
    required this.primaryFg,
    required this.secondaryBg,
    required this.secondaryFg,
    required this.disabledBg,
    required this.disabledFg,
  });

  factory ButtonTokens.dark(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppSpacingTokens space,
  ) {
    return ButtonTokens(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: space.s16, vertical: space.s12),
      radius: radius.md,
      primaryBg: colors.primary,
      primaryFg: colors.textPrimary,
      secondaryBg: colors.surfaceStrong,
      secondaryFg: colors.textPrimary,
      disabledBg: colors.border,
      disabledFg: colors.textMuted,
    );
  }

  factory ButtonTokens.light(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppSpacingTokens space,
  ) {
    return ButtonTokens(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: space.s16, vertical: space.s12),
      radius: radius.md,
      primaryBg: colors.primary,
      primaryFg: colors.textPrimary,
      secondaryBg: colors.surfaceStrong,
      secondaryFg: colors.textPrimary,
      disabledBg: colors.border,
      disabledFg: colors.textMuted,
    );
  }
}

@immutable
class CardTokens {
  final double radius;
  final double blur;
  final Color glassOverlay;
  final Color border;
  final List<BoxShadow> shadow;
  final Color solidBg;
  final Color mediaScrim;

  const CardTokens({
    required this.radius,
    required this.blur,
    required this.glassOverlay,
    required this.border,
    required this.shadow,
    required this.solidBg,
    required this.mediaScrim,
  });

  factory CardTokens.dark(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
    AppShadowTokens shadow,
  ) {
    return CardTokens(
      radius: radius.lg,
      blur: blur.med,
      glassOverlay: colors.bg.withOpacity(0.72),
      border: colors.textPrimary.withOpacity(0.12),
      shadow: shadow.med,
      solidBg: colors.surface,
      mediaScrim: colors.scrim,
    );
  }

  factory CardTokens.light(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
    AppShadowTokens shadow,
  ) {
    return CardTokens(
      radius: radius.lg,
      blur: blur.med,
      glassOverlay: colors.surfaceStrong.withOpacity(0.7),
      border: colors.border,
      shadow: shadow.soft,
      solidBg: colors.surface,
      mediaScrim: colors.scrim,
    );
  }
}

@immutable
class ChipTokens {
  final double radius;
  final double blur;
  final Color bg;
  final Color border;
  final Color selectedBg;
  final Color selectedBorder;
  final Color text;

  const ChipTokens({
    required this.radius,
    required this.blur,
    required this.bg,
    required this.border,
    required this.selectedBg,
    required this.selectedBorder,
    required this.text,
  });

  factory ChipTokens.dark(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return ChipTokens(
      radius: radius.pill,
      blur: blur.low,
      bg: colors.bg.withOpacity(0.6),
      border: colors.textPrimary.withOpacity(0.12),
      selectedBg: colors.accent.withOpacity(0.16),
      selectedBorder: colors.accent.withOpacity(0.5),
      text: colors.textPrimary,
    );
  }

  factory ChipTokens.light(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return ChipTokens(
      radius: radius.pill,
      blur: blur.low,
      bg: colors.surfaceStrong.withOpacity(0.7),
      border: colors.border,
      selectedBg: colors.accent.withOpacity(0.16),
      selectedBorder: colors.accent.withOpacity(0.5),
      text: colors.textPrimary,
    );
  }
}

@immutable
class InputTokens {
  final double radius;
  final Color fill;
  final Color border;
  final Color focusRingColor;
  final double focusRingWidth;
  final Color errorColor;

  const InputTokens({
    required this.radius,
    required this.fill,
    required this.border,
    required this.focusRingColor,
    required this.focusRingWidth,
    required this.errorColor,
  });

  factory InputTokens.dark(AppColorTokens colors, AppRadiusTokens radius) {
    return InputTokens(
      radius: radius.md,
      fill: colors.bg.withOpacity(0.7),
      border: colors.textPrimary.withOpacity(0.12),
      focusRingColor: colors.accent,
      focusRingWidth: 1.5,
      errorColor: colors.danger,
    );
  }

  factory InputTokens.light(AppColorTokens colors, AppRadiusTokens radius) {
    return InputTokens(
      radius: radius.md,
      fill: colors.surfaceStrong.withOpacity(0.8),
      border: colors.border,
      focusRingColor: colors.accent,
      focusRingWidth: 1.5,
      errorColor: colors.danger,
    );
  }
}

@immutable
class NavTokens {
  final double radius;
  final double blur;
  final Color scrim;
  final double bottomBarHeight;
  final double bottomOffset;

  const NavTokens({
    required this.radius,
    required this.blur,
    required this.scrim,
    required this.bottomBarHeight,
    required this.bottomOffset,
  });

  factory NavTokens.dark(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return NavTokens(
      radius: radius.md,
      blur: blur.high,
      scrim: colors.transparent,
      bottomBarHeight: 58,
      bottomOffset: 8,
    );
  }

  factory NavTokens.light(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return NavTokens(
      radius: radius.md,
      blur: blur.high,
      scrim: colors.transparent,
      bottomBarHeight: 58,
      bottomOffset: 8,
    );
  }
}

@immutable
class SheetTokens {
  final double radius;
  final Color scrim;
  final double blur;
  final EdgeInsets padding;
  final Color handleColor;
  final double handleWidth;
  final double handleHeight;
  final double handleRadius;

  const SheetTokens({
    required this.radius,
    required this.scrim,
    required this.blur,
    required this.padding,
    required this.handleColor,
    required this.handleWidth,
    required this.handleHeight,
    required this.handleRadius,
  });

  factory SheetTokens.dark(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return SheetTokens(
      radius: radius.lg,
      scrim: colors.scrimStrong,
      blur: blur.med,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      handleColor: colors.borderStrong,
      handleWidth: 42,
      handleHeight: 4,
      handleRadius: radius.xs,
    );
  }

  factory SheetTokens.light(
    AppColorTokens colors,
    AppRadiusTokens radius,
    AppBlurTokens blur,
  ) {
    return SheetTokens(
      radius: radius.lg,
      scrim: colors.scrimStrong,
      blur: blur.med,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      handleColor: colors.borderStrong,
      handleWidth: 42,
      handleHeight: 4,
      handleRadius: radius.xs,
    );
  }
}

@immutable
class BadgeTokens {
  final Color live;
  final Color online;
  final Color verified;
  final Color fresh;

  const BadgeTokens({
    required this.live,
    required this.online,
    required this.verified,
    required this.fresh,
  });

  factory BadgeTokens.dark(AppColorTokens colors) {
    return BadgeTokens(
      live: colors.accent,
      online: colors.success,
      verified: colors.info,
      fresh: colors.warning,
    );
  }

  factory BadgeTokens.light(AppColorTokens colors) {
    return BadgeTokens(
      live: colors.accent,
      online: colors.success,
      verified: colors.info,
      fresh: colors.warning,
    );
  }
}

