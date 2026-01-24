import 'package:flutter/material.dart';

double bottomNavSafePadding(BuildContext context) {
  const navHeight = 62.0;
  const navTopPadding = 4.0;
  const navBottomFallback = 8.0;
  final bottomInset = MediaQuery.of(context).padding.bottom;
  final navBottomPadding =
      (bottomInset > 0 ? bottomInset : navBottomFallback);
  return navHeight + navTopPadding + navBottomPadding;
}





