import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import 'glass_surface.dart';

class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final String? errorText;
  final bool enabled;
  final bool obscureText;
  final int? maxLines;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  const GlassTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.errorText,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final borderColor =
        hasError ? tokens.input.errorColor : tokens.colors.border;

    return GlassSurface(
      radius: tokens.input.radius,
      blur: tokens.blur.low,
      scrim: tokens.input.fill,
      borderColor: borderColor,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscureText,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: tokens.type.body.copyWith(color: tokens.colors.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          labelText: labelText,
          errorText: errorText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: tokens.colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.input.radius),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.input.radius),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.input.radius),
            borderSide: BorderSide(
              color: tokens.input.focusRingColor,
              width: tokens.input.focusRingWidth,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.input.radius),
            borderSide: BorderSide(
              color: tokens.input.errorColor,
              width: tokens.input.focusRingWidth,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.input.radius),
            borderSide: BorderSide(
              color: tokens.input.errorColor,
              width: tokens.input.focusRingWidth,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: tokens.space.s16,
            vertical: tokens.space.s12,
          ),
          hintStyle: tokens.type.caption.copyWith(
            color: tokens.colors.textMuted,
          ),
          labelStyle: tokens.type.caption.copyWith(
            color: tokens.colors.textMuted,
          ),
          errorStyle: tokens.type.caption.copyWith(
            color: tokens.input.errorColor,
          ),
        ),
      ),
    );
  }
}

