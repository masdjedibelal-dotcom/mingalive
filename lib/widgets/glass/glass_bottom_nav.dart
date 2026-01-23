import 'package:flutter/material.dart';
import '../../theme/app_theme_extensions.dart';
import 'glass_surface.dart';

class GlassBottomNavItem {
  final IconData icon;
  final String label;

  const GlassBottomNavItem({
    required this.icon,
    required this.label,
  });
}

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassBottomNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final visibleIndices =
        List<int>.generate(items.length, (index) => index);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space.s12,
        tokens.space.s4,
        tokens.space.s12,
        bottomInset > 0 ? bottomInset : tokens.space.s8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GlassSurface(
            radius: tokens.radius.pill,
            blurEnabled: true,
            blur: tokens.blur.low,
            scrim: const Color(0xFF121212).withOpacity(0.9),
            borderColor: const Color(0x0DFFFFFF),
            boxShadow: const [],
            child: SizedBox(
              height: 62,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(visibleIndices.length, (index) {
                  final itemIndex = visibleIndices[index];
                  final item = items[itemIndex];
                  final isSelected = itemIndex == currentIndex;
                  final activeFill = tokens.colors.surfaceStrong;
                  final labelColor = isSelected
                      ? tokens.colors.accent
                      : tokens.colors.textSecondary;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onTap(itemIndex),
                      child: AnimatedContainer(
                        duration: tokens.motion.med,
                        curve: tokens.motion.curve,
                        margin: EdgeInsets.symmetric(
                          horizontal: tokens.space.s2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? activeFill
                              : tokens.colors.transparent,
                          borderRadius:
                              BorderRadius.circular(tokens.radius.pill),
                          border: Border.all(
                            color: tokens.colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Semantics(
                            label: item.label,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: tokens.space.s20,
                                  color: labelColor,
                                ),
                                SizedBox(height: tokens.space.s2),
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens.type.caption.copyWith(
                                    color: labelColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

