import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_button.dart';

class AvatarViewerModal extends StatelessWidget {
  final String imageUrl;

  const AvatarViewerModal({
    super.key,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.colors.bg,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    color: tokens.colors.textMuted,
                    size: 64,
                  );
                },
              ),
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
}



