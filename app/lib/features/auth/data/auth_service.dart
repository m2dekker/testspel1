import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
import '../../haven/data/demo_game_backend.dart';

/// The logged-in player.
class AppUser {
  const AppUser({required this.id, required this.name});

  final String id;
  final String name;
}

/// A login problem with a message for the player.
class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Login state. It is a [ChangeNotifier] so the router can redirect
/// whenever the player logs in or out.
abstract class AuthService extends ChangeNotifier {
  AppUser? get user;

  /// True for the offline demo, which only asks for a captain's name.
  bool get isDemo;
}

// ---------------------------------------------------------------------------

/// Real accounts through Supabase Auth (email + Google).
class SupabaseAuthService extends AuthService {
  SupabaseAuthService(this._client) {
    _sub = _client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _sub;

  @override
  bool get isDemo => false;

  @override
  AppUser? get user {
    final u = _client.auth.currentUser;
    if (u == null) return null;
    final name = u.userMetadata?['username'] as String? ?? u.email ?? 'Captain';
    return AppUser(id: u.id, name: name);
  }

  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _client.auth.signInWithPassword(email: email, password: password),
      );

  /// Returns a message to show when the account still needs email confirmation.
  Future<String?> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final res = await _guard(
      () => _client.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      ),
    );
    if (res.session == null) {
      return 'Check your email to confirm your account, then log in.';
    }
    return null;
  }

  Future<void> signInWithGoogle() => _guard(
    () => _client.auth.signInWithOAuth(
      OAuthProvider.google,
      // Web returns to the current page; mobile returns through a deep link.
      redirectTo: kIsWeb ? null : Env.oauthRedirect,
    ),
  );

  Future<void> signOut() => _client.auth.signOut();

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------

/// Offline demo: no account, just a captain's name saved on the device.
class DemoAuthService extends AuthService {
  DemoAuthService(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool get isDemo => true;

  @override
  AppUser? get user {
    final name = _prefs.getString(DemoGameBackend.captainKey);
    return name == null ? null : AppUser(id: 'demo', name: name);
  }

  Future<void> startDemo(String captainName) async {
    final name = captainName.trim();
    if (name.isEmpty) throw AuthFailure('Give your captain a name.');
    await _prefs.setString(DemoGameBackend.captainKey, name);
    notifyListeners();
  }

  /// Leaves the haven (it stays saved on this device).
  Future<void> signOut() async {
    await _prefs.remove(DemoGameBackend.captainKey);
    notifyListeners();
  }

  /// Deletes the saved demo haven so the next login starts over.
  Future<void> abandonHaven() async {
    await _prefs.remove(DemoGameBackend.storageKey);
    await signOut();
  }
}
