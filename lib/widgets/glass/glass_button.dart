import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import '../../theme/app_tokens.dart';
import 'glass_surface.dart';

enum GlassButtonVariant { primary, secondary, ghost, icon }

class GlassButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final GlassButtonVariant variant;
  final bool isLoading;
  final bool glow;

  const GlassButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.variant = GlassButtonVariant.primary,
    this.isLoading = false,
    this.glow = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDisabled = widget.onPressed == null || widget.isLoading;
    final styles = _resolveStyles(tokens, isDisabled);
    final content = _buildContent(tokens, styles);

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => _setPressed(true),
      onTapUp: isDisabled ? null : (_) => _setPressed(false),
      onTapCancel: isDisabled ? null : () => _setPressed(false),
      onTap: isDisabled ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: tokens.motion.fast,
        curve: tokens.motion.curve,
        child: GlassSurface(
          blurEnabled: widget.variant != GlassButtonVariant.ghost,
          blur: tokens.blur.low,
          scrim: styles.background,
          borderColor: styles.border,
          radius: tokens.button.radius,
          glow: widget.glow && widget.variant == GlassButtonVariant.primary,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.button.height),
            child: Padding(
              padding: styles.padding,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppTokens tokens, _ButtonStyle styles) {
    if (widget.isLoading) {
      return SizedBox(
        width: tokens.space.s16,
        height: tokens.space.s16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: styles.foreground,
        ),
      );
    }

    if (widget.variant == GlassButtonVariant.icon && widget.icon != null) {
      return Icon(widget.icon, color: styles.foreground, size: tokens.space.s20);
    }

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: styles.foreground, size: tokens.space.s16),
          SizedBox(width: tokens.space.s8),
          Text(
            widget.label ?? '',
            style: tokens.type.body.copyWith(
              color: styles.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Text(
      widget.label ?? '',
      style: tokens.type.body.copyWith(
        color: styles.foreground,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  _ButtonStyle _resolveStyles(AppTokens tokens, bool isDisabled) {
    final basePadding = tokens.button.padding;
    if (isDisabled) {
      return _ButtonStyle(
        background: tokens.button.disabledBg,
        foreground: tokens.button.disabledFg,
        border: tokens.colors.border,
        padding: basePadding,
      );
    }

    switch (widget.variant) {
      case GlassButtonVariant.secondary:
        return _ButtonStyle(
          background: tokens.button.secondaryBg,
          foreground: tokens.button.secondaryFg,
          border: tokens.colors.borderStrong,
          padding: basePadding,
        );
      case GlassButtonVariant.ghost:
        return _ButtonStyle(
          background: tokens.colors.transparent,
          foreground: tokens.colors.textPrimary,
          border: tokens.colors.border,
          padding: basePadding,
        );
      case GlassButtonVariant.icon:
        return _ButtonStyle(
          background: tokens.colors.surfaceStrong,
          foreground: tokens.colors.textPrimary,
          border: tokens.colors.border,
          padding: EdgeInsets.all(tokens.space.s8),
        );
      case GlassButtonVariant.primary:
        return _ButtonStyle(
          background: tokens.button.primaryBg,
          foreground: tokens.button.primaryFg,
          border: tokens.colors.borderStrong,
          padding: basePadding,
        );
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }
}

class _ButtonStyle {
  final Color background;
  final Color foreground;
  final Color border;
  final EdgeInsetsGeometry padding;

  const _ButtonStyle({
    required this.background,
    required this.foreground,
    required this.border,
    required this.padding,
  });
}

