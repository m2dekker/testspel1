/// Build-time configuration, passed with `--dart-define` or
/// `--dart-define-from-file=env.json`.
///
/// Without a Supabase URL and key the app runs in **offline demo mode**:
/// the same game rules run locally and progress is saved on the device.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's publishable key (or legacy anon key). Safe to ship in the
  /// app: RLS and the RPC rules decide what it can do.
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Force demo mode even when Supabase is configured.
  static const forceDemo = bool.fromEnvironment('DEMO');

  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty && !forceDemo;

  /// Deep link the mobile apps use to return from Google sign-in.
  /// Must also be added to Supabase → Authentication → URL Configuration.
  static const oauthRedirect = 'io.blackwake.isles://login-callback';
}
