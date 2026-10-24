import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/haven/presentation/haven_screen.dart';
import 'providers.dart';

/// Two screens for now: login and the haven. Logged-out players are always
/// sent to /login, logged-in players away from it.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.user != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HavenScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Google sign-in on mobile comes back through this deep link.
      GoRoute(path: '/login-callback', redirect: (context, state) => '/'),
    ],
    errorBuilder: (context, state) => const HavenScreen(),
  );
  ref.onDispose(router.dispose);
  return router;
});
