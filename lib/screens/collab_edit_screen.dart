import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';
import '../services/supabase_collabs_repository.dart';
import '../models/collab.dart';

class CollabEditResult {
  final String title;
  final String description;
  final bool isPublic;

  const CollabEditResult({
    required this.title,
    required this.description,
    required this.isPublic,
  });
}

class CollabEditScreen extends StatefulWidget {
  final String collabId;
  final String ownerId;
  final String initialTitle;
  final String initialDescription;
  final bool initialIsPublic;

  const CollabEditScreen({
    super.key,
    required this.collabId,
    required this.ownerId,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialIsPublic,
  });

  @override
  State<CollabEditScreen> createState() => _CollabEditScreenState();
}

class _CollabEditScreenState extends State<CollabEditScreen> {
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late bool _isPublic;
  List<CollabMediaItem> _mediaItems = [];
  bool _isLoadingMedia = true;
  bool _isUpdatingMedia = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _isPublic = widget.initialIsPublic;
    _loadMediaItems();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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

    await _collabsRepository.updateCollab(
      collabId: widget.collabId,
      title: title,
      description: _descriptionController.text.trim(),
      isPublic: _isPublic,
    );

    Navigator.of(context).pop(
      CollabEditResult(
        title: title,
        description: _descriptionController.text.trim(),
        isPublic: _isPublic,
      ),
    );
  }

  Future<void> _loadMediaItems() async {
    final items =
        await _collabsRepository.fetchCollabMediaItems(widget.collabId);
    if (!mounted) return;
    setState(() {
      _mediaItems = items;
      _isLoadingMedia = false;
    });
  }

  Future<void> _addMedia() async {
    if (_mediaItems.length >= 5) return;
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

    setState(() {
      _isUpdatingMedia = true;
    });
    final bytes = await file.readAsBytes();
    final item = await _collabsRepository.addCollabMediaItem(
      collabId: widget.collabId,
      userId: widget.ownerId,
      bytes: bytes,
      filename: file.name.isNotEmpty ? file.name : 'media',
    );
    if (!mounted) return;
    if (item != null) {
      setState(() {
        _mediaItems = [..._mediaItems, item];
      });
    }
    if (mounted) {
      setState(() {
        _isUpdatingMedia = false;
      });
    }
  }

  Future<void> _removeMedia(CollabMediaItem item) async {
    setState(() {
      _isUpdatingMedia = true;
    });
    await _collabsRepository.deleteCollabMediaItem(
      itemId: item.id,
      storagePath: item.storagePath,
    );
    if (!mounted) return;
    setState(() {
      _mediaItems = _mediaItems.where((entry) => entry.id != item.id).toList();
      _isUpdatingMedia = false;
    });
  }

  Future<void> _reorderMedia(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _mediaItems.removeAt(oldIndex);
      _mediaItems.insert(newIndex, item);
      _isUpdatingMedia = true;
    });
    await _collabsRepository.reorderCollabMediaItems(
      widget.collabId,
      _mediaItems,
    );
    if (!mounted) return;
    setState(() {
      _isUpdatingMedia = false;
    });
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
          'Collab bearbeiten',
          style: MingaTheme.titleSmall,
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Speichern',
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
            child: TextField(
              controller: _descriptionController,
              style: MingaTheme.body,
              maxLines: 4,
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
          SizedBox(height: 16),
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
          SizedBox(height: 24),
          _buildMediaSection(),
        ],
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
              onPressed: _mediaItems.length >= 5 || _isUpdatingMedia
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
        if (_isLoadingMedia)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(
                color: MingaTheme.accentGreen,
              ),
            ),
          )
        else if (_mediaItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Füge bis zu 5 Medien hinzu, um dein Collab visuell zu gestalten.',
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
              itemCount: _mediaItems.length,
              itemBuilder: (context, index) {
                final item = _mediaItems[index];
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
                          child: _buildMediaThumbnail(item),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: _isUpdatingMedia ? null : () => _removeMedia(item),
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

  Widget _buildMediaThumbnail(CollabMediaItem item) {
    if (item.kind == 'video') {
      return Container(
        color: MingaTheme.darkOverlay,
        child: Center(
          child: Icon(Icons.play_circle_fill,
              color: MingaTheme.textSecondary, size: 28),
        ),
      );
    }
    return Image.network(
      item.publicUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: MingaTheme.skeletonFill,
          child: Icon(
            Icons.image_outlined,
            color: MingaTheme.textSubtle,
          ),
        );
      },
    );
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

