import 'package:flutter/material.dart';
import '../models/place.dart';
import '../services/auth_service.dart';
import '../services/supabase_collabs_repository.dart';
import '../services/supabase_gate.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_bottom_sheet.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/glass/glass_text_field.dart';

Future<void> showAddToCollabSheet({
  required BuildContext context,
  required Place place,
}) async {
  final currentUser = AuthService.instance.currentUser;
  if (currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bitte einloggen, um Spots zu speichern.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  if (!SupabaseGate.isEnabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Collabs sind nur mit Supabase verfügbar.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  await showGlassBottomSheet(
    context: context,
    isScrollControlled: true,
    child: _AddToCollabSheet(
      place: place,
      userId: currentUser.id,
    ),
  );
}

class _AddToCollabSheet extends StatefulWidget {
  final Place place;
  final String userId;

  const _AddToCollabSheet({
    required this.place,
    required this.userId,
  });

  @override
  State<_AddToCollabSheet> createState() => _AddToCollabSheetState();
}

class _AddToCollabSheetState extends State<_AddToCollabSheet> {
  final SupabaseCollabsRepository _collabsRepository =
      SupabaseCollabsRepository();
  List<Collab> _myCollabs = [];
  List<Collab> _savedCollabs = [];
  List<Collab> _publicCollabs = [];
  final Map<String, Set<String>> _collabPlaceIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCollabs();
  }

  Future<void> _loadCollabs() async {
    try {
      final results = await Future.wait([
        _collabsRepository.fetchCollabsByOwner(
          ownerId: widget.userId,
          isPublic: true,
        ),
        _collabsRepository.fetchCollabsByOwner(
          ownerId: widget.userId,
          isPublic: false,
        ),
        _collabsRepository.fetchSavedCollabs(userId: widget.userId),
        _collabsRepository.fetchPublicCollabs(),
      ]);

      final myCollabs = [...results[0], ...results[1]];
      final saved = results[2]
          .where((collab) => collab.ownerId != widget.userId)
          .toList();
      final public = results[3]
          .where((collab) => collab.ownerId != widget.userId)
          .toList();

      if (mounted) {
        setState(() {
          _myCollabs = myCollabs;
          _savedCollabs = saved;
          _publicCollabs = public;
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: tokens.space.s20,
          right: tokens.space.s20,
          top: tokens.space.s12,
          bottom: MediaQuery.of(context).viewInsets.bottom + tokens.space.s20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            SizedBox(height: tokens.space.s16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Zu Collab hinzufügen',
                style: tokens.type.title.copyWith(
                  color: tokens.colors.textPrimary,
                ),
              ),
            ),
            SizedBox(height: tokens.space.s12),
            if (_isLoading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.space.s24),
                child: CircularProgressIndicator(
                  color: tokens.colors.accent,
                ),
              )
            else if (_myCollabs.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.space.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Du hast noch keine Collabs erstellt.',
                      style: tokens.type.body.copyWith(
                        color: tokens.colors.textMuted,
                      ),
                    ),
                    SizedBox(height: tokens.space.s16),
                    SizedBox(
                      width: double.infinity,
                      height: tokens.button.height,
                      child: GlassButton(
                        variant: GlassButtonVariant.secondary,
                        onPressed: _showCreateCollabDialog,
                        label: 'Create collab',
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myCollabs.length,
                separatorBuilder: (_, __) => Divider(
                  color: tokens.colors.border,
                  height: tokens.space.s16,
                ),
                itemBuilder: (context, index) {
                  final collab = _myCollabs[index];
                  return FutureBuilder<List<String>>(
                    future: _collabsRepository.fetchCollabPlaceIds(
                      collabId: collab.id,
                    ),
                    builder: (context, snapshot) {
                      final placeIds = snapshot.data ?? [];
                      _collabPlaceIds[collab.id] = placeIds.toSet();
                      final isInList = placeIds.contains(widget.place.id);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          collab.title,
                          style: tokens.type.body.copyWith(
                            color: tokens.colors.textPrimary,
                          ),
                        ),
                        trailing: isInList
                            ? Icon(
                                Icons.check,
                                color: tokens.colors.accent,
                              )
                            : Icon(
                                Icons.add,
                                color: tokens.colors.textMuted,
                              ),
                        onTap: isInList ? null : () => _addPlace(collab),
                      );
                    },
                  );
                },
              ),
            if (_savedCollabs.isNotEmpty) ...[
              SizedBox(height: tokens.space.s20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Gespeicherte Collabs',
                  style: tokens.type.caption.copyWith(
                    color: tokens.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: tokens.space.s8),
              ..._savedCollabs.map(
                (collab) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    collab.title,
                    style: tokens.type.body.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    'Nur eigene Collabs können Spots aufnehmen.',
                    style: tokens.type.caption.copyWith(
                      color: tokens.colors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
            if (_publicCollabs.isNotEmpty) ...[
              SizedBox(height: tokens.space.s20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Öffentliche Collabs',
                  style: tokens.type.caption.copyWith(
                    color: tokens.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: tokens.space.s8),
              ..._publicCollabs.map(
                (collab) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    collab.title,
                    style: tokens.type.body.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    'Nur eigene Collabs können Spots aufnehmen.',
                    style: tokens.type.caption.copyWith(
                      color: tokens.colors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: tokens.space.s16),
            SizedBox(
              width: double.infinity,
              height: tokens.button.height,
              child: GlassButton(
                variant: GlassButtonVariant.secondary,
                onPressed: _showCreateCollabDialog,
                label: 'Create collab',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPlace(Collab collab) async {
    await _collabsRepository.addPlaceToCollab(
      collabId: collab.id,
      placeId: widget.place.id,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Zu "${collab.title}" hinzugefügt'),
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }

  void _showCreateCollabDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isPublic = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: context.tokens.colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: context.tokens.space.s24,
            vertical: context.tokens.space.s24,
          ),
          child: GlassSurface(
            radius: context.tokens.radius.lg,
            blur: context.tokens.blur.med,
            scrim: context.tokens.card.glassOverlay,
            borderColor: context.tokens.colors.border,
            child: Padding(
              padding: EdgeInsets.all(context.tokens.space.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Neuen Collab erstellen',
                    style: context.tokens.type.title.copyWith(
                      color: context.tokens.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: context.tokens.space.s16),
                  GlassTextField(
                    controller: titleController,
                    labelText: 'Titel',
                    autofocus: true,
                  ),
                  SizedBox(height: context.tokens.space.s16),
                  GlassTextField(
                    controller: descriptionController,
                    labelText: 'Short description',
                    hintText: 'Why did you create this collection?',
                    maxLines: 4,
                  ),
                  SizedBox(height: context.tokens.space.s16),
                  GlassSurface(
                    radius: context.tokens.radius.md,
                    blur: context.tokens.blur.low,
                    scrim: context.tokens.input.fill,
                    borderColor: context.tokens.colors.border,
                    child: SwitchListTile(
                      title: Text(
                        'Collab öffentlich machen',
                        style: context.tokens.type.body.copyWith(
                          color: context.tokens.colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Öffentliche Collabs können von anderen entdeckt werden.',
                        style: context.tokens.type.caption.copyWith(
                          color: context.tokens.colors.textMuted,
                        ),
                      ),
                      activeColor: context.tokens.colors.accent,
                      value: isPublic,
                      onChanged: (value) {
                        setDialogState(() {
                          isPublic = value;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: context.tokens.space.s20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GlassButton(
                        variant: GlassButtonVariant.ghost,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        label: 'Abbrechen',
                      ),
                      SizedBox(width: context.tokens.space.s12),
                      GlassButton(
                        variant: GlassButtonVariant.primary,
                        onPressed: () async {
                          final title = titleController.text.trim();
                          final description = descriptionController.text.trim();

                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bitte einen Titel eingeben'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }

                          await _collabsRepository.createCollab(
                            title: title,
                            description: description.isEmpty ? null : description,
                            isPublic: isPublic,
                            coverMediaUrls: const [],
                          );

                          if (!mounted) return;
                          Navigator.of(dialogContext).pop();
                          await _loadCollabs();
                        },
                        label: 'Erstellen',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

