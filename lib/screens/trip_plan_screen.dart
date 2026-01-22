import 'package:flutter/material.dart';
import 'theme.dart';

/// Screen showing AI-generated trip plan
class TripPlanScreen extends StatelessWidget {
  final Map<String, dynamic> trip;
  final String assistantText;

  const TripPlanScreen({
    super.key,
    required this.trip,
    required this.assistantText,
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
        title: Text(
          'Reiseplan',
          style: MingaTheme.titleMedium,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Assistant text
              if (assistantText.isNotEmpty) ...[
                GlassSurface(
                  radius: 16,
                  blurSigma: 16,
                  overlayColor: MingaTheme.glassOverlayXSoft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      assistantText,
                      style: MingaTheme.body.copyWith(height: 1.5),
                    ),
                  ),
                ),
                SizedBox(height: 24),
              ],
              // Trip duration
              Row(
                children: [
                  Icon(Icons.access_time,
                      color: MingaTheme.textSubtle, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Dauer: ${trip['durationMinutes'] ?? 180} Minuten',
                    style: MingaTheme.body.copyWith(
                      color: MingaTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (trip['startArea'] != null && trip['startArea'].toString().isNotEmpty) ...[
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.location_on,
                        color: MingaTheme.textSubtle, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Start: ${trip['startArea']}',
                      style: MingaTheme.body.copyWith(
                        color: MingaTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              if (trip['themes'] != null && (trip['themes'] as List).isNotEmpty) ...[
                SizedBox(height: 24),
                Text(
                  'Themen:',
                  style: MingaTheme.titleSmall,
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (trip['themes'] as List).map((theme) {
                    return GlassSurface(
                      radius: 16,
                      blurSigma: 12,
                      overlayColor: MingaTheme.accentGreenMuted,
                      borderColor: MingaTheme.accentGreen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          theme.toString(),
                          style: MingaTheme.bodySmall.copyWith(
                            color: MingaTheme.accentGreen,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              SizedBox(height: 32),
              // Coming soon placeholder
              GlassSurface(
                radius: 16,
                blurSigma: 16,
                overlayColor: MingaTheme.glassOverlayXXSoft,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: MingaTheme.textSubtle,
                        size: 48,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Detaillierte Route wird geladen...',
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

