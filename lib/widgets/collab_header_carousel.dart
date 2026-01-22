import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../theme/app_tokens.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';

class CollabHeaderCarousel extends StatefulWidget {
  final List<String> mediaUrls;
  final String? gradientKey;
  final VoidCallback? onExpandTap;
  final ValueChanged<int>? onIndexChanged;

  const CollabHeaderCarousel({
    super.key,
    required this.mediaUrls,
    this.gradientKey,
    this.onExpandTap,
    this.onIndexChanged,
  });

  @override
  State<CollabHeaderCarousel> createState() => _CollabHeaderCarouselState();
}

class _CollabHeaderCarouselState extends State<CollabHeaderCarousel> {
  int _currentIndex = 0;
  late final PageController _pageController;
  Timer? _autoAdvanceTimer;

  @override
  void didUpdateWidget(CollabHeaderCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.mediaUrls.length) {
      _currentIndex = 0;
    }
    _startAutoAdvance();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasMedia = widget.mediaUrls.isNotEmpty;
    if (!hasMedia) {
      return Container(
        decoration: BoxDecoration(
          gradient: _gradientForKey(tokens.gradients, widget.gradientKey),
        ),
      );
    }

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _advanceToNext,
          onLongPress: widget.onExpandTap,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                _snapToNearestPage();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                widget.onIndexChanged?.call(index);
              },
              itemBuilder: (context, index) {
                final url = widget.mediaUrls[index];
                return Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: _gradientForKey(
                          context.tokens.gradients,
                          widget.gradientKey,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: context.tokens.colors.textMuted,
                          size: 48,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (widget.mediaUrls.length > 1)
          Positioned(
            right: 16,
            bottom: 16,
            child: GlassSurface(
              radius: tokens.radius.pill,
              blur: tokens.blur.low,
              scrim: tokens.card.glassOverlay,
              borderColor: tokens.colors.border,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space.s12,
                vertical: tokens.space.s6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  widget.mediaUrls.length,
                  (index) => Container(
                    width: tokens.space.s6,
                    height: tokens.space.s6,
                    margin: EdgeInsets.symmetric(horizontal: tokens.space.s2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentIndex
                          ? tokens.colors.textPrimary
                          : tokens.colors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.onExpandTap != null && widget.mediaUrls.isNotEmpty)
          Positioned(
            top: 16,
            right: 16,
            child: GlassButton(
              variant: GlassButtonVariant.icon,
              icon: Icons.open_in_full,
              onPressed: widget.onExpandTap,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (widget.mediaUrls.length <= 1) return;
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _advanceToNext();
    });
  }

  void _advanceToNext() {
    if (widget.mediaUrls.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % widget.mediaUrls.length;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _snapToNearestPage() {
    if (widget.mediaUrls.length <= 1) return;
    final page = _pageController.page;
    if (page == null) return;
    final target = page.round();
    if ((page - target).abs() < 0.01) return;
    _pageController.animateToPage(
      target.clamp(0, widget.mediaUrls.length - 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  LinearGradient _gradientForKey(AppGradientTokens gradients, String? key) {
    switch (key) {
      case 'mint':
        return gradients.mint;
      case 'calm':
        return gradients.calm;
      case 'sunset':
        return gradients.sunset;
      default:
        return gradients.deep;
    }
  }
}




