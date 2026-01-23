import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/supabase_gate.dart';
import 'widgets/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supabaseUrl = AppConfig.supabaseUrl;
  final supabaseAnonKey = AppConfig.supabaseAnonKey;

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    SupabaseGate.enabled = true;
  } else {
    SupabaseGate.enabled = false;
    debugPrint('⚠️ Supabase nicht konfiguriert – läuft im Demo-Modus');
  }

  runApp(const MingaLiveApp());
}

class MingaLiveApp extends StatelessWidget {
  const MingaLiveApp({super.key});

  Future<bool> _isOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen_v1') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Use singleton AuthService instance
    final authService = AuthService.instance;

    return AuthProvider(
      authService: authService,
      child: MaterialApp(
        title: 'MingaLive',
        theme: AppTheme.dark(),
        home: FutureBuilder<bool>(
          future: _isOnboardingSeen(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final seen = snapshot.data ?? false;
            if (seen) {
              return MainShell(key: mainShellKey);
            }
            return OnboardingScreen(
              onFinished: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => MainShell(key: mainShellKey),
                  ),
                );
              },
            );
          },
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
