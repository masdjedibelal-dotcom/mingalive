import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../theme/app_theme_extensions.dart';
import '../glass/glass_surface.dart';
import 'media_carousel.dart';

class MediaViewer extends StatefulWidget {
  final List<MediaCarouselItem> items;
  final int initialIndex;
  final bool muted;
  final bool allowSoundToggle;

  const MediaViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.muted = true,
    this.allowSoundToggle = true,
  });

  static Future<void> show(
    BuildContext context, {
    required List<MediaCarouselItem> items,
    int initialIndex = 0,
    bool muted = true,
    bool allowSoundToggle = true,
  }) {
    final colors = context.colors;
    return showDialog(
      context: context,
      barrierColor: colors.scrimStrong,
      builder: (_) => MediaViewer(
        items: items,
        initialIndex: initialIndex,
        muted: muted,
        allowSoundToggle: allowSoundToggle,
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  final Map<int, VideoPlayerController> _controllers = {};
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _playVideoForCurrent();
  }

  @override
  void didUpdateWidget(MediaViewer oldWidget) {
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
      backgroundColor: context.colors.bg,
      body: Stack(
        children: [
          GestureDetector(
            onTap: widget.allowSoundToggle && _isCurrentVideo ? _toggleMute : null,
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
            top: tokens.space.s12,
            right: tokens.space.s12,
            child: SafeArea(
              bottom: false,
              child: GlassSurface(
                radius: tokens.radius.sm,
                blur: tokens.blur.low,
                scrim: context.colors.scrim,
                borderColor: context.colors.border,
                padding: EdgeInsets.all(tokens.space.s6),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    color: context.colors.textPrimary,
                    size: tokens.space.s16,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: tokens.space.s12,
            left: tokens.space.s12,
            child: SafeArea(
              bottom: false,
              child: GlassSurface(
                radius: tokens.radius.sm,
                blur: tokens.blur.low,
                scrim: context.colors.scrim,
                borderColor: context.colors.border,
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.space.s12,
                  vertical: tokens.space.s6,
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.items.length}',
                  style: tokens.type.caption.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (widget.allowSoundToggle && _isCurrentVideo)
            Positioned(
              bottom: tokens.space.s16,
              right: tokens.space.s16,
              child: GlassSurface(
                radius: tokens.radius.sm,
                blur: tokens.blur.low,
                scrim: context.colors.scrim,
                borderColor: context.colors.border,
                padding: EdgeInsets.all(tokens.space.s6),
                child: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: context.colors.textSecondary,
                  size: tokens.space.s16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String url) {
    return InteractiveViewer(
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.image_outlined,
                color: context.colors.textMuted,
                size: context.space.s32,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideo(int index, String url) {
    final controller = _controllers.putIfAbsent(
      index,
      () {
        final videoController =
            VideoPlayerController.networkUrl(Uri.parse(url));
        videoController
          ..setLooping(false)
          ..setVolume(_muted ? 0 : 1)
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
          strokeWidth: 2,
          color: context.colors.textSecondary,
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  bool get _isCurrentVideo {
    if (widget.items.isEmpty) return false;
    return widget.items[_currentIndex].isVideo;
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

  void _toggleMute() {
    if (!widget.allowSoundToggle) return;
    setState(() {
      _muted = !_muted;
    });
    for (final controller in _controllers.values) {
      controller.setVolume(_muted ? 0 : 1);
    }
  }
}



