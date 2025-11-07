// main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ⟵ aggiungi

import 'core/env.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/venues/screens/map_screen.dart';
import 'features/onboarding/start_onboarding.dart'; // ⟵ aggiungi

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
        colorSchemeSeed: _brandPurple, // ⟵ viola brand (o lascia Colors.indigo)
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
      home: const AuthGate(), // ⟵ usa l’AuthGate
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/map': (_) => const MapScreen(),
      },
    );
  }
}

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
    final prefs = await SharedPreferences.getInstance();
    _onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    // Utente loggato → mappa
    if (session != null) return const MapScreen();

    // Utente non loggato → Onboarding se non visto, altrimenti Login
    return _onboardingSeen ? const LoginScreen() : const StartOnboarding();
  }
}
