import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// InheritedWidget to provide AuthService to the widget tree
class AuthProvider extends InheritedWidget {
  final AuthService authService;

  const AuthProvider({
    super.key,
    required this.authService,
    required super.child,
  });

  /// Get AuthService from the nearest AuthProvider in the widget tree
  static AuthService of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    if (provider == null) {
      throw Exception('AuthProvider not found in widget tree');
    }
    return provider.authService;
  }

  @override
  bool updateShouldNotify(AuthProvider oldWidget) {
    return authService != oldWidget.authService;
  }
}

