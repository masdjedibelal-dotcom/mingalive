import 'package:flutter/material.dart';
import '../services/supabase_collabs_repository.dart';
import 'collab_card.dart';
import '../theme/app_theme_extensions.dart';

class CollabGrid extends StatelessWidget {
  final List<Collab> collabs;
  final String Function(Collab) creatorName;
  final String? Function(Collab) creatorAvatarUrl;
  final String Function(Collab) creatorId;
  final String? Function(Collab)? creatorBadge;
  final Map<String, int>? saveCounts;
  final String emptyText;
  final ValueChanged<Collab>? onCollabTap;
  final ValueChanged<Collab>? onCreatorTap;
  final bool Function(Collab)? showEditIcon;
  final ValueChanged<Collab>? onEditTap;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const CollabGrid({
    super.key,
    required this.collabs,
    required this.creatorName,
    required this.creatorAvatarUrl,
    required this.creatorId,
    this.creatorBadge,
    this.saveCounts,
    required this.emptyText,
    this.onCollabTap,
    this.onCreatorTap,
    this.showEditIcon,
    this.onEditTap,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (collabs.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.space.s32),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: tokens.type.body.copyWith(
              color: tokens.colors.textMuted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.s4,
        vertical: tokens.space.s8,
      ),
      shrinkWrap: shrinkWrap,
      physics: physics ??
          (shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics()),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: collabs.length,
      itemBuilder: (context, index) {
        final collab = collabs[index];
        final mediaUrls = collab.coverMediaUrls;
        final saveCount = saveCounts?[collab.id];
        return CollabCard(
          title: collab.title,
          username: creatorName(collab),
          avatarUrl: creatorAvatarUrl(collab),
          creatorId: creatorId(collab),
          creatorBadge: creatorBadge?.call(collab),
          mediaUrls: mediaUrls,
          imageUrl: mediaUrls.isNotEmpty ? mediaUrls.first : null,
          gradientKey: 'mint',
          saveCount: saveCount,
          onTap: onCollabTap == null ? () {} : () => onCollabTap!(collab),
          onCreatorTap: onCreatorTap == null ? () {} : () => onCreatorTap!(collab),
          onEditTap: showEditIcon != null && showEditIcon!(collab)
              ? () => onEditTap?.call(collab)
              : null,
        );
      },
    );
  }
}

