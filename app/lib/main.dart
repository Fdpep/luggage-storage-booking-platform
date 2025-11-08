// main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ⟵ aggiungi

import 'core/env.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/venues/screens/map_screen.dart';
import 'features/splash/splash_screen.dart' ;
import 'features/onboarding/start_onboarding.dart'; // ⟵ aggiungi
import 'package:shared_preferences/shared_preferences.dart';

const _brandPurple = Color(0xFF4B3FE4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BagDrop Marketplace',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _brandPurple, // ⟵ viola brand 
        brightness: Brightness.light,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        chipTheme: const ChipThemeData(
          shape: StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _brandPurple,
        brightness: Brightness.dark,
      ),
      home: const SplashScreen(), // ⟵ usa l’AuthGate
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/map': (_) => const MapScreen(),
      },
    );
  }
}

// main.dart (sotto la classe App)


/// ⚙️ Metti a true in DEV per forzare l'onboarding ogni volta
const bool kShowOnboardingEveryLaunch = true;

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // in DEV ignoriamo il flag
    if (!kShowOnboardingEveryLaunch) {
      final prefs = await SharedPreferences.getInstance();
      _onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Utente già loggato → vai subito alla mappa
      return const MapScreen();
    }

    // Utente NON loggato:
    // - in DEV → mostra SEMPRE l’onboarding
    // - in PROD → mostrala solo se non è stata vista
    if (kShowOnboardingEveryLaunch || !_onboardingSeen) {
      return const StartOnboarding();
    }
    return const LoginScreen();
  }
}


