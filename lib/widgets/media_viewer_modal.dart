import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'media_carousel.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_button.dart';

class MediaViewerModal extends StatefulWidget {
  final List<MediaCarouselItem> items;
  final int initialIndex;

  const MediaViewerModal({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<MediaViewerModal> createState() => _MediaViewerModalState();
}

class _MediaViewerModalState extends State<MediaViewerModal> {
  final Map<int, VideoPlayerController> _controllers = {};
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _showVideoControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _playVideoForCurrent();
  }

  @override
  void didUpdateWidget(MediaViewerModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.items.length) {
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showVideoControls = !_showVideoControls;
              });
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (index) {
                final previousIndex = _currentIndex;
                setState(() {
                  _currentIndex = index;
                });
                _disposeControllerFor(previousIndex);
                _playVideoForCurrent();
              },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return item.isVideo
                    ? _buildVideo(index, item.url)
                    : _buildImage(item.url);
              },
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: GlassButton(
                variant: GlassButtonVariant.icon,
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(String url) {
    final tokens = context.tokens;
    return InteractiveViewer(
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.image_outlined,
                color: tokens.colors.textMuted,
                size: 48,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideo(int index, String url) {
    final tokens = context.tokens;
    final controller = _controllers.putIfAbsent(
      index,
      () {
        final videoController =
            VideoPlayerController.networkUrl(Uri.parse(url));
        videoController
          ..setLooping(false)
          ..setVolume(1)
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
      return Center(
        child: CircularProgressIndicator(
          color: context.tokens.colors.textSecondary,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        if (_showVideoControls)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: tokens.colors.textPrimary,
                    bufferedColor: tokens.colors.borderStrong,
                    backgroundColor: tokens.colors.border,
                  ),
                ),
                SizedBox(height: tokens.space.s12),
                IconButton(
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: tokens.colors.textPrimary,
                    size: 48,
                  ),
                  onPressed: () {
                    setState(() {
                      if (controller.value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _disposeControllerFor(int index) {
    final controller = _controllers.remove(index);
    controller?.pause();
    controller?.dispose();
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
}



