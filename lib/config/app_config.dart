class AppConfig {
  AppConfig._();

  static const String _oauthRedirectScheme = 'com.masdjedi.mingalive';
  static const String _oauthRedirectHost = 'login-callback';
  static const String _defaultSupabaseUrl = 'https://gsdkquzddlpzxgwxigmf.supabase.co';
  static const String _defaultSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdzZGtxdXpkZGxwenhnd3hpZ21mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNDUwMzUsImV4cCI6MjA4MzgyMTAzNX0.rlAoxRf-Zv-OINSjJOHhNsx2ndmhnMERldvTeMwAHJA';

  static String get supabaseUrl {
    const defined = String.fromEnvironment('SUPABASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }
    return _defaultSupabaseUrl;
  }

  static String get supabaseAnonKey {
    const defined = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (defined.isNotEmpty) {
      return defined;
    }
    return _defaultSupabaseAnonKey;
  }

  static String get oauthRedirectUri =>
      '$_oauthRedirectScheme://$_oauthRedirectHost';
}

