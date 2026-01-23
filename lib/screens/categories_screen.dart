import 'package:flutter/material.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import 'list_screen.dart';
import 'main_shell.dart';

/// Screen showing all categories for a specific kind
class CategoriesScreen extends StatelessWidget {
  final String kind;

  const CategoriesScreen({
    super.key,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MingaTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Alle Kategorien',
          style: MingaTheme.titleMedium,
        ),
      ),
      body: CategoriesView(kind: kind),
    );
  }
}

class CategoriesView extends StatefulWidget {
  final String kind;
  final bool showSearchField;

  const CategoriesView({
    super.key,
    required this.kind,
    this.showSearchField = true,
  });

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  final PlaceRepository _repository = PlaceRepository();
  final TextEditingController _searchController = TextEditingController();
  List<String>? _allCategories;
  List<String>? _filteredCategories;
  bool _isLoading = true;
  Map<String, IconData> _iconByCategory = {};
  static const _fallbackIcons = [
    Icons.local_dining,
    Icons.local_pizza,
    Icons.local_cafe,
    Icons.ramen_dining,
    Icons.icecream,
    Icons.bakery_dining,
    Icons.local_bar,
    Icons.park,
    Icons.museum,
    Icons.storefront,
    Icons.nightlife,
    Icons.local_florist,
    Icons.emoji_nature,
    Icons.spa,
    Icons.shopping_bag,
    Icons.map,
    Icons.nightlife,
    Icons.park,
    Icons.museum,
    Icons.storefront,
    Icons.local_florist,
    Icons.emoji_nature,
    Icons.sports_soccer,
    Icons.sports_basketball,
    Icons.sports_tennis,
    Icons.fitness_center,
    Icons.pool,
    Icons.terrain,
    Icons.water,
    Icons.castle,
    Icons.church,
    Icons.attractions,
    Icons.theater_comedy,
    Icons.movie,
    Icons.music_note,
    Icons.art_track,
    Icons.casino,
    Icons.cake,
    Icons.local_drink,
    Icons.breakfast_dining,
    Icons.icecream,
    Icons.set_meal,
    Icons.dining,
    Icons.lunch_dining,
    Icons.local_bar,
    Icons.bakery_dining,
    Icons.shopping_cart,
    Icons.spa,
    Icons.pets,
    Icons.landscape,
    Icons.map_outlined,
    Icons.travel_explore,
  ];
  static const _tilePalettes = [
    [Color(0xFF1D2B64), Color(0xFF1A3F8B)],
    [Color(0xFF145A32), Color(0xFF1D8348)],
    [Color(0xFF512E5F), Color(0xFF6C3483)],
    [Color(0xFF7B241C), Color(0xFF922B21)],
    [Color(0xFF0B5345), Color(0xFF117864)],
    [Color(0xFF512E2E), Color(0xFF784212)],
    [Color(0xFF1B4F72), Color(0xFF21618C)],
    [Color(0xFF4A235A), Color(0xFF5B2C6F)],
    [Color(0xFF3D3B40), Color(0xFF4C4A4F)],
    [Color(0xFF12343B), Color(0xFF2A4F55)],
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _searchController.addListener(_filterCategories);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCategories);
    _searchController.dispose();
    super.dispose();
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase().trim();
    if (_allCategories == null) return;

