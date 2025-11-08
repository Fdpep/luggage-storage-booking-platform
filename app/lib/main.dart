import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'routes/auth_gate.dart';                 // rimane com'è
import 'schermate/home_shell.dart';
import 'schermate/autenticazione/accesso.dart';
import 'schermate/autenticazione/registrazione.dart';
import 'schermate/autenticazione/reset_password.dart';
import 'schermate/onboarding/start_onboarding.dart';       // <- il tuo onboarding
import 'theme/app_theme.dart';

/// ⚙️ In DEV metti true per forzare l’onboarding ad ogni avvio.
/// In PROD lascialo false: verrà mostrato solo la prima volta.
const bool kShowOnboardingEveryLaunch = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  runApp(const BagDropApp());
}

class BagDropApp extends StatelessWidget {
  const BagDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BagDrop',
      theme: AppTheme.light(),
      routes: {
        '/accesso': (_) => const AccessoScreen(),
        '/registrazione': (_) => const RegistrazioneScreen(),
        '/reset': (_) => const ResetPasswordScreen(),
      },
      home: const RootGate(), // <-- usa il wrapper che decide Onboarding/AuthGate
    );
  }
}

/// RootGate decide cosa mostrare all’avvio:
/// - se utente è loggato → HomeShell
/// - se NON loggato e Onboarding non visto (o forzato in DEV) → StartOnboarding
/// - altrimenti → AuthGate (che a sua volta mostra HomeShell loggato/non loggato)
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _checking = true;
  bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // In DEV ignora il flag per forzare l’onboarding
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

    // 1) Decidi SUBITO se mostrare l’onboarding
    final showOnboarding = kShowOnboardingEveryLaunch || !_onboardingSeen;
    if (showOnboarding) {
      return const StartOnboarding();
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Utente già loggato → vai subito alla Home
      return const HomeShell();
    }

    // Utente non loggato:
    // - in DEV → mostra SEMPRE l’onboarding
    // - in PROD → mostrala solo se non è stata vista
    if (kShowOnboardingEveryLaunch || !_onboardingSeen) {
      return const StartOnboarding();
    }

    // Altrimenti passa al tuo AuthGate (che mostra HomeShell loggato/non loggato)
    return AuthGate(
      ingressoBuilder: (_) => const _IngressoSplash(),
      signedOutBuilder: (_) => const HomeShell(),
      signedInBuilder: (_) => const HomeShell(),
    );
  }
}

class _IngressoSplash extends StatelessWidget {
  const _IngressoSplash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
