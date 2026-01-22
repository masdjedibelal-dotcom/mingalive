import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/supabase_chat_repository.dart';
import '../services/supabase_gate.dart';
import '../theme/app_theme_extensions.dart';
import '../theme/app_tokens.dart';
import '../widgets/glass/glass_surface.dart';

/// Chat input widget with TextField and Send button
/// Always visible, keyboard-safe, no overlays
class ChatInput extends StatefulWidget {
  final String roomId;
  final String userId;
  final Future<void> Function(String roomId, String userId, String text) onSend;
  final String? placeholder;
  final bool enabled;

  const ChatInput({
    super.key,
    required this.roomId,
    required this.userId,
    required this.onSend,
    this.placeholder,
    this.enabled = true,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Check if user is logged in
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte einloggen, um zu schreiben.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Clear text field immediately for better UX
    _controller.clear();

    try {
      // Call repository sendTextMessage
      await widget.onSend(widget.roomId, widget.userId, text);
    } catch (e) {
      // Restore text on error
      _controller.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nachricht konnte nicht gesendet werden'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handlePickImage() async {
    // Check if user is logged in
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte einloggen, um Bilder zu senden.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!SupabaseGate.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bild-Upload ist nur mit Supabase verfügbar.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // Pick image
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Compress for faster upload
      );

      if (image == null) return; // User cancelled

      // Show uploading state
      setState(() {
        _isUploading = true;
      });

      // Read image bytes
      final Uint8List imageBytes = await image.readAsBytes();
      final filename = image.name;

      // Upload to Supabase Storage bucket "chat_media" under roomId/<timestamp>_<filename>
      final repository = SupabaseChatRepository();
      final mediaUrl = await repository.uploadImage(widget.roomId, imageBytes, filename);

      // Create stream-stage media post (NOT in chat messages)
      await repository.createMediaPost(
        roomId: widget.roomId,
        mediaUrl: mediaUrl,
      );

      // Note: Do NOT attach mediaUrl to chat messages - this is stream-stage only

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bild konnte nicht hochgeladen werden'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = AuthService.instance.currentUser != null;
    final isEnabled = widget.enabled && isLoggedIn;
    final tokens = context.tokens;

    return GlassSurface(
      radius: tokens.radius.sm,
      blur: tokens.blur.med,
      scrim: tokens.colors.bg.withOpacity(0.78),
      borderColor: tokens.colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.s12,
          vertical: tokens.space.s8,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              Expanded(
                child: GlassSurface(
                  radius: tokens.radius.lg,
                  blur: tokens.blur.low,
                  scrim: isEnabled
                      ? tokens.colors.bg.withOpacity(0.7)
                      : tokens.colors.bg.withOpacity(0.5),
                  borderColor: tokens.colors.border,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: isEnabled,
                    style: tokens.type.body.copyWith(
                      color: tokens.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.placeholder ?? 'Schreib etwas…',
                      hintStyle: tokens.type.caption.copyWith(
                        color: tokens.colors.textMuted,
                      ),
                      filled: true,
                      fillColor: tokens.colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radius.lg),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: tokens.space.s12,
                        vertical: tokens.space.s8,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              SizedBox(width: tokens.space.s8),
              _buildIconAction(
                tokens: tokens,
                icon: Icons.photo_camera,
                isLoading: _isUploading,
                onTap: (isEnabled && !_isUploading) ? _handlePickImage : null,
                color: isEnabled
                    ? tokens.colors.textSecondary
                    : tokens.colors.textMuted,
              ),
              SizedBox(width: tokens.space.s8),
              _buildIconAction(
                tokens: tokens,
                icon: Icons.send,
                onTap: (isEnabled && !_isUploading) ? _handleSend : null,
                color: isEnabled
                    ? tokens.colors.accent
                    : tokens.colors.accent.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconAction({
    required AppTokens tokens,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: tokens.space.s32,
        height: tokens.space.s32,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: tokens.space.s16,
                  height: tokens.space.s16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.colors.textPrimary,
                  ),
                )
              : Icon(
                  icon,
                  size: tokens.space.s16,
                  color: color,
                ),
        ),
      ),
    );
  }

}

