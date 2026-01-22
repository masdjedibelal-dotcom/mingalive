import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../screens/categories_screen.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';

class CategorySearchSheet extends StatefulWidget {
  final String initialKind;
  final ValueChanged<String> onKindChanged;

  const CategorySearchSheet({
    super.key,
    required this.initialKind,
    required this.onKindChanged,
  });

  @override
  State<CategorySearchSheet> createState() => _CategorySearchSheetState();
}

class _CategorySearchSheetState extends State<CategorySearchSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<String> _kinds;

  @override
  void initState() {
    super.initState();
    _kinds = const ['food', 'sight'];
    final initialIndex =
        _kinds.indexOf(widget.initialKind).clamp(0, _kinds.length - 1);
    _tabController = TabController(length: _kinds.length, vsync: this);
    _tabController.index = initialIndex;
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging) {
      final kind = _kinds[_tabController.index];
      widget.onKindChanged(kind);
      if (kDebugMode) {
        debugPrint('CategorySearchSheet: tab changed to $kind');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            SizedBox(height: tokens.space.s12),
            GlassSurface(
              radius: tokens.radius.pill,
              blur: tokens.blur.low,
              scrim: tokens.colors.border,
              borderColor: tokens.colors.transparent,
              child: SizedBox(
                width: tokens.space.s32,
                height: tokens.space.s4,
              ),
            ),
            SizedBox(height: tokens.space.s12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.space.s20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Alle Kategorien entdecken',
                      style: tokens.type.title.copyWith(
                        color: tokens.colors.textPrimary,
                      ),
                    ),
                  ),
                  GlassButton(
                    variant: GlassButtonVariant.icon,
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            SizedBox(height: tokens.space.s8),
            TabBar(
              controller: _tabController,
              indicatorColor: tokens.colors.accent,
              labelColor: tokens.colors.textPrimary,
              unselectedLabelColor: tokens.colors.textMuted,
              labelStyle: tokens.type.body.copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  tokens.type.body.copyWith(color: tokens.colors.textMuted),
              onTap: (index) {
                final kind = _kinds[index];
                widget.onKindChanged(kind);
                if (kDebugMode) {
                  debugPrint('CategorySearchSheet: tab tapped -> $kind');
                }
              },
              tabs: const [
                Tab(text: 'Essen & Trinken'),
                Tab(text: 'Places'),
              ],
            ),
            SizedBox(height: tokens.space.s8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  CategoriesView(kind: 'food', showSearchField: false),
                  CategoriesView(kind: 'sight', showSearchField: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}




