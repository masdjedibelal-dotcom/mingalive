import 'package:flutter/material.dart';
import '../models/place.dart';
import '../theme/app_theme_extensions.dart';
import 'place_image.dart';
import '../widgets/glass/glass_surface.dart';

class PlaceGrid extends StatelessWidget {
  final List<Place> places;
  final String emptyText;
  final ValueChanged<Place>? onPlaceTap;

  const PlaceGrid({
    super.key,
    required this.places,
    required this.emptyText,
    this.onPlaceTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (places.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.space.s32),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: tokens.type.body.copyWith(
              color: tokens.colors.textMuted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s4,
        vertical: tokens.space.s8,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.76,
      ),
      itemCount: places.length,
      itemBuilder: (context, index) {
        final place = places[index];
        return GestureDetector(
          onTap: onPlaceTap == null ? null : () => onPlaceTap!(place),
          child: GlassSurface(
            radius: tokens.radius.md,
            blur: tokens.blur.med,
            scrim: tokens.card.glassOverlay,
            borderColor: tokens.colors.border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(tokens.radius.md),
                    ),
                    child: PlaceImage(
                      imageUrl: place.imageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space.s12,
                    vertical: tokens.space.s8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.type.body.copyWith(
                          color: tokens.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: tokens.space.s4),
                      Text(
                        place.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.type.caption.copyWith(
                          color: tokens.colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}




