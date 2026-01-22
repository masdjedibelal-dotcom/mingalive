import 'package:flutter/material.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_gate.dart';
import '../data/place_repository.dart';
import 'theme.dart';

Future<bool> showAddSpotsToCollabSheet({
  required BuildContext context,
  required String collabId,
}) async {
  final currentUser = AuthService.instance.currentUser;
  if (currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bitte einloggen, um Spots hinzuzufügen.'),
        duration: Duration(seconds: 2),
      ),
    );
    return false;
  }

  if (!SupabaseGate.isEnabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Spots sind nur mit Supabase verfügbar.'),
        duration: Duration(seconds: 2),
      ),
    );
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MingaTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bottomSheetContext) {
      return _AddSpotsToCollabSheet(collabId: collabId);
    },
  );

  return result == true;
}

class _AddSpotsToCollabSheet extends StatefulWidget {
  final String collabId;

  const _AddSpotsToCollabSheet({
    required this.collabId,
  });

  @override
  State<_AddSpotsToCollabSheet> createState() => _AddSpotsToCollabSheetState();
}

class _AddSpotsToCollabSheetState extends State<_AddSpotsToCollabSheet> {
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final PlaceRepository _placeRepository = PlaceRepository();
  final TextEditingController _searchController = TextEditingController();
  List<Place> _places = [];
  List<String> _existingPlaceIds = [];
  final Set<String> _selectedPlaceIds = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPlaces();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      return;
    }
    try {
      final places =
          await _placeRepository.fetchFavorites(userId: currentUser.id);
      final existing = await _collabsRepository.fetchCollabPlaceIds(
        collabId: widget.collabId,
      );
      if (mounted) {
        setState(() {
          _places = places;
          _existingPlaceIds = existing;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    setState(() {});
  }

  List<Place> get _filteredPlaces {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _places;
    }
    return _places.where((place) {
      return place.name.toLowerCase().contains(query) ||
          place.category.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _confirmSelection() async {
    if (_selectedPlaceIds.isEmpty) return;
    setState(() {
      _isSaving = true;
    });
    try {
      await _collabsRepository.addPlacesToCollab(
        collabId: widget.collabId,
        placeIds: _selectedPlaceIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konnte Spots nicht hinzufügen.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 20,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlay,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MingaTheme.borderStrong,
                    borderRadius: BorderRadius.circular(MingaTheme.radiusXs),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Spots hinzufügen',
                style: MingaTheme.titleMedium,
              ),
              SizedBox(height: 12),
              TextField(
                controller: _searchController,
                style: MingaTheme.body,
                decoration: InputDecoration(
                  hintText: 'Suche in deinen gespeicherten Orten',
                  hintStyle: MingaTheme.bodySmall.copyWith(
                    color: MingaTheme.textSubtle,
                  ),
                  prefixIcon:
                      Icon(Icons.search, color: MingaTheme.textSubtle),
                  filled: true,
                  fillColor: MingaTheme.glassOverlay,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            SizedBox(height: 12),
            if (_isLoading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: MingaTheme.accentGreen,
                  ),
                ),
              )
            else if (_places.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Noch keine gespeicherten Orte.',
                  style: MingaTheme.bodySmall.copyWith(
                    color: MingaTheme.textSubtle,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _filteredPlaces.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: MingaTheme.borderSubtle),
                  itemBuilder: (context, index) {
                    final place = _filteredPlaces[index];
                    final isInCollab = _existingPlaceIds.contains(place.id);
                    final isSelected = _selectedPlaceIds.contains(place.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        place.name,
                        style: MingaTheme.body,
                      ),
                      subtitle: Text(
                        place.category,
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                      ),
                      trailing: isInCollab
                          ? Icon(
                              Icons.check,
                              color: MingaTheme.accentGreen,
                            )
                          : Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPlaceIds.add(place.id);
                                  } else {
                                    _selectedPlaceIds.remove(place.id);
                                  }
                                });
                              },
                              activeColor: MingaTheme.accentGreen,
                              checkColor: MingaTheme.buttonLightForeground,
                            ),
                      onTap: isInCollab
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selectedPlaceIds.remove(place.id);
                                } else {
                                  _selectedPlaceIds.add(place.id);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _isSaving || _selectedPlaceIds.isEmpty ? null : _confirmSelection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MingaTheme.accentGreen,
                  disabledBackgroundColor: MingaTheme.glassOverlaySoft,
                ),
                child: Text(
                  _isSaving ? 'Hinzufügen…' : 'Ausgewählte hinzufügen',
                  style: MingaTheme.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}




