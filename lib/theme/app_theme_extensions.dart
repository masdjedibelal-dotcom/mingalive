import 'package:flutter/material.dart';
import 'app_tokens.dart';

extension AppThemeX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.dark();

  AppColorTokens get colors => tokens.colors;
  AppBlurTokens get blur => tokens.blur;
  AppRadiusTokens get radius => tokens.radius;
  AppSpacingTokens get space => tokens.space;
  AppShadowTokens get shadow => tokens.shadow;
  AppMotionTokens get motion => tokens.motion;
  AppTypographyTokens get type => tokens.type;
  ButtonTokens get button => tokens.button;
  CardTokens get card => tokens.card;
  ChipTokens get chip => tokens.chip;
  InputTokens get input => tokens.input;
  NavTokens get nav => tokens.nav;
  SheetTokens get sheet => tokens.sheet;
  BadgeTokens get badge => tokens.badge;
  AppGradientTokens get gradients => tokens.gradients;
}

