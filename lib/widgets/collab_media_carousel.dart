import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/collab.dart';
import '../theme/app_theme_extensions.dart';
import '../theme/app_tokens.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';

class CollabMediaCarousel extends StatefulWidget {
  final List<CollabMediaItem> items;
  final String? gradientKey;
  final bool showIndicators;
  final bool autoAdvance;
  final ValueChanged<int>? onItemTap;
  final bool showExpandIcon;

  const CollabMediaCarousel({
    super.key,
    required this.items,
    this.gradientKey,
    this.showIndicators = true,
    this.autoAdvance = true,
    this.onItemTap,
    this.showExpandIcon = true,
  });

  @override
  State<CollabMediaCarousel> createState() => _CollabMediaCarouselState();
}

class _CollabMediaCarouselState extends State<CollabMediaCarousel> {
  final Map<String, VideoPlayerController> _videoControllers = {};
  late final PageController _pageController;
  Timer? _autoAdvanceTimer;
  Timer? _resumeTimer;
  int _currentIndex = 0;
  bool _isUserInteracting = false;

  List<CollabMediaItem> get _items => widget.items.limitedForCarousel();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoAdvance();
  }

  @override
  void didUpdateWidget(CollabMediaCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= _items.length) {
      _currentIndex = 0;
    }
    _startAutoAdvance();
  }

  @override
  void deactivate() {
    _pauseAllVideos();
    super.deactivate();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_items.isEmpty) {
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
          onTapDown: (_) => _handleUserInteraction(),
          onLongPressStart: (_) => _handleUserInteraction(),
          onTap: () {
            _handleUserInteraction();
            _advanceToNext();
            widget.onItemTap?.call(_currentIndex);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification ||
                  notification is ScrollUpdateNotification) {
                _handleUserInteraction();
              } else if (notification is ScrollEndNotification) {
                _scheduleResume();
                _snapToNearestPage();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.horizontal,
              physics: const PageScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                _playVideoForCurrent();
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildMediaItem(item);
              },
            ),
          ),
        ),
        if (widget.showIndicators && _items.length > 1)
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
                  _items.length,
                  (index) => GestureDetector(
                    onTap: () => _jumpToPage(index),
                    child: Container(
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
          ),
        if (widget.showExpandIcon && widget.onItemTap != null && _items.isNotEmpty)
          Positioned(
            top: 16,
            right: 16,
            child: GlassButton(
              variant: GlassButtonVariant.icon,
              icon: Icons.open_in_full,
              onPressed: () => widget.onItemTap?.call(_currentIndex),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaItem(CollabMediaItem item) {
    if (item.kind == 'video') {
      return _buildVideo(item);
    }
    return Image.network(
      item.publicUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: BoxDecoration(
            gradient:
                _gradientForKey(context.tokens.gradients, widget.gradientKey),
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
  }

  Widget _buildVideo(CollabMediaItem item) {
    final controller = _videoControllers.putIfAbsent(
      item.id,
      () {
        final videoController =
            VideoPlayerController.networkUrl(Uri.parse(item.publicUrl));
        videoController
          ..setLooping(true)
          ..setVolume(0)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            if (_items[_currentIndex].id == item.id) {
              videoController.play();
            }
          });
        return videoController;
      },
    );

    if (!controller.value.isInitialized) {
      final tokens = context.tokens;
      return GlassSurface(
        radius: tokens.radius.md,
        blur: tokens.blur.low,
        scrim: tokens.card.glassOverlay,
        borderColor: tokens.colors.border,
        child: Center(
          child: Icon(
            Icons.play_circle_fill,
            color: tokens.colors.textSecondary,
            size: 48,
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  void _playVideoForCurrent() {
    if (_items.isEmpty) return;
    final currentItem = _items[_currentIndex.clamp(0, _items.length - 1)];
    _pauseAllVideos(exceptId: currentItem.id);
    if (currentItem.kind == 'video') {
      _videoControllers[currentItem.id]?.play();
    }
  }

  void _pauseAllVideos({String? exceptId}) {
    for (final entry in _videoControllers.entries) {
      if (exceptId != null && entry.key == exceptId) {
        continue;
      }
      entry.value.pause();
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _resumeTimer?.cancel();
    if (!widget.autoAdvance || _items.length <= 1 || _isUserInteracting) return;
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _items.isEmpty) return;
      final nextIndex = (_currentIndex + 1) % _items.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleUserInteraction() {
    _pauseAutoAdvance();
    _scheduleResume();
  }

  void _pauseAutoAdvance() {
    _isUserInteracting = true;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  void _scheduleResume() {
    if (!widget.autoAdvance || _items.length <= 1) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _isUserInteracting = false;
      _startAutoAdvance();
    });
  }

  void _snapToNearestPage() {
    if (_items.length <= 1) return;
    final page = _pageController.page;
    if (page == null) return;
    final target = page.round();
    if ((page - target).abs() < 0.01) return;
    _pageController.animateToPage(
      target.clamp(0, _items.length - 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpToPage(int index) {
    if (_items.isEmpty) return;
    final target = index.clamp(0, _items.length - 1);
    _handleUserInteraction();
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _advanceToNext() {
    if (_items.isEmpty || _items.length <= 1) return;
    final nextIndex = (_currentIndex + 1) % _items.length;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 250),
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

