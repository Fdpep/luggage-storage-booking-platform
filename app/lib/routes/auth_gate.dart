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
  final WidgetBuilder signedInBuilder; // app privata
  final WidgetBuilder signedOutBuilder; // flusso accesso
  final WidgetBuilder? partnerBuilder; //app privata (partner)

  const AuthGate({
    super.key,
    required this.ingressoBuilder,
    required this.signedInBuilder,
    required this.signedOutBuilder,
    this.partnerBuilder,
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
  bool _caricandoRuolo = false; // <-- ( flag caricamento ruolo

  @override
  void initState() {
    super.initState();

    // 1) Legge l’eventuale sessione già presente
    _session = _supabase.auth.currentSession;
        if (_session != null) {
      _loadRole();               // <-- (NUOVO)
    }


    // 2) Ascolta i cambi di stato (login/logout)
   _sub = _supabase.auth.onAuthStateChange.listen((s) {
      if (!mounted) return;
      setState(() {
        _session = s.session;
        _role = null;            // resettiamo il ruolo quando cambia sessione
      });
      if (s.session != null) {
        _loadRole();             // <-- carica ruolo appena loggati
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
    if (_mostraIngresso) return widget.ingressoBuilder(context);

    final loggato = _session != null;

    if (!loggato) {
      return widget.signedOutBuilder(context);
    }

   if (_role == 'partner' && widget.partnerBuilder != null) {
      return widget.partnerBuilder!(context);
    }
   return widget.signedInBuilder(context);

  }


  Future<void> _loadRole() async {
    final uid = _session?.user.id;
    if (uid == null) return;

    setState(() => _caricandoRuolo = true);

    try {
      // Leggiamo SOLO la colonna 'role' dalla tabella user_profiles
      final data = await _supabase
          .from('user_profiles')
          .select('role')
          .eq('id', uid)
          .limit(1);

      String role = 'user';
      if ( data.isNotEmpty) {
        role = (data.first['role'] as String?) ?? 'user';
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _caricandoRuolo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _role = 'user'; // fallback prudente
        _caricandoRuolo = false;
      });
    }
  }
}
