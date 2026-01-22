import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../theme/app_theme_extensions.dart';
import '../glass/glass_surface.dart';

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
  final ValueChanged<int>? onExpand;
  final bool autoAdvance;
  final bool showIndicators;
  final bool showCounter;
  final bool showExpandIcon;
  final bool enableVideoAutoplay;
  final bool allowSoundToggle;
  final bool muted;
  final String? gradientKey;
  final Widget? empty;

  const MediaCarousel({
    super.key,
    required this.items,
    this.onPageChanged,
    this.onItemTap,
    this.onExpand,
    this.autoAdvance = true,
    this.showIndicators = true,
    this.showCounter = true,
    this.showExpandIcon = true,
    this.enableVideoAutoplay = true,
    this.allowSoundToggle = true,
    this.muted = true,
    this.gradientKey,
    this.empty,
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
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
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
    if (widget.items.isEmpty) {
      return widget.empty ??
          Container(
            decoration: BoxDecoration(
              gradient: _gradientForKey(widget.gradientKey),
            ),
            child: Center(
              child: Icon(
                Icons.image_outlined,
                color: context.colors.textMuted,
                size: context.space.s32,
              ),
            ),
          );
    }

    final tokens = context.tokens;
    final showExpand = widget.showExpandIcon && widget.onExpand != null;
    final showIndicators = widget.showIndicators && widget.items.length > 1;

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _handleUserInteraction(),
          onLongPressStart: (_) => _handleUserInteraction(),
          onTap: () {
            _handleUserInteraction();
            final nextIndex = _advanceToNext();
            widget.onItemTap?.call(nextIndex);
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
        if (showIndicators)
          Positioned(
            right: tokens.space.s16,
            bottom: tokens.space.s16,
            child: GlassSurface(
              radius: tokens.radius.md,
              blur: tokens.blur.low,
              scrim: tokens.colors.scrim,
              borderColor: tokens.colors.border,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space.s12,
                vertical: tokens.space.s6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showCounter)
                    Padding(
                      padding: EdgeInsets.only(right: tokens.space.s8),
                      child: Text(
                        '${_currentIndex + 1}/${widget.items.length}',
                        style: tokens.type.caption.copyWith(
                          color: tokens.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      widget.items.length,
                      (index) => GestureDetector(
                        onTap: () => _jumpToPage(index),
                        child: Container(
                          width: tokens.space.s6,
                          height: tokens.space.s6,
                          margin: EdgeInsets.symmetric(
                            horizontal: tokens.space.s2,
                          ),
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
                ],
              ),
            ),
          ),
        if (showExpand)
          Positioned(
            top: tokens.space.s12,
            right: tokens.space.s12,
            child: GestureDetector(
              onTap: () => widget.onExpand?.call(_currentIndex),
              child: GlassSurface(
                radius: tokens.radius.sm,
                blur: tokens.blur.low,
                scrim: tokens.colors.scrim,
                borderColor: tokens.colors.border,
                padding: EdgeInsets.all(tokens.space.s6),
                child: Icon(
                  Icons.open_in_full,
                  color: tokens.colors.textSecondary,
                  size: tokens.space.s16,
                ),
              ),
            ),
          ),
        if (widget.allowSoundToggle && _isCurrentVideo)
          Positioned(
            top: tokens.space.s12,
            left: tokens.space.s12,
            child: GestureDetector(
              onTap: _toggleMute,
              child: GlassSurface(
                radius: tokens.radius.sm,
                blur: tokens.blur.low,
                scrim: tokens.colors.scrim,
                borderColor: tokens.colors.border,
                padding: EdgeInsets.all(tokens.space.s6),
                child: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: tokens.colors.textSecondary,
                  size: tokens.space.s16,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImage(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: BoxDecoration(
            gradient: _gradientForKey(widget.gradientKey),
          ),
          child: Center(
            child: Icon(
              Icons.image_outlined,
              color: context.colors.textMuted,
              size: context.space.s32,
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideo(int index, String url) {
    if (index != _currentIndex) {
      return Container(
        decoration: BoxDecoration(
          gradient: _gradientForKey(widget.gradientKey),
        ),
        child: Center(
          child: Icon(
            Icons.play_circle_fill,
            color: context.colors.textMuted,
            size: context.space.s32,
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
          ..setVolume(_muted ? 0 : 1)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            if (_currentIndex == index && widget.enableVideoAutoplay) {
              videoController.play();
            }
          });
        return videoController;
      },
    );

    if (!controller.value.isInitialized) {
      return Center(
        child: SizedBox(
          width: context.space.s20,
          height: context.space.s20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.textSecondary,
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

  bool get _isCurrentVideo {
    if (widget.items.isEmpty) return false;
    return widget.items[_currentIndex].isVideo;
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
    });
    for (final controller in _controllers.values) {
      controller.setVolume(_muted ? 0 : 1);
    }
  }

  void _disposeControllerFor(int index) {
    final controller = _controllers.remove(index);
    controller?.pause();
    controller?.dispose();
  }

  void _playVideoForCurrent() {
    if (!widget.enableVideoAutoplay || widget.items.isEmpty) return;
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
    if (!widget.autoAdvance || widget.items.length <= 1 || _isUserInteracting) {
      return;
    }
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.items.isEmpty) return;
      _advanceToNext();
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
    if (!widget.autoAdvance || widget.items.length <= 1) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _isUserInteracting = false;
      _startAutoAdvance();
    });
  }

  void _snapToNearestPage() {
    if (widget.items.length <= 1) return;
    final page = _pageController.page;
    if (page == null) return;
    final target = page.round();
    if ((page - target).abs() < 0.01) return;
    _pageController.animateToPage(
      target.clamp(0, widget.items.length - 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpToPage(int index) {
    if (widget.items.isEmpty) return;
    final target = index.clamp(0, widget.items.length - 1);
    _handleUserInteraction();
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  int _advanceToNext() {
    if (widget.items.isEmpty || widget.items.length <= 1) {
      return _currentIndex;
    }
    final nextIndex = (_currentIndex + 1) % widget.items.length;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    return nextIndex;
  }

  LinearGradient _gradientForKey(String? key) {
    final gradients = context.tokens.gradients;
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

