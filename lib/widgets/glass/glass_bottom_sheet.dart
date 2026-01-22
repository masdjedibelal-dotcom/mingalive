import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import 'glass_surface.dart';

Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  final sheet = context.sheet;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: context.colors.transparent,
    barrierColor: sheet.scrim,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(sheet.radius),
      ),
    ),
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      final resolvedPadding = sheet.padding.copyWith(
        bottom: sheet.padding.bottom + bottomInset,
      );
      return SafeArea(
        top: false,
        child: GlassSurface(
          radius: sheet.radius,
          blur: sheet.blur,
          scrim: context.colors.surface,
          borderColor: context.colors.border,
          child: Padding(
            padding: resolvedPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: sheet.handleWidth,
                  height: sheet.handleHeight,
                  decoration: BoxDecoration(
                    color: sheet.handleColor,
                    borderRadius: BorderRadius.circular(sheet.handleRadius),
                  ),
                ),
                SizedBox(height: context.space.s12),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}



