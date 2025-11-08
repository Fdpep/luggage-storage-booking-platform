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

  const AuthGate({
    super.key,
    required this.ingressoBuilder,
    required this.signedInBuilder,
    required this.signedOutBuilder,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _supabase = Supabase.instance.client;

  Session? _session;
  bool _mostraIngresso = true;   // per la schermata d’ingresso
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();

    // 1) Legge l’eventuale sessione già presente
    _session = _supabase.auth.currentSession;

    // 2) Ascolta i cambi di stato (login/logout)
    _sub = _supabase.auth.onAuthStateChange.listen((s) {
      if (!mounted) return;
      setState(() => _session = s.session);
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
    return loggato
        ? widget.signedInBuilder(context)
        : widget.signedOutBuilder(context);
  }
}
