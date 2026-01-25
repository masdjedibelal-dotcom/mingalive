import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme_extensions.dart';

class CollabCarousel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? titleIcon;
  final bool isLoading;
  final String emptyText;
  final VoidCallback onSeeAll;
  final bool showSeeAll;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const CollabCarousel({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.isLoading,
    required this.emptyText,
    required this.onSeeAll,
    this.showSeeAll = true,
    this.height = 260,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (titleIcon != null) ...[
              Icon(
                titleIcon,
                size: 18,
                color: tokens.colors.textSecondary,
              ),
              SizedBox(width: tokens.space.s6),
            ],
            Expanded(
              child: Text(
                title,
                style: tokens.type.headline.copyWith(
                  color: tokens.colors.textPrimary,
                ),
              ),
            ),
            if (showSeeAll)
              InkWell(
                onTap: onSeeAll,
                borderRadius: BorderRadius.circular(tokens.radius.sm),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Alle ansehen',
                    style: tokens.type.body.copyWith(
                      color: tokens.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          SizedBox(height: tokens.space.s4),
          Text(
            subtitle!,
            style: tokens.type.body.copyWith(
              color: tokens.colors.textMuted,
            ),
          ),
        ],
        SizedBox(height: tokens.space.s12),
        if (isLoading)
          SizedBox(
            height: height,
            child: Center(
              child: CircularProgressIndicator(
                color: tokens.colors.accent,
              ),
            ),
          )
        else if (itemCount == 0)
          SizedBox(
            height: height,
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
            height: height,
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

