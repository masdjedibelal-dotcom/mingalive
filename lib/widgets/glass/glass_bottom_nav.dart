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
  final VoidCallback? onSearch;
  final List<GlassBottomNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onSearch,
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
          final tabBar = GlassSurface(
            radius: tokens.nav.radius,
            blur: tokens.nav.blur,
            scrim: tokens.colors.transparent,
            borderColor: tokens.colors.border,
            boxShadow: tokens.shadow.med,
            child: SizedBox(
              height: tokens.nav.bottomBarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(visibleIndices.length, (index) {
                  final itemIndex = visibleIndices[index];
                  final item = items[itemIndex];
                  final isSelected = itemIndex == currentIndex;
                  final activeFill = tokens.colors.accent.withOpacity(0.2);
                  final activeBorder = tokens.colors.accent.withOpacity(0.5);

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
                              BorderRadius.circular(tokens.radius.sm),
                          border: Border.all(
                            color: isSelected
                                ? activeBorder
                                : tokens.colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Semantics(
                            label: item.label,
                            child: Icon(
                              item.icon,
                              size: tokens.space.s20,
                              color: isSelected
                                  ? tokens.colors.textPrimary
                                  : tokens.colors.textSecondary,
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

          return Row(
            children: [
              Expanded(child: tabBar),
              SizedBox(width: tokens.space.s12),
              GestureDetector(
                onTap: onSearch,
                child: GlassSurface(
                  radius: tokens.nav.radius,
                  blur: tokens.nav.blur,
                  scrim: tokens.colors.transparent,
                  borderColor: tokens.colors.border,
                  boxShadow: tokens.shadow.med,
                  child: SizedBox(
                    height: tokens.nav.bottomBarHeight,
                    width: tokens.nav.bottomBarHeight,
                    child: Icon(
                      Icons.search,
                      size: tokens.space.s20,
                      color: tokens.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

