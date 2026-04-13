import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isAuthenticated = session != null;
    final isSplash = state.matchedLocation == '/splash';
    final isAuthRoute = state.matchedLocation.startsWith('/auth');

    // Always allow splash
    if (isSplash) return null;

    // Redirect to login if not authenticated and not on an auth route
    if (!isAuthenticated && !isAuthRoute) return '/auth/login';

    // Redirect to home if authenticated and trying to access auth routes
    if (isAuthenticated && isAuthRoute) return '/home';

    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/auth/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/auth/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
  ],
);
