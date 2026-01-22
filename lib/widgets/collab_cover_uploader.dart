import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';

class CollabCoverUploader extends StatefulWidget {
  final String? coverUrl;
  final Future<String?> Function(Uint8List bytes, String filename)? onUpload;
  final void Function(Uint8List bytes, String filename)? onLocalSelected;
  final VoidCallback onRemove;

  const CollabCoverUploader({
    super.key,
    this.coverUrl,
    this.onUpload,
    this.onLocalSelected,
    required this.onRemove,
  });

  @override
  State<CollabCoverUploader> createState() => _CollabCoverUploaderState();
}

class _CollabCoverUploaderState extends State<CollabCoverUploader> {
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _localBytes;
  bool _isUploading = false;

  Future<void> _pickMedia() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.tokens.colors.transparent,
      builder: (bottomSheetContext) {
        final tokens = bottomSheetContext.tokens;
        return SafeArea(
          top: false,
          child: GlassSurface(
            radius: tokens.radius.lg,
            blur: tokens.blur.med,
            scrim: tokens.card.glassOverlay,
            borderColor: tokens.colors.border,
            child: Padding(
              padding: EdgeInsets.all(tokens.space.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSheetAction(
                    icon: Icons.image_outlined,
                    label: 'Bild auswählen',
                    onTap: () => Navigator.of(bottomSheetContext).pop('image'),
                  ),
                  SizedBox(height: tokens.space.s8),
                  _buildSheetAction(
                    icon: Icons.videocam_outlined,
                    label: 'Video auswählen',
                    onTap: () => Navigator.of(bottomSheetContext).pop('video'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selection == null) return;

    XFile? file;
    if (selection == 'video') {
      file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final filename = file.name.isNotEmpty ? file.name : 'cover';
    if (widget.onUpload != null) {
      setState(() {
        _isUploading = true;
      });
      final url = await widget.onUpload!(bytes, filename);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        if (url != null) {
          _localBytes = null;
        }
      });
    } else if (widget.onLocalSelected != null) {
      setState(() {
        _localBytes = bytes;
      });
      widget.onLocalSelected!(bytes, filename);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasCover = widget.coverUrl != null || _localBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cover',
          style: tokens.type.body.copyWith(
            color: tokens.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: tokens.space.s8),
        if (hasCover) _buildPreview(),
        SizedBox(height: tokens.space.s8),
        Row(
          children: [
            GlassButton(
              variant: GlassButtonVariant.primary,
              onPressed: _isUploading ? null : _pickMedia,
              label: hasCover ? 'Cover ersetzen' : 'Cover hochladen',
            ),
            SizedBox(width: tokens.space.s12),
            if (hasCover)
              GlassButton(
                variant: GlassButtonVariant.secondary,
                onPressed: _isUploading
                    ? null
                    : () {
                        setState(() {
                          _localBytes = null;
                        });
                        widget.onRemove();
                      },
                label: 'Entfernen',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final url = widget.coverUrl;
    if (_localBytes != null) {
      return _buildPreviewBox(
        child: Image.memory(
          _localBytes!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPreviewFallback();
          },
        ),
      );
    }

    if (url != null && url.isNotEmpty) {
      if (_isVideoUrl(url)) {
        return _buildPreviewBox(child: _buildVideoPlaceholder());
      }
      return _buildPreviewBox(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildPreviewFallback();
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPreviewBox({required Widget child}) {
    final tokens = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (_isUploading)
              Container(
                color: tokens.colors.scrimStrong,
                child: Center(
                  child: CircularProgressIndicator(
                    color: tokens.colors.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewFallback() {
    final tokens = context.tokens;
    return Container(
      color: tokens.colors.surfaceStrong.withOpacity(0.4),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: tokens.colors.textMuted,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    final tokens = context.tokens;
    return Container(
      color: tokens.colors.scrim,
      child: Center(
        child: Icon(
          Icons.play_circle_fill,
          color: tokens.colors.textSecondary,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s12,
          vertical: tokens.space.s8,
        ),
        child: Row(
          children: [
            Icon(icon, color: tokens.colors.textPrimary),
            SizedBox(width: tokens.space.s12),
            Text(
              label,
              style: tokens.type.body.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }
}

