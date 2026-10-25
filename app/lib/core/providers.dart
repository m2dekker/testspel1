import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_service.dart';
import '../features/haven/data/demo_game_backend.dart';
import '../features/haven/data/game_backend.dart';
import '../features/haven/data/supabase_game_backend.dart';
import 'env.dart';

/// Loaded in main() before the app starts, then injected with an override.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPrefsProvider in main()'),
);

/// Login state: real Supabase accounts, or the offline demo.
final authServiceProvider = Provider<AuthService>((ref) {
  final AuthService service = Env.useSupabase
      ? SupabaseAuthService(Supabase.instance.client)
      : DemoAuthService(ref.watch(sharedPrefsProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Where game actions are sent: the Postgres RPCs, or the local demo rules.
final gameBackendProvider = Provider<GameBackend>((ref) {
  return Env.useSupabase
      ? SupabaseGameBackend(Supabase.instance.client)
      : DemoGameBackend(ref.watch(sharedPrefsProvider));
});
