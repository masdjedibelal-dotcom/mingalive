import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import 'glass_text_field.dart';

class GlassSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSearch;
  final bool enabled;
  final bool isLoading;

  const GlassSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.onChanged,
    this.onSearch,
    this.enabled = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GlassTextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      hintText: hintText ?? 'Suche...',
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch?.call(),
      prefixIcon: Icon(
        Icons.search,
        color: tokens.colors.textMuted,
        size: tokens.space.s16,
      ),
      suffixIcon: isLoading
          ? SizedBox(
              width: tokens.space.s16,
              height: tokens.space.s16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.colors.textSecondary,
              ),
            )
          : IconButton(
              icon: Icon(
                Icons.search,
                color: tokens.colors.textSecondary,
                size: tokens.space.s16,
              ),
              onPressed: onSearch,
            ),
    );
  }
}



