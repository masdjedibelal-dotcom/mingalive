import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';
import '../widgets/glass/glass_button.dart';

class CollabCarousel extends StatelessWidget {
  final String title;
  final bool isLoading;
  final String emptyText;
  final VoidCallback onSeeAll;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const CollabCarousel({
    super.key,
    required this.title,
    required this.isLoading,
    required this.emptyText,
    required this.onSeeAll,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: tokens.type.headline.copyWith(
                  color: tokens.colors.textPrimary,
                ),
              ),
            ),
            GlassButton(
              variant: GlassButtonVariant.ghost,
              onPressed: onSeeAll,
              label: 'Alle ansehen',
            ),
          ],
        ),
        SizedBox(height: tokens.space.s12),
        if (isLoading)
          SizedBox(
            height: 260,
            child: Center(
              child: CircularProgressIndicator(
                color: tokens.colors.accent,
              ),
            ),
          )
        else if (itemCount == 0)
          SizedBox(
            height: 120,
            child: Center(
              child: Text(
                emptyText,
                style: tokens.type.body.copyWith(
                  color: tokens.colors.textMuted,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 260,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              primary: false,
              dragStartBehavior: DragStartBehavior.down,
              padding: EdgeInsets.symmetric(horizontal: tokens.space.s4),
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          ),
      ],
    );
  }
}

