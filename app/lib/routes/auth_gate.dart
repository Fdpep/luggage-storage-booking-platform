//AuthGate (in routes/): è un guard di routing che
//ascolta lo stato di Supabase (sessione login) e decide
// quale albero di schermate mostrare: se loggato → app privata; se no → flusso di accesso.
// Così non si deve controllare l’autenticazione in ogni pagina.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Decide cosa mostrare in base allo stato di autenticazione.
/// - All’avvio: mostra una schermata d’ingresso (splash) per un attimo.
/// - Se c’è sessione: albero "loggato".
/// - Se non c’è sessione: albero "non loggato".
class AuthGate extends StatefulWidget {
  final WidgetBuilder ingressoBuilder; // splash/ingresso
  final WidgetBuilder signedInBuilder; // app privata (utente)
  final WidgetBuilder signedOutBuilder; // flusso accesso
  final WidgetBuilder? partnerBuilder; // app privata (partner)
  final WidgetBuilder? adminBuilder; // app privata (admin)

  const AuthGate({
    super.key,
    required this.ingressoBuilder,
    required this.signedInBuilder,
    required this.signedOutBuilder,
    this.partnerBuilder,
    this.adminBuilder,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _supabase = Supabase.instance.client;

  Session? _session;
  bool _mostraIngresso = true; // per la schermata d’ingresso
  StreamSubscription<AuthState>? _sub;

  String? _role; // <-- ruolo dell’utente
  bool _caricandoRuolo = false; // <-- flag caricamento ruolo

  @override
  void initState() {
    super.initState();
    debugPrint('[AuthGate] initState');

    // 1) Legge l’eventuale sessione già presente
    _session = _supabase.auth.currentSession;
    if (_session != null) {
      _loadRole(); //  carica ruolo se già loggato
    }

    // 2) Ascolta i cambi di stato (login/logout)
    _sub = _supabase.auth.onAuthStateChange.listen((s) {
      debugPrint('[AuthGate] onAuthStateChange: ${s.event}');
      if (!mounted) return;
      setState(() {
        _session = s.session;
        _role = null; // reset ruolo quando cambia sessione
        _caricandoRuolo = false; // azzera eventuale spinner precedente
      });
      if (s.session != null) {
        _loadRole(); //  carica ruolo appena loggati
      }
    });

    // 3) Mostra la schermata d’ingresso per un breve tempo
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _mostraIngresso = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[AuthGate] build: session=${_session != null}, role=$_role, loading=$_caricandoRuolo, ingresso=$_mostraIngresso',
    );

    // 1) Splash iniziale SEMPRE, oppure se sono loggato ma il ruolo non è pronto
    if (_mostraIngresso ||
        (_session != null && (_role == null || _caricandoRuolo))) {
      return widget.ingressoBuilder(context);
    }

    // 2) Non loggato → flusso accesso
    if (_session == null) {
      return widget.signedOutBuilder(context);
    }

    // 3) Loggato e ruolo caricato → instrada per ruolo
    if (_role == 'admin' && widget.adminBuilder != null) {
      return widget.adminBuilder!(context);
    }

    if (_role == 'partner' && widget.partnerBuilder != null) {
      return widget.partnerBuilder!(context);
    }

    // 4) Default: utente normale
    return widget.signedInBuilder(context);
  }

  Future<void> _loadRole() async {
    final uid = _session?.user.id;
    if (uid == null) return;

    if (mounted) {
      setState(() => _caricandoRuolo = true);
    }

    try {
      // Leggiamo SOLO la colonna 'role' dalla tabella user_profiles
      debugPrint('[AuthGate] _loadRole for uid=$uid');
      final row = await _supabase
          .from('user_profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle(); // ← evita Liste e gestisce 0/1 riga

      String role = (row?['role'] as String?) ?? 'user';
      debugPrint('[AuthGate] ruolo caricato: $role (row=$row)');

      if (!mounted) return;
      setState(() {
        _role = role;
        _caricandoRuolo = false;
      });
    } catch (e) {
      debugPrint('[AuthGate] ERRORE caricando ruolo: $e  (RLS? colonna role?)');
      if (!mounted) return;
      setState(() {
        _role = 'user'; // fallback prudente
        _caricandoRuolo = false;
      });
    }
  }
}
