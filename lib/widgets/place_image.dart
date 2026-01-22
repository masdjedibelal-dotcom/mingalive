import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';

/// Place image widget with loading shimmer, error handling, and memory optimization
class PlaceImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  const PlaceImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
  });

  /// Calculate cacheWidth based on target size to reduce memory usage
  int? get _cacheWidth {
    if (width == null) return null;
    // Use 240 for small images (< 200px), 480 for larger images
    return width! < 200 ? 240 : 480;
  }

  @override
  Widget build(BuildContext context) {
    // Check if URL is empty or invalid
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context);
    }

    final uri = Uri.tryParse(imageUrl!);
    if (uri == null || !uri.hasScheme) {
      return _buildPlaceholder(context);
    }

    Widget imageWidget = Image.network(
      imageUrl!,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: _cacheWidth,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildShimmer(context);
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildPlaceholder(context);
      },
    );

    // Apply borderRadius if specified
    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// Build shimmer loading placeholder
  Widget _buildShimmer(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.colors.surfaceStrong.withOpacity(0.4),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Stack(
        children: [
          // Shimmer effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tokens.colors.surfaceStrong.withOpacity(0.5),
                    tokens.colors.border.withOpacity(0.2),
                    tokens.colors.surfaceStrong.withOpacity(0.5),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Loading indicator
          Center(
            child: CircularProgressIndicator(
              color: tokens.colors.accent,
              strokeWidth: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// Build error placeholder
  Widget _buildPlaceholder(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.colors.surfaceStrong.withOpacity(0.5),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          Icons.image,
          color: tokens.colors.textMuted,
          size: ((height != null ? height! * 0.3 : 48).clamp(24.0, 80.0)).toDouble(),
        ),
      ),
    );
  }
}

