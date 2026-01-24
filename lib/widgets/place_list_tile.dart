import 'package:flutter/material.dart';
import '../models/place.dart';
import '../theme/app_theme_extensions.dart';
import 'place_image.dart';
import '../widgets/place_distance_text.dart';

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

    return Material(
      color: tokens.colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.space.s6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaceImage(
                imageUrl: place.imageUrl,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                borderRadius: tokens.radius.sm,
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
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: tokens.space.s6),
                    PlaceDistanceText(
                      distanceKm: place.distanceKm,
                      style: tokens.type.caption.copyWith(
                        color: tokens.colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: tokens.space.s6),
                    Text(
                      _buildMetaLine(place),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.type.caption.copyWith(
                        color: tokens.colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
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
                        child: Text(
                          hasNote
                              ? 'Beschreibung bearbeiten'
                              : 'Beschreibung hinzufügen',
                          style: tokens.type.caption.copyWith(
                            color: tokens.colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMetaLine(Place place) {
    final parts = <String>[];
    final category = place.category.trim();
    if (category.isNotEmpty) {
      parts.add(category);
    }
    if (parts.isEmpty) return '';
    return parts.join(' · ');
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trim()}…';
  }
}

