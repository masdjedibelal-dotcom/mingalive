import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/auth_service.dart';

class CollabCreateScreen extends StatefulWidget {
  const CollabCreateScreen({super.key});

  @override
  State<CollabCreateScreen> createState() => _CollabCreateScreenState();
}

class _CollabCreateScreenState extends State<CollabCreateScreen> {
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _itemsController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;
  final List<_PendingMedia> _pendingMedia = [];
  bool _isUploadingMedia = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _itemsController.dispose();
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

    setState(() {
      _isSaving = true;
    });

    final placeIds = _itemsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

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
          GlassSurface(
            radius: 16,
            blurSigma: 16,
            overlayColor: MingaTheme.glassOverlayXSoft,
            child: TextField(
              controller: _itemsController,
              style: MingaTheme.body,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Spot-IDs (optional)',
                labelStyle: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
                hintText: 'id1, id2, id3',
                hintStyle: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSubtle,
                ),
                filled: true,
                fillColor: MingaTheme.transparent,
                border: const OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
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

