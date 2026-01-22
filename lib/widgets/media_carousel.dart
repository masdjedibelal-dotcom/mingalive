import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_surface.dart';

class MediaCarouselItem {
  final String url;
  final bool isVideo;

  const MediaCarouselItem({
    required this.url,
    required this.isVideo,
  });
}

class MediaCarousel extends StatefulWidget {
  final List<MediaCarouselItem> items;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onItemTap;

  const MediaCarousel({
    super.key,
    required this.items,
    this.onPageChanged,
    this.onItemTap,
  });

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  final Map<int, VideoPlayerController> _controllers = {};
  late final PageController _pageController;
  Timer? _autoAdvanceTimer;
  Timer? _resumeTimer;
  int _currentIndex = 0;
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoAdvance();
  }

  @override
  void didUpdateWidget(MediaCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.items.length) {
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
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (widget.items.isEmpty) {
      return GlassSurface(
        radius: tokens.radius.md,
        blur: tokens.blur.low,
        scrim: tokens.card.glassOverlay,
        borderColor: tokens.colors.border,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: tokens.colors.textMuted,
            size: 48,
          ),
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
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.horizontal,
              physics: const PageScrollPhysics(),
              itemCount: widget.items.length,
              onPageChanged: (index) {
                final previousIndex = _currentIndex;
                setState(() {
                  _currentIndex = index;
                });
                _disposeControllerFor(previousIndex);
                _playVideoForCurrent();
                widget.onPageChanged?.call(index);
              },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return item.isVideo
                    ? _buildVideo(index, item.url)
                    : _buildImage(item.url);
              },
            ),
          ),
        ),
        if (widget.items.length > 1)
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
                  widget.items.length,
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
      ],
    );
  }

  Widget _buildImage(String url) {
    final tokens = context.tokens;
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return GlassSurface(
          radius: tokens.radius.md,
          blur: tokens.blur.low,
          scrim: tokens.card.glassOverlay,
          borderColor: tokens.colors.border,
          child: Center(
            child: Icon(
              Icons.image_outlined,
              color: tokens.colors.textMuted,
              size: 48,
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideo(int index, String url) {
    final tokens = context.tokens;
    if (index != _currentIndex) {
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

    final controller = _controllers.putIfAbsent(
      index,
      () {
        final videoController =
            VideoPlayerController.networkUrl(Uri.parse(url));
        videoController
          ..setLooping(true)
          ..setVolume(0)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            if (_currentIndex == index) {
              videoController.play();
            }
          });
        return videoController;
      },
    );

    if (!controller.value.isInitialized) {
      return GlassSurface(
        radius: tokens.radius.md,
        blur: tokens.blur.low,
        scrim: tokens.card.glassOverlay,
        borderColor: tokens.colors.border,
        child: Center(
          child: CircularProgressIndicator(
            color: tokens.colors.textSecondary,
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

  void _disposeControllerFor(int index) {
    final controller = _controllers.remove(index);
    controller?.pause();
    controller?.dispose();
  }

  void _advanceToNext() {
    if (widget.items.isEmpty) return;
    if (widget.items.length == 1) return;
    final nextIndex = (_currentIndex + 1) % widget.items.length;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _playVideoForCurrent() {
    if (widget.items.isEmpty) return;
    final item = widget.items[_currentIndex];
    if (!item.isVideo) {
      _pauseAllVideos();
      return;
    }
    for (final entry in _controllers.entries) {
      if (entry.key != _currentIndex) {
        entry.value.pause();
      }
    }
    _controllers[_currentIndex]?.play();
  }

  void _pauseAllVideos() {
    for (final controller in _controllers.values) {
      controller.pause();
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _resumeTimer?.cancel();
    if (widget.items.length <= 1 || _isUserInteracting) return;
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.items.isEmpty) return;
      final nextIndex = (_currentIndex + 1) % widget.items.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleUserInteraction() {
    _isUserInteracting = true;
    _autoAdvanceTimer?.cancel();
    _scheduleResume();
  }

  void _scheduleResume() {
    if (widget.items.length <= 1) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _isUserInteracting = false;
      _startAutoAdvance();
    });
  }
}


