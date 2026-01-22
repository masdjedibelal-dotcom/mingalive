import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';

class PlaceDistanceText extends StatelessWidget {
  final double? distanceKm;
  final TextStyle? style;

  const PlaceDistanceText({
    super.key,
    required this.distanceKm,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final value = distanceKm;
    if (value == null) {
      return const SizedBox.shrink();
    }
    return Text(
      '${value.toStringAsFixed(1)} km',
      style: style ??
          tokens.type.body.copyWith(
            color: tokens.colors.textMuted,
          ),
    );
  }
}

