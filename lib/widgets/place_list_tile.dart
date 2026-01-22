import 'package:flutter/material.dart';
import '../models/place.dart';
import '../theme/app_theme_extensions.dart';
import 'place_distance_text.dart';
import 'place_image.dart';
import '../widgets/glass/glass_surface.dart';

class PlaceListTile extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;
  final String? note;
  final bool isNoteExpanded;
  final VoidCallback? onToggleNote;
  final VoidCallback? onEditNote;

  const PlaceListTile({
    super.key,
    required this.place,
    required this.onTap,
    this.note,
    this.isNoteExpanded = false,
    this.onToggleNote,
    this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final noteText = note?.trim() ?? '';
    final hasNote = noteText.isNotEmpty;
    final showToggle = hasNote && noteText.length > 120;
    final previewText = hasNote && !isNoteExpanded
        ? _truncate(noteText, 120)
        : noteText;

    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: tokens.radius.lg,
        blur: tokens.blur.med,
        scrim: tokens.card.glassOverlay,
        borderColor: tokens.colors.border,
        child: Padding(
          padding: EdgeInsets.all(tokens.space.s12),
          child: Row(
            children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius.md),
              child: SizedBox(
                width: 74,
                height: 74,
                child: PlaceImage(
                  imageUrl: place.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(width: tokens.space.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.title.copyWith(
                      color: tokens.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: tokens.space.s6),
                  Text(
                    place.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.type.caption.copyWith(
                      color: tokens.colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (place.distanceKm != null) ...[
                    SizedBox(height: tokens.space.s4),
                    PlaceDistanceText(distanceKm: place.distanceKm),
                  ],
                  if (hasNote) ...[
                    SizedBox(height: tokens.space.s6),
                    Text(
                      previewText,
                      maxLines: isNoteExpanded ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.caption.copyWith(
                        color: tokens.colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    if (showToggle) ...[
                      SizedBox(height: tokens.space.s4),
                      GestureDetector(
                        onTap: onToggleNote,
                        child: Text(
                          isNoteExpanded ? 'Weniger' : 'Weiterlesen',
                          style: tokens.type.caption.copyWith(
                            color: tokens.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (onEditNote != null) ...[
                    SizedBox(height: tokens.space.s6),
                    GestureDetector(
                      onTap: onEditNote,
                      child: GlassSurface(
                        radius: tokens.radius.sm,
                        blur: tokens.blur.low,
                        scrim: tokens.card.glassOverlay,
                        borderColor: tokens.colors.border,
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.space.s8,
                          vertical: tokens.space.s4,
                        ),
                        child: Text(
                          hasNote ? 'Notiz bearbeiten' : 'Notiz hinzufügen',
                          style: tokens.type.caption.copyWith(
                            color: tokens.colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: tokens.colors.textMuted,
            ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trim()}…';
  }
}

