import 'package:flutter/material.dart';
import 'theme.dart';
import '../models/place.dart';
import 'detail_screen.dart';
import 'main_shell.dart';
import '../widgets/live_badge.dart';
import '../widgets/place_distance_text.dart';

/// Screen showing search results for a query
class SearchResultsScreen extends StatelessWidget {
  final String query;
  final List<Place> results;

  const SearchResultsScreen({
    super.key,
    required this.query,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MingaTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suchergebnisse',
              style: MingaTheme.titleMedium,
            ),
            if (query.isNotEmpty)
              Text(
                '"$query"',
                style: MingaTheme.textMuted.copyWith(fontSize: 14),
              ),
          ],
        ),
      ),
      body: results.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final place = results[index];
                return _buildResultCard(context: context, place: place);
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final suggestedQueries = ['ramen', 'biergarten', 'live'];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: MingaTheme.textSubtle,
            ),
            SizedBox(height: 24),
            Text(
              'Keine Ergebnisse gefunden',
              style: MingaTheme.titleSmall,
            ),
            SizedBox(height: 12),
            Text(
              'Versuche es mit einer anderen Suche',
              style: MingaTheme.textMuted.copyWith(fontSize: 14),
            ),
            SizedBox(height: 32),
            Text(
              'Vorschläge:',
              style: MingaTheme.textMuted,
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: suggestedQueries.map((suggestion) {
                return GestureDetector(
                  onTap: () {
                    // Pop back and trigger search with suggestion
                    Navigator.of(context).pop(suggestion);
                  },
                  child: GlassSurface(
                    radius: MingaTheme.cardRadius,
                    blurSigma: 16,
                    overlayColor: MingaTheme.glassOverlayXXSoft,
                    borderColor: MingaTheme.accentGreenBorderSoft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        suggestion,
                        style: MingaTheme.textMuted.copyWith(
                          color: MingaTheme.accentGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required BuildContext context,
    required Place place,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassSurface(
        radius: MingaTheme.cardRadius,
        blurSigma: 18,
        overlayColor: MingaTheme.glassOverlay,
        boxShadow: MingaTheme.cardShadow,
        child: Material(
          color: MingaTheme.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(MingaTheme.cardRadius),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DetailScreen(
                    place: place,
                    openPlaceChat: (placeId) {
                      MainShell.of(context)?.openPlaceChat(placeId);
                    },
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quadratisches Bild
                  ClipRRect(
                  borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                    child: Image.network(
                      place.imageUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 80,
                          height: 80,
                        color: MingaTheme.skeletonFill,
                          child: Icon(
                            Icons.image,
                          color: MingaTheme.textSubtle,
                            size: 40,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  // Name, Entfernung und Live-Indikator
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                place.name,
                                style: MingaTheme.titleSmall.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (place.isLive)
                              LiveBadge(
                                liveCount: place.liveCount,
                                compact: true,
                              ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            if (place.distanceKm != null) ...[
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: MingaTheme.textSubtle,
                              ),
                              SizedBox(width: 4),
                            ],
                            PlaceDistanceText(distanceKm: place.distanceKm),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

