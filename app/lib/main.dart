import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
//import 'schermate/ingresso.dart';
import 'routes/auth_gate.dart';
import 'schermate/user/home_shell.dart';
import 'schermate/autenticazione/accesso.dart';
import 'schermate/autenticazione/registrazione.dart';
import 'schermate/autenticazione/reset_password.dart';
//import 'schermate/onboarding/start_onboarding.dart'; // <- onboarding
import 'schermate/partner/dashboard/partner_shell.dart';
import 'schermate/admin/admin_shell.dart'; // <- NUOVO
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// In DEV metti true per forzare l’onboarding ad ogni avvio.
/// In PROD lascialo false: verrà mostrato solo la prima volta.
//const bool kShowOnboardingEveryLaunch = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Se NON siamo su Web, proviamo a caricare il file .env.android
  //    (che hai dichiarato nel pubspec.yaml come asset)
  if (!kIsWeb) {
    try {
      await dotenv.load(
        fileName: 'assets/.env.android',
      ); // <-- NOTA: niente "assets/"
      debugPrint('Caricato .env.android');
    } catch (e) {
      debugPrint('Impossibile caricare assets/.env.android: $e');
    }
  }

  // 2) Leggiamo prima i dart-define (prioritari)
  const urlFromDefine = String.fromEnvironment('SUPABASE_URL');
  const keyFromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  // 3) Se i dart-define non sono impostati, prendiamo i valori da dotenv
  final supabaseUrl = urlFromDefine.isNotEmpty
      ? urlFromDefine
      : (dotenv.maybeGet('SUPABASE_URL') ?? '');
  final supabaseAnonKey = keyFromDefine.isNotEmpty
      ? keyFromDefine
      : (dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    debugPrint(
      'SUPABASE_URL o SUPABASE_ANON_KEY non impostate (né via dart-define né via .env.android)!',
    );
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const BagDropApp());
}

class BagDropApp extends StatelessWidget {
  const BagDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      restorationScopeId: 'bagdrop_app',
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
      partnerBuilder: (_) => PartnerShell(), // partner
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