    if (query.isEmpty) {
      setState(() {
        _filteredCategories = List<String>.from(_allCategories!);
      });
    } else {
      setState(() {
        _filteredCategories = _allCategories!
            .where((category) => category.toLowerCase().contains(query))
            .toList();
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _repository.fetchTopCategories(
        kind: widget.kind,
        limit: 1000, // Get all categories
      );

      // Sort alphabetically
      final sortedCategories = List<String>.from(categories)..sort((a, b) => a.compareTo(b));

      if (mounted) {
        setState(() {
          _allCategories = sortedCategories;
          _filteredCategories = sortedCategories;
          _iconByCategory = _buildIconMap(sortedCategories);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allCategories = [];
          _filteredCategories = [];
          _iconByCategory = {};
          _isLoading = false;
        });
      }
    }
  }

  _CategoryStyle _getCategoryStyle(String category) {
    final palette =
        _tilePalettes[category.hashCode.abs() % _tilePalettes.length];
    final icon = _iconByCategory[category] ??
        (widget.kind == 'sight' ? Icons.place : Icons.category);
    return _CategoryStyle(icon: icon, colors: palette);
  }

  Map<String, IconData> _buildIconMap(List<String> categories) {
    final overrides = <String, IconData>{
      'RAMEN': Icons.ramen_dining,
      'BIERGARTEN': Icons.local_bar,
      'EVENTS': Icons.event,
      'KAFFEE': Icons.local_cafe,
      'CAFE': Icons.local_cafe,
      'COFFEE': Icons.local_cafe,
      'RESTAURANT': Icons.restaurant,
      'PIZZA': Icons.local_pizza,
      'BURGER': Icons.lunch_dining,
      'ICE_CREAM': Icons.icecream,
      'EIS': Icons.icecream,
      'MUSEUM': Icons.museum,
      'PARK': Icons.park,
      'CHURCH': Icons.church,
      'KIRCHE': Icons.church,
      'MONUMENT': Icons.account_tree,
      'BAR': Icons.local_bar,
      'DRINKS': Icons.local_bar,
      'COCKTAIL': Icons.local_bar,
      'SUSHI': Icons.set_meal,
      'STEAK': Icons.dining,
      'FRÜHSTÜCK': Icons.free_breakfast,
      'BREAKFAST': Icons.free_breakfast,
      'DESSERT': Icons.cake,
      'BAKERY': Icons.bakery_dining,
      'BACKEN': Icons.bakery_dining,
      'SHOPPING': Icons.shopping_bag,
      'MARKT': Icons.storefront,
      'MARKET': Icons.storefront,
      'AUSSICHT': Icons.landscape,
      'VIEWPOINT': Icons.landscape,
      'NIGHTLIFE': Icons.nightlife,
      'CLUB': Icons.nightlife,
      'WANDERN': Icons.terrain,
      'HIKING': Icons.terrain,
      'SEE': Icons.water,
      'LAKE': Icons.water,
      'ZOO': Icons.pets,
      'FLOWERS': Icons.local_florist,
      'BLUMEN': Icons.local_florist,
    };
    final used = <IconData>{...overrides.values};
    final icons = _fallbackIcons.where((icon) => !used.contains(icon)).toList();
    var iconIndex = 0;
    final mapping = <String, IconData>{};
    for (final category in categories) {
      final key = category.toUpperCase();
      final override = overrides[key];
      if (override != null) {
        mapping[category] = override;
        continue;
      }
      if (iconIndex < icons.length) {
        mapping[category] = icons[iconIndex];
        iconIndex += 1;
      } else {
        mapping[category] = Icons.category;
      }
    }
    return mapping;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
        if (widget.showSearchField)
          Padding(
            padding: const EdgeInsets.all(20),
            child: GlassSurface(
              radius: 16,
              blurSigma: 16,
              overlayColor: MingaTheme.glassOverlayXSoft,
              child: TextField(
                controller: _searchController,
                style: MingaTheme.body,
                decoration: InputDecoration(
                  hintText: 'Kategorien suchen...',
                  hintStyle: MingaTheme.bodySmall.copyWith(
                    color: MingaTheme.textSubtle,
                  ),
                  prefixIcon:
                      Icon(Icons.search, color: MingaTheme.textSubtle),
                  filled: true,
                  fillColor: MingaTheme.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: MingaTheme.accentGreen,
                    ),
                  )
                : _filteredCategories == null || _filteredCategories!.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.category_outlined,
                              size: 64,
                              color: MingaTheme.textSubtle,
                            ),
                            SizedBox(height: 24),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'Keine Ergebnisse gefunden'
                                  : 'Keine Kategorien gefunden',
                              style: MingaTheme.titleSmall.copyWith(
                                color: MingaTheme.textSubtle,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _filteredCategories!.length,
                        itemBuilder: (context, index) {
                          final category = _filteredCategories![index];
                          final style = _getCategoryStyle(category);
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ListScreen(
                                    categoryName: category,
                                    kind: widget.kind,
                                    openPlaceChat: (placeId) {
                                      MainShell.of(context)
                                          ?.openPlaceChat(placeId);
                                    },
                                  ),
                                ),
                              );
                            },
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: style.colors,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.22),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        style.icon,
                                          size: 38,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                  const SizedBox(height: 6),
                                  Text(
                                    category,
                                    style: MingaTheme.body.copyWith(
                                      color: MingaTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
    );
  }
}

class _CategoryStyle {
  final IconData icon;
  final List<Color> colors;

  const _CategoryStyle({
    required this.icon,
    required this.colors,
  });
}

