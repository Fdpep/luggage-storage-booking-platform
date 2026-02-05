// routes/auth_gate.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// OTP screen
import '../schermate/autenticazione/verify_otp.dart';

// ⬇️ IMPORTA QUI le tue schermate partner-candidate
// Se non esistono ancora, per ora puoi puntare alla PartnerWaitingScreen,
// poi le sostituiamo con quelle nuove.
import '../schermate/partner/auth_partner/partner_waiting_screen.dart';
import '../schermate/partner/auth_partner/partner_onboarding_start_screen.dart';
import '../schermate/partner/auth_partner/partner_payment_required_screen.dart';
import '../schermate/partner/auth_partner/partner_rejected_screen.dart';

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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  Session? _session;
  bool _mostraIngresso = true;
  StreamSubscription<AuthState>? _sub;

  String? _role;
  bool _caricandoRuolo = false;

  // ⬇️ NUOVO: stato richiesta partner (solo se role=partner_candidate)
  String? _candidateStatus;
  bool _caricandoCandidate = false;

  bool _shownIncompleteWarning = false;
  String? _candidateRejectReason;
  Timer? _candidatePoll;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _session = _supabase.auth.currentSession;
    if (_session != null) {
      _loadRoleAndMaybeCandidate();
    }

    _sub = _supabase.auth.onAuthStateChange.listen((s) {
      if (!mounted) return;
      _candidatePoll?.cancel();
      _candidatePoll = null;
      setState(() {
        _session = s.session;
        _role = null;
        _candidateStatus = null;
        _caricandoRuolo = false;
        _caricandoCandidate = false;
        _shownIncompleteWarning = false;
        _candidateRejectReason = null;
      });

      if (s.session != null) {
        _loadRoleAndMaybeCandidate();
      }
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _mostraIngresso = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _candidatePoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // ✅ Non refreshare su ogni resume (camera/gallery compresi),
    // altrimenti smonti PartnerShell e torni alla dashboard.
    final shouldRefresh =
        _role == 'partner_candidate' && _candidateStatus == 'awaiting_payment';

    if (shouldRefresh) {
      _reloadAuthState(showLoader: false); // ✅ non mostra splash
    }
  }

  Future<void> _reloadAuthState({bool showLoader = false}) async {
    try {
      await _supabase.auth.refreshSession();
    } catch (_) {}

    final s = _supabase.auth.currentSession;
    if (!mounted) return;

    setState(() {
      _session = s;
      _caricandoRuolo = showLoader; // ✅ non smonta UI
      _caricandoCandidate = false;
    });

    _candidatePoll?.cancel();
    _candidatePoll = null;

    if (s != null) {
      await _loadRoleAndMaybeCandidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1) Splash / loading
    if (_mostraIngresso ||
        (_session != null && (_caricandoRuolo || _caricandoCandidate))) {
      return widget.ingressoBuilder(context);
    }

    // 2) non loggato
    if (_session == null) {
      return widget.signedOutBuilder(context);
    }

    // 3) OTP gate (come volevi tu): se otp_verified=false → VerifyOtp
    final user = _session!.user;
    final meta = user.userMetadata ?? {};
    final otpVerified = meta['otp_verified'] == true;

    if (!otpVerified) {
      final email = user.email;
      if (email == null || email.isEmpty)
        return widget.signedOutBuilder(context);

      return SchermataVerifyOtp(
        email: email,
        postSignup: false,
        isPartnerFlow: false, // registrazione partner da app verrà rimossa
      );
    }

    // 4) ruolo mancante => fallback (come prima)
    if (_role == null) {
      if (!_shownIncompleteWarning) {
        _shownIncompleteWarning = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registrazione non completata correttamente. '
                'Per favore ripeti la registrazione.',
              ),
            ),
          );
        });
      }
      return widget.signedOutBuilder(context);
    }

    // 5) routing per ruolo
    if (_role == 'admin' && widget.adminBuilder != null) {
      return widget.adminBuilder!(context);
    }

    // ✅ PARTNER CANDIDATE: decide in base a partner_requests.status
    if (_role == 'partner_candidate') {
      // Qui per ora usiamo waiting screen come fallback universale.
      // Poi sostituiremo con schermate dedicate:
      //
      // draft        -> PartnerOnboardingStartScreen()
      // submitted    -> PartnerWaitingScreen()
      // docs_approved-> PartnerPaymentRequiredScreen()
      // rejected     -> PartnerRejectedScreen()
      //
      switch (_candidateStatus) {
        case 'draft':
          return const PartnerOnboardingStartScreen();

        case 'submitted':
          return const PartnerWaitingScreen();

        // ✅ stato corretto per pagamento richiesto
        case 'awaiting_payment':
          return const PartnerPaymentRequiredScreen();

        case 'paid':
          // se mai rimanesse partner_candidate ma paid, lo tratto come “attivo”
          if (widget.partnerBuilder != null)
            return widget.partnerBuilder!(context);
          return widget.signedInBuilder(context);

        case 'rejected':
          return PartnerRejectedScreen(reason: _candidateRejectReason);

        default:
          // nessuna richiesta -> lo mando a iniziare dal sito
          return const PartnerOnboardingStartScreen();
      }
    }

    // PARTNER ATTIVO
    if (_role == 'partner' && widget.partnerBuilder != null) {
      return widget.partnerBuilder!(context);
    }

    // UTENTE NORMALE
    return widget.signedInBuilder(context);
  }

  // ==========================
  // LOADERS
  // ==========================

  Future<void> _loadRoleAndMaybeCandidate() async {
    final uid = _session?.user.id;
    if (uid == null) return;

    if (mounted) setState(() => _caricandoRuolo = true);

    try {
      final row = await _supabase
          .from('user_profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();

      final String? role = row?['role'] as String?;

      if (!mounted) return;
      setState(() {
        _role = role;
        _caricandoRuolo = false;
      });

      _candidatePoll?.cancel();
      if (role == 'partner_candidate') {
        _candidatePoll = Timer.periodic(const Duration(seconds: 20), (_) async {
          final uid = _session?.user.id;
          if (uid != null) await _loadCandidateStatus(uid, showLoader: false);
        });
      }

      // Se è partner_candidate carico anche lo stato della richiesta
      if (role == 'partner_candidate') {
        await _loadCandidateStatus(uid);
      }
    } catch (e) {
      _candidatePoll?.cancel();
      _candidatePoll = null;
      if (!mounted) return;
      setState(() {
        _caricandoRuolo = false;
      });
    }
  }

  Future<void> _loadCandidateStatus(
    String uid, {
    bool showLoader = true,
  }) async {
    if (mounted && showLoader) setState(() => _caricandoCandidate = true);

    try {
      final req = await _supabase
          .from('partner_requests')
          .select('id,status,reject_reason')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final String? st = req?['status'] as String?;
      final String? reason = req?['reject_reason'] as String?;

      if (!mounted) return;
      setState(() {
        _candidateStatus = st;
        _caricandoCandidate = false;
        _candidateRejectReason = reason;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _candidateStatus = null;
        _caricandoCandidate = false;
      });
    }
  }
}
