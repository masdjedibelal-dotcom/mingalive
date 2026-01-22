import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import 'supabase_gate.dart';

/// Service for managing authentication state
/// 
/// IMPORTANT: Before using Google OAuth, configure it in Supabase Dashboard:
/// 1. Go to Authentication > Providers > Google
/// 2. Enable Google provider
/// 3. Add your Google OAuth Client ID and Secret from Google Cloud Console
/// 4. Add redirect URL: https://<your-project-ref>.supabase.co/auth/v1/callback
/// 5. For web: In Google Cloud Console, add authorized redirect URIs:
///    - https://<your-project-ref>.supabase.co/auth/v1/callback
///    - http://localhost:<port>/auth/v1/callback (for local development)
class AuthService extends ChangeNotifier {
  static AuthService? _instance;
  
  /// Singleton instance
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  AppUser? _currentUser;

  /// Current authenticated user, null if not logged in
  AppUser? get currentUser => _currentUser;

  /// ValueNotifier for reactive updates
  final ValueNotifier<AppUser?> currentUserNotifier = ValueNotifier<AppUser?>(null);

  AuthService._() {
    // Initialize with null user
    _currentUser = null;
    currentUserNotifier.value = null;

    // Listen to Supabase auth state changes only if enabled
    if (SupabaseGate.isEnabled) {
      try {
        final supabase = SupabaseGate.client;
        supabase.auth.onAuthStateChange.listen((data) {
          _updateUserFromSession(data.session);
        });

        // Check for existing session on initialization (safe for refresh)
        final existingSession = supabase.auth.currentSession;
        _updateUserFromSession(existingSession);
      } catch (e) {
        // Defensive: if Supabase access fails, continue in demo mode
        if (kDebugMode) {
          debugPrint('⚠️ AuthService: Failed to initialize Supabase auth listener: $e');
        }
      }
    }
  }

  /// Update current user from Supabase session
  void _updateUserFromSession(Session? session) {
    final wasLoggedIn = _currentUser != null;
    
    if (session?.user == null) {
      if (wasLoggedIn && kDebugMode) {
        debugPrint('🔴 AuthService: User signed out');
      }
      _currentUser = null;
      currentUserNotifier.value = null;
    } else {
      final user = session!.user;
      final userMetadata = user.userMetadata ?? {};

      // Extract user info from Supabase user
      // Supabase stores Google profile in user_metadata
      final name = userMetadata['full_name'] as String? ??
          userMetadata['name'] as String? ??
          (user.email != null ? user.email!.split('@').first : 'User');
      
      final email = user.email;
      final photoUrl = userMetadata['avatar_url'] as String? ??
          userMetadata['picture'] as String?;

      final newUser = AppUser(
        id: user.id,
        name: name,
        email: email,
        photoUrl: photoUrl,
      );
      
      // Only log if state actually changed
      if (!wasLoggedIn || _currentUser?.id != newUser.id) {
        if (kDebugMode) {
          debugPrint('🟢 AuthService: User signed in (${newUser.name}, ${newUser.email ?? 'no email'})');
        }
      }
      
      _currentUser = newUser;
      currentUserNotifier.value = _currentUser;
    }
    notifyListeners();
  }

  /// Sign in with Google OAuth
  /// 
  /// IMPORTANT: Ensure Google OAuth is configured in Supabase Dashboard
  /// See class documentation for setup instructions.
  /// 
  /// Throws exception if Supabase is not enabled.
  Future<void> signInWithGoogle() async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ AuthService: Google login attempted but Supabase is not enabled');
      }
      throw Exception('Supabase ist noch nicht konfiguriert.');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔄 AuthService: Initiating Google OAuth sign-in...');
      }
      final supabase = SupabaseGate.client;
      // For web, Supabase handles the redirect automatically
      // The redirect URL should be configured in Supabase Dashboard:
      // Authentication > URL Configuration > Redirect URLs
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.origin : null, // Mobile handles redirect automatically
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      // User will be updated via onAuthStateChange listener
      if (kDebugMode) {
        debugPrint('✅ AuthService: Google OAuth sign-in initiated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AuthService: Google OAuth sign-in failed: $e');
      }
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  /// Sign out the current user
  /// Works for both Supabase users and demo users
  Future<void> signOut() async {
    // If Supabase is enabled and user is logged in via Supabase, sign out from Supabase
    if (SupabaseGate.isEnabled && _currentUser != null) {
      try {
        if (kDebugMode) {
          debugPrint('🔄 AuthService: Signing out from Supabase...');
        }
        final supabase = SupabaseGate.client;
        await supabase.auth.signOut();
        if (kDebugMode) {
          debugPrint('✅ AuthService: Supabase sign-out successful');
        }
      } catch (e) {
        // Continue with local sign out even if Supabase sign out fails
        if (kDebugMode) {
          debugPrint('⚠️ AuthService: Supabase sign-out failed, continuing with local sign-out: $e');
        }
      }
    }

    // Always clear local user state (works for both Supabase and demo users)
    if (kDebugMode && _currentUser != null) {
      debugPrint('🔴 AuthService: Clearing local user state');
    }
    _currentUser = null;
    currentUserNotifier.value = null;
    notifyListeners();
  }

  /// Sign in with a mock/demo user (for fallback/demo purposes)
  /// 
  /// Behavior:
  /// - If SupabaseGate is enabled: Uses Supabase signInWithPassword with demo credentials
  /// - If SupabaseGate is disabled: Creates local demo user with static UUID
  /// 
  /// For Supabase mode:
  /// - Email: "demo@mingalive.app"
  /// - Password: Read from --dart-define DEMO_PASSWORD (or placeholder if not set)
  /// 
  /// IMPORTANT: Create the demo user in Supabase Dashboard:
  /// 1. Go to Authentication > Users
  /// 2. Add user with email: demo@mingalive.app
  /// 3. Set password (must match DEMO_PASSWORD or placeholder)
  Future<void> signInMock() async {
    if (kDebugMode) {
      debugPrint('🟡 AuthService: Signing in with demo user');
    }

    if (SupabaseGate.isEnabled) {
      // Use Supabase authentication
      try {
        const demoEmail = 'demo@mingalive.app';
        // TODO: Replace with actual password from --dart-define DEMO_PASSWORD
        // Read password from environment variable or use placeholder
        const demoPassword = String.fromEnvironment(
          'DEMO_PASSWORD',
          defaultValue: 'demo_password_placeholder_change_me', // TODO: Set via --dart-define
        );

        if (kDebugMode) {
          if (demoPassword == 'demo_password_placeholder_change_me') {
            debugPrint('⚠️ AuthService: Using placeholder password. Set --dart-define=DEMO_PASSWORD=your_password');
          }
        }

        final supabase = SupabaseGate.client;
        final response = await supabase.auth.signInWithPassword(
          email: demoEmail,
          password: demoPassword,
        );

        // User will be updated via onAuthStateChange listener
        // But we can also update immediately from the response
        if (response.session != null) {
          _updateUserFromSession(response.session);
        }

        if (kDebugMode) {
          debugPrint('✅ AuthService: Demo user signed in via Supabase');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ AuthService: Demo login failed: $e');
        }
        rethrow;
      }
    } else {
      // Local demo user (fallback when Supabase is disabled)
      _currentUser = const AppUser(
        id: '00000000-0000-0000-0000-000000000001', // Valid UUID for Supabase compatibility
        name: 'Demo User',
        email: 'demo@mingalive.app',
        photoUrl: null,
      );
      currentUserNotifier.value = _currentUser;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    currentUserNotifier.dispose();
    super.dispose();
  }
}

