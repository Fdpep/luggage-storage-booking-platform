import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
//import 'schermate/ingresso.dart';
import 'routes/auth_gate.dart';
import 'schermate/home_shell.dart';
import 'schermate/autenticazione/accesso.dart';
import 'schermate/autenticazione/registrazione.dart';
import 'schermate/autenticazione/reset_password.dart';
//import 'schermate/onboarding/start_onboarding.dart'; // <- onboarding
import 'schermate/partner/partner_shell.dart';
import 'schermate/admin/admin_shell.dart'; // <- NUOVO
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// In DEV metti true per forzare l’onboarding ad ogni avvio.
/// In PROD lascialo false: verrà mostrato solo la prima volta.
//const bool kShowOnboardingEveryLaunch = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carichiamo il file .env solo se NON siamo su Web
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: 'assets/.env');
    } catch (e) {
      debugPrint(' Impossibile caricare assets/.env: $e');
    }
  }

  

  final supabaseUrl = kIsWeb
      ? const String.fromEnvironment('SUPABASE_URL')
      : (dotenv.env['SUPABASE_URL'] ?? '');

  final supabaseAnonKey = kIsWeb
      ? const String.fromEnvironment('SUPABASE_ANON_KEY')
      : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');

  //  assert/log per capire se sono vuote
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    debugPrint(' SUPABASE_URL o SUPABASE_ANON_KEY non impostate!');
  }

    await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

/*
  // 1) Carichiamo le variabili dal file .env
  await dotenv.load(fileName: 'assets/.env');
  // 2) Inizializziamo Supabase
  await SupabaseService.init();
*/

  /*
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
   */
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
      home: const RootGate(),
    );
  }
}

/// RootGate decide cosa mostrare all’avvio:
/// - se utente è loggato → HomeShell / PartnerShell / AdminShell (via AuthGate)
/// - se NON loggato e Onboarding non visto → StartOnboarding
/// - altrimenti → Accesso
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _checking = true;
  //bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Leggi SEMPRE il flag salvato: evita loop anche in DEV
    /*final prefs = await SharedPreferences.getInstance();
    _onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    */
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Se vuoi riattivare l'onboarding, decommenta qui:
    /*
    final showOnboarding = !_onboardingSeen;
    if (showOnboarding) {
      return const StartOnboarding();
    }
    */

    // Passiamo il controllo all'AuthGate
    return AuthGate(
      ingressoBuilder: (_) => const _IngressoSplash(),
      signedOutBuilder: (_) => const AccessoScreen(),
      signedInBuilder: (_) => const HomeShell(), // utente normale
      partnerBuilder: (_) => const PartnerShell(), // partner
      adminBuilder: (_) => const AdminShell(), // admin
    );
  }
}

class _IngressoSplash extends StatelessWidget {
  const _IngressoSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
