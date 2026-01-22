import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/supabase_gate.dart';
import 'widgets/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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

  @override
  Widget build(BuildContext context) {
    // Use singleton AuthService instance
    final authService = AuthService.instance;

    return AuthProvider(
      authService: authService,
      child: MaterialApp(
        title: 'MingaLive',
        theme: AppTheme.dark(),
        home: MainShell(key: mainShellKey),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
