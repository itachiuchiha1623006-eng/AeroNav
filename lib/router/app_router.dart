import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/splash_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/routes_screen.dart';
import '../screens/profile_screen.dart';
import 'package:latlong2/latlong.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isAuthenticated = session != null;
    final isSplash = state.matchedLocation == '/splash';
    final isLanding = state.matchedLocation == '/landing';
    final isAuthRoute = state.matchedLocation.startsWith('/auth');

   
    if (isSplash || isLanding) return null;


    if (!isAuthenticated && !isAuthRoute) return '/auth/login';

    
    if (isAuthenticated && isAuthRoute) return '/home';

    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/landing',
      builder: (context, state) => const LandingScreen(),
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
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/routes',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        return RoutesScreen(
          startPoint: args['startPoint'] as LatLng,
          endPoint: args['endPoint'] as LatLng,
          destinationName: args['destinationName'] as String,
        );
      },
    ),
  ],
);
