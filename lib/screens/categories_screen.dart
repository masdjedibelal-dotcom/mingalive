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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allCategories = [];
          _filteredCategories = [];
          _isLoading = false;
        });
      }
    }
  }

  IconData _getCategoryIcon(String category) {
    final upperCategory = category.toUpperCase();
    switch (upperCategory) {
      case 'RAMEN':
        return Icons.ramen_dining;
      case 'BIERGARTEN':
        return Icons.local_bar;
      case 'EVENTS':
        return Icons.event;
      case 'KAFFEE':
      case 'CAFE':
      case 'COFFEE':
        return Icons.local_cafe;
      case 'RESTAURANT':
        return Icons.restaurant;
      case 'PIZZA':
        return Icons.local_pizza;
      case 'BURGER':
        return Icons.lunch_dining;
      case 'ICE_CREAM':
      case 'EIS':
        return Icons.icecream;
      case 'MUSEUM':
        return Icons.museum;
      case 'PARK':
        return Icons.park;
      case 'CHURCH':
      case 'KIRCHE':
        return Icons.church;
      case 'MONUMENT':
        return Icons.account_tree;
      default:
        return widget.kind == 'sight' ? Icons.place : Icons.restaurant_menu;
    }
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
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: _filteredCategories!.length,
                        itemBuilder: (context, index) {
                          final category = _filteredCategories![index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ListScreen(
                              categoryName: category,
                                  kind: widget.kind,
                                  openPlaceChat: (placeId) {
                                    MainShell.of(context)?.openPlaceChat(placeId);
                                  },
                            ),
                          ),
                        );
                      },
                      child: GlassSurface(
                        radius: 20,
                        blurSigma: 16,
                        overlayColor: MingaTheme.glassOverlayXSoft,
                        boxShadow: MingaTheme.cardShadow,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getCategoryIcon(category),
                              size: 48,
                              color: MingaTheme.accentGreen,
                            ),
                            SizedBox(height: 12),
                            Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                category.toUpperCase(),
                                style: MingaTheme.label.copyWith(
                                  color: MingaTheme.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
    );
  }
}

