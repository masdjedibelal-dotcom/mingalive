import 'package:flutter/material.dart';
import 'app_tokens.dart';

class AppTheme {
  static ThemeData dark() {
    final tokens = AppTokens.dark();
    return _build(tokens);
  }

  static ThemeData light() {
    final tokens = AppTokens.light();
    return _build(tokens);
  }

  static ThemeData _build(AppTokens tokens) {
    final colors = tokens.colors;
    final type = tokens.type;
    final chip = tokens.chip;
    final card = tokens.card;
    final input = tokens.input;
    final sheet = tokens.sheet;

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bg,
      primaryColor: colors.primary,
      colorScheme: ColorScheme.dark(
        primary: colors.primary,
        onPrimary: colors.textPrimary,
        secondary: colors.accent,
        onSecondary: colors.textPrimary,
        error: colors.danger,
        onError: colors.textPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        background: colors.bg,
        onBackground: colors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.transparent,
        selectedItemColor: colors.textPrimary,
        unselectedItemColor: colors.textMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chip.bg,
        selectedColor: chip.selectedBg,
        disabledColor: colors.border,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s12,
          vertical: tokens.space.s6,
        ),
        labelStyle: type.caption.copyWith(color: chip.text),
        secondaryLabelStyle: type.caption.copyWith(color: chip.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chip.radius),
          side: BorderSide(color: chip.border),
        ),
      ),
      cardTheme: CardThemeData(
        color: card.solidBg,
        elevation: 0,
        shadowColor: colors.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(card.radius),
          side: BorderSide(color: card.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 0.5,
        space: tokens.space.s12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input.fill,
        hintStyle: type.caption.copyWith(color: colors.textMuted),
        labelStyle: type.caption.copyWith(color: colors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(input.radius),
          borderSide: BorderSide(color: input.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(input.radius),
          borderSide: BorderSide(color: input.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(input.radius),
          borderSide: BorderSide(
            color: input.focusRingColor,
            width: input.focusRingWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(input.radius),
          borderSide: BorderSide(
            color: input.errorColor,
            width: input.focusRingWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(input.radius),
          borderSide: BorderSide(
            color: input.errorColor,
            width: input.focusRingWidth,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space.s16,
          vertical: tokens.space.s12,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.transparent,
        modalBackgroundColor: colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheet.radius),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary),
      textTheme: TextTheme(
        titleLarge: type.headline,
        titleMedium: type.title,
        bodyMedium: type.body,
        bodySmall: type.caption,
      ),
      extensions: [tokens],
    );
  }
}

