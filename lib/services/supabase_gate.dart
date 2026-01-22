import 'package:supabase_flutter/supabase_flutter.dart';

/// Gate to safely access Supabase client only when initialized
/// 
/// Usage:
/// - Set SupabaseGate.enabled = true after successful Supabase.initialize()
/// - Check SupabaseGate.isEnabled before using Supabase features
/// - Access client via SupabaseGate.client (asserts if not enabled)
class SupabaseGate {
  /// Whether Supabase has been successfully initialized
  static bool enabled = false;

  /// Check if Supabase is enabled/initialized
  static bool get isEnabled => enabled;

  /// Get Supabase client (asserts if not enabled)
  /// 
  /// Throws assertion error if Supabase is not initialized.
  /// Always check isEnabled before calling this in production code.
  static SupabaseClient get client {
    assert(enabled, 'Supabase is not enabled/initialized');
    return Supabase.instance.client;
  }
}

