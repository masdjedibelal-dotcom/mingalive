import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';
import '../data/place_repository.dart';
import '../models/place.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/auth_service.dart';
import '../widgets/place_image.dart';
import '../widgets/place_list_tile.dart';
import '../widgets/glass/glass_bottom_sheet.dart';
import '../widgets/glass/glass_text_field.dart';
import '../widgets/glass/glass_button.dart';

class CollabCreateScreen extends StatefulWidget {
  const CollabCreateScreen({super.key});

  @override
  State<CollabCreateScreen> createState() => _CollabCreateScreenState();
}

class _CollabCreateScreenState extends State<CollabCreateScreen> {
  static const int _noteMaxChars = 120;

  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final PlaceRepository _placeRepository = PlaceRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;
  final List<_PendingMedia> _pendingMedia = [];
  bool _isUploadingMedia = false;
  List<Place> _selectedPlaces = [];
  Map<String, String> _placeNotes = {};
  final Set<String> _expandedNoteKeys = {};

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onPreviewChanged);
    _descriptionController.addListener(_onPreviewChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onPreviewChanged);
    _descriptionController.removeListener(_onPreviewChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onPreviewChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einen Titel eingeben'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final placeIds = _selectedPlaces.map((place) => place.id).toList();

    final collab = await _collabsRepository.createCollab(
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      isPublic: _isPublic,
      coverMediaUrls: const [],
      placeIds: placeIds,
    );

    if (!mounted) return;
    if (collab != null && _pendingMedia.isNotEmpty) {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        final urls = <String>[];
        for (final media in _pendingMedia) {
          final item = await _collabsRepository.addCollabMediaItem(
            collabId: collab.id,
            userId: currentUser.id,
            bytes: media.bytes,
            filename: media.filename,
          );
          if (item != null) {
            urls.add(item.publicUrl);
          }
        }
        if (urls.isNotEmpty) {
          await _collabsRepository.updateCollab(
            collabId: collab.id,
            coverMediaUrls: urls,
          );
        }
      }
    }

    if (collab != null && _placeNotes.isNotEmpty) {
      for (final entry in _placeNotes.entries) {
        final note = entry.value.trim();
        if (note.isEmpty) continue;
        await _collabsRepository.updateCollabPlaceNote(
          collabId: collab.id,
          placeId: entry.key,
          note: note,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });

    if (collab != null) {
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fehler beim Erstellen des Collabs'),
        duration: Duration(seconds: 2),
        backgroundColor: MingaTheme.dangerRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      appBar: AppBar(
        backgroundColor: MingaTheme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: MingaTheme.textPrimary),
        title: Text(
          'Neuen Collab erstellen',
          style: MingaTheme.titleSmall,
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(
              _isSaving ? 'Speichern…' : 'Speichern',
              style: MingaTheme.body.copyWith(
                color: MingaTheme.accentGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildCollabPreview(),
          SizedBox(height: 16),
          GlassSurface(
            radius: 16,
            blurSigma: 16,
            overlayColor: MingaTheme.glassOverlayXSoft,
            child: TextField(
              controller: _titleController,
              style: MingaTheme.body,
              decoration: InputDecoration(
                labelText: 'Titel',
                labelStyle: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
                filled: true,
                fillColor: MingaTheme.transparent,
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(height: 16),
          GlassSurface(
            radius: 16,
            blurSigma: 16,
            overlayColor: MingaTheme.glassOverlayXSoft,
            borderColor: MingaTheme.transparent,
            child: TextField(
              controller: _descriptionController,
              style: MingaTheme.body,
              maxLines: 4,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: 'Beschreibung',
                labelStyle: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
                hintText: 'Warum hast du diese Spots gesammelt?',
                hintStyle: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
                filled: true,
                fillColor: MingaTheme.transparent,
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(height: 8),
          GlassSurface(
            radius: 16,
            blurSigma: 16,
            overlayColor: MingaTheme.glassOverlayXSoft,
            child: SwitchListTile(
              value: _isPublic,
              onChanged: (value) {
                setState(() {
                  _isPublic = value;
                });
              },
              title: Text(
                'Collab öffentlich machen',
                style: MingaTheme.body,
              ),
              subtitle: Text(
                'Öffentliche Collabs können von anderen entdeckt werden.',
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          _buildMediaSection(),
          SizedBox(height: 16),
          _buildSpotsSection(),
        ],
      ),
    );
  }

  Widget _buildCollabPreview() {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final spotCount = _selectedPlaces.length;
    return GlassSurface(
      radius: 18,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlayXSoft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MingaTheme.glassOverlaySoft,
                    borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                  ),
                  child: Text(
                    'Vorschau',
                    style: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (_pendingMedia.length > 1)
                  Text(
                    '1/${_pendingMedia.length}',
                    style: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSubtle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                      child: SizedBox(
                        width: 72,
                        height: 96,
                        child: _pendingMedia.isNotEmpty
                            ? _buildPendingThumbnail(_pendingMedia.first)
                            : Container(
                                color: MingaTheme.glassOverlaySoft,
                                child: Icon(
                                  Icons.collections,
                                  color: MingaTheme.textSubtle,
                                ),
                              ),
                      ),
                    ),
                    if (_pendingMedia.length > 1)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MingaTheme.darkOverlayMedium,
                            borderRadius:
                                BorderRadius.circular(MingaTheme.radiusSm),
                          ),
                          child: Text(
                            '+${_pendingMedia.length - 1}',
                            style: MingaTheme.bodySmall.copyWith(
                              color: MingaTheme.textPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                    title.isEmpty ? 'Deine Collab' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MingaTheme.titleSmall.copyWith(
                          color: MingaTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description.isEmpty
                            ? 'Kurze Beschreibung deiner Liste.'
                            : description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        spotCount == 0
                            ? 'Noch keine Spots'
                            : '$spotCount Spots',
                        style: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Medien',
              style: MingaTheme.titleSmall,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pendingMedia.length >= 5 || _isUploadingMedia
                  ? null
                  : _addMedia,
              icon: Icon(Icons.add, color: MingaTheme.accentGreen),
              label: Text(
                'Hinzufügen',
                style: MingaTheme.body.copyWith(
                  color: MingaTheme.accentGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        if (_pendingMedia.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Bis zu 5 Medien für das Cover.',
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              onReorder: _reorderMedia,
              itemCount: _pendingMedia.length,
              itemBuilder: (context, index) {
                final item = _pendingMedia[index];
                return Container(
                  key: ValueKey(item.id),
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: _buildPendingThumbnail(item),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => _removePending(item),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: MingaTheme.darkOverlayMedium,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: MingaTheme.textPrimary,
                            ),
                          ),
                        ),
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

  Widget _buildSpotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Spots',
              style: MingaTheme.titleSmall,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _showSpotPicker,
              icon: Icon(Icons.add, color: MingaTheme.accentGreen),
              label: Text(
                'Hinzufügen',
                style: MingaTheme.body.copyWith(
                  color: MingaTheme.accentGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (_selectedPlaces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Lieblings‑Spots hinzufügen (optional).',
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Reihenfolge per Drag anpassen.',
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tipp: Füge pro Spot eine kurze Beschreibung hinzu.',
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSubtle,
              ),
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedPlaces.length,
            onReorder: _reorderSelectedPlaces,
            itemBuilder: (context, index) {
              final place = _selectedPlaces[index];
              return Container(
                key: ValueKey(place.id),
                margin: const EdgeInsets.only(bottom: 12),
                child: PlaceListTile(
                  place: place,
                  note: _placeNotes[place.id],
                  isNoteExpanded: _expandedNoteKeys.contains(_noteKey(place.id)),
                  onToggleNote: () => _toggleNote(place.id),
                  onEditNote: () => _showPlaceNoteSheet(
                    placeId: place.id,
                    initialNote: _placeNotes[place.id],
                  ),
                  onTap: () {},
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  String _noteKey(String placeId) => 'create::$placeId';

  void _toggleNote(String placeId) {
    final key = _noteKey(placeId);
    setState(() {
      if (_expandedNoteKeys.contains(key)) {
        _expandedNoteKeys.remove(key);
      } else {
        _expandedNoteKeys.add(key);
      }
    });
  }

  Future<void> _showPlaceNoteSheet({
    required String placeId,
    required String? initialNote,
  }) async {
    final controller = TextEditingController(text: initialNote ?? '');
    final focusNode = FocusNode();

    await showGlassBottomSheet(
      context: context,
      isScrollControlled: true,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Beschreibung', style: MingaTheme.titleSmall),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: MingaTheme.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 8),
              GlassTextField(
                controller: controller,
                focusNode: focusNode,
                hintText: 'Kurze Beschreibung zum Spot…',
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                onChanged: (value) {
                  if (value.length <= _noteMaxChars) return;
                  final trimmed = value.substring(0, _noteMaxChars);
                  controller.value = controller.value.copyWith(
                    text: trimmed,
                    selection: TextSelection.collapsed(offset: trimmed.length),
                  );
                },
              ),
              SizedBox(height: 8),
              Text(
                '${controller.text.length}/$_noteMaxChars',
                style: MingaTheme.bodySmall.copyWith(color: MingaTheme.textSubtle),
              ),
              SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  variant: GlassButtonVariant.primary,
                  label: 'Speichern',
                  onPressed: () {
                    final note = controller.text.trim();
                    setState(() {
                      if (note.isEmpty) {
                        _placeNotes.remove(placeId);
                      } else {
                        _placeNotes[placeId] = note;
                      }
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    controller.dispose();
    focusNode.dispose();
  }

  void _reorderSelectedPlaces(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _selectedPlaces.removeAt(oldIndex);
      _selectedPlaces.insert(newIndex, item);
    });
  }

  Future<void> _showSpotPicker() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einloggen, um Spots hinzuzufügen.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final favoritePlaces =
        await _placeRepository.fetchFavorites(userId: currentUser.id);
    if (!mounted) return;

    final selectedIds = _selectedPlaces.map((place) => place.id).toSet();
    final favoriteIds = favoritePlaces.map((place) => place.id).toSet();
    var searchResults = <Place>[];
    var isSearching = false;
    var searchToken = 0;
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MingaTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> runSearch(String query) async {
              final trimmed = query.trim();
              searchToken += 1;
              final token = searchToken;
              if (trimmed.isEmpty) {
                setModalState(() {
                  searchResults = [];
                  isSearching = false;
                });
                return;
              }
              setModalState(() {
                isSearching = true;
              });
              final results = await _placeRepository.search(query: trimmed);
              if (token != searchToken) return;
              setModalState(() {
                searchResults = results;
                isSearching = false;
              });
            }

            final query = searchController.text.trim().toLowerCase();
            final filtered = query.isEmpty ? favoritePlaces : searchResults;

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Spots hinzufügen',
                            style: MingaTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: MingaTheme.textSecondary,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: searchController,
                      style: MingaTheme.body,
                      decoration: InputDecoration(
                        hintText: 'Suche nach Titel, Kategorie oder Straße',
                        hintStyle: MingaTheme.bodySmall.copyWith(
                          color: MingaTheme.textSubtle,
                        ),
                        prefixIcon:
                            Icon(Icons.search, color: MingaTheme.textSubtle),
                        filled: true,
                        fillColor: MingaTheme.glassOverlay,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(MingaTheme.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) => runSearch(value),
                    ),
                    SizedBox(height: 12),
                    Flexible(
                      child: isSearching
                          ? Center(
                              child: CircularProgressIndicator(
                                color: MingaTheme.accentGreen,
                                strokeWidth: 2,
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    query.isEmpty
                                        ? 'Keine gespeicherten Spots gefunden.'
                                        : 'Keine Ergebnisse gefunden.',
                                    style: MingaTheme.bodySmall.copyWith(
                                      color: MingaTheme.textSubtle,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final place = filtered[index];
                                    final isSelected =
                                        selectedIds.contains(place.id);
                                    final isFavorite =
                                        favoriteIds.contains(place.id);
                                    final subtitleParts = <String>[
                                      place.category,
                                      if (place.address != null &&
                                          place.address!.trim().isNotEmpty)
                                        place.address!.trim(),
                                      if (!isFavorite) 'Aus Suche',
                                    ];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          MingaTheme.radiusSm,
                                        ),
                                        child: SizedBox(
                                          width: 46,
                                          height: 46,
                                          child: PlaceImage(
                                            imageUrl: place.imageUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        place.name,
                                        style: MingaTheme.bodySmall.copyWith(
                                          color: MingaTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        subtitleParts.join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: MingaTheme.bodySmall.copyWith(
                                          color: MingaTheme.textSubtle,
                                        ),
                                      ),
                                      trailing: Checkbox(
                                        value: isSelected,
                                        activeColor: MingaTheme.accentGreen,
                                        onChanged: (value) async {
                                          if (value == true &&
                                              !favoriteIds.contains(place.id)) {
                                            await _placeRepository.addFavorite(
                                              placeId: place.id,
                                              userId: currentUser.id,
                                            );
                                            favoriteIds.add(place.id);
                                            favoritePlaces.insert(0, place);
                                          }
                                          setModalState(() {
                                            if (value == true) {
                                              selectedIds.add(place.id);
                                            } else {
                                              selectedIds.remove(place.id);
                                            }
                                          });
                                        },
                                      ),
                                      onTap: () async {
                                        if (!isSelected &&
                                            !favoriteIds.contains(place.id)) {
                                          await _placeRepository.addFavorite(
                                            placeId: place.id,
                                            userId: currentUser.id,
                                          );
                                          favoriteIds.add(place.id);
                                          favoritePlaces.insert(0, place);
                                        }
                                        setModalState(() {
                                          if (isSelected) {
                                            selectedIds.remove(place.id);
                                          } else {
                                            selectedIds.add(place.id);
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
                      child: ElevatedButton(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(selectedIds),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MingaTheme.accentGreen,
                          foregroundColor: MingaTheme.textPrimary,
                        ),
                        child: Text('Übernehmen'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedPlaces = favoritePlaces
          .where((place) => result.contains(place.id))
          .toList();
    });
  }

  Future<void> _addMedia() async {
    if (_pendingMedia.length >= 5) return;
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MingaTheme.transparent,
      builder: (bottomSheetContext) {
        return GlassSurface(
          radius: 20,
          blurSigma: 18,
          overlayColor: MingaTheme.glassOverlay,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSheetAction(
                    icon: Icons.image_outlined,
                    label: 'Bild auswählen',
                    onTap: () => Navigator.of(bottomSheetContext).pop('image'),
                  ),
                  SizedBox(height: 8),
                  _buildSheetAction(
                    icon: Icons.videocam_outlined,
                    label: 'Video auswählen',
                    onTap: () => Navigator.of(bottomSheetContext).pop('video'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selection == null) return;

    XFile? file;
    if (selection == 'video') {
      file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final filename = file.name.isNotEmpty ? file.name : 'media';
    setState(() {
      _pendingMedia.add(
        _PendingMedia(
          id: '${DateTime.now().millisecondsSinceEpoch}_${_pendingMedia.length}',
          bytes: bytes,
          filename: filename,
          kind: selection,
        ),
      );
    });
  }

  void _removePending(_PendingMedia item) {
    setState(() {
      _pendingMedia.removeWhere((entry) => entry.id == item.id);
    });
  }

  void _reorderMedia(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _pendingMedia.removeAt(oldIndex);
      _pendingMedia.insert(newIndex, item);
    });
  }

  Widget _buildPendingThumbnail(_PendingMedia item) {
    if (item.kind == 'video') {
      return Container(
        color: MingaTheme.darkOverlay,
        child: Center(
          child: Icon(Icons.play_circle_fill,
              color: MingaTheme.textSecondary, size: 28),
        ),
      );
    }
    return Image.memory(item.bytes, fit: BoxFit.cover);
  }

  Widget _buildSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: MingaTheme.textPrimary),
            SizedBox(width: 12),
            Text(
              label,
              style: MingaTheme.body,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingMedia {
  final String id;
  final Uint8List bytes;
  final String filename;
  final String kind; // 'image' | 'video'

  const _PendingMedia({
    required this.id,
    required this.bytes,
    required this.filename,
    required this.kind,
  });
}

