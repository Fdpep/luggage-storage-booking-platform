import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase/user_repo.dart';
import '../../utils/last_email_store.dart';

/// Verifica OTP con:
/// - Validazione 6 cifre
/// - Re-invio con cooldown
/// - Salvataggio e-mail al successo
class SchermataVerifyOtp extends StatefulWidget {
  final String email;
  final bool postSignup; // ci arriva dalla registrazione
  final bool isPartnerFlow;

  //  Dati extra usati SOLO nel flusso partner
  final String? partnerName;
  final String? partnerAddress;

  /// Vecchio campo totale (compat)
  final int? partnerCapacity;

  /// Nuovi campi per taglia (opzionali)
  final int? partnerCapacityS;
  final int? partnerCapacityM;
  final int? partnerCapacityL;
  final Map<String, dynamic>? partnerOpeningHours;

  final String? partnerMessage;
  final double? partnerLat;
  final double? partnerLng;

  const SchermataVerifyOtp({
    super.key,
    required this.email,
    this.postSignup = false,
    this.isPartnerFlow = false,
    this.partnerName,
    this.partnerAddress,
    this.partnerCapacity,
    this.partnerCapacityS,
    this.partnerCapacityM,
    this.partnerCapacityL,
    this.partnerMessage,
    this.partnerLat,
    this.partnerLng,
    this.partnerOpeningHours,
  });

  @override
  State<SchermataVerifyOtp> createState() => _SchermataVerifyOtpState();
}

class _SchermataVerifyOtpState extends State<SchermataVerifyOtp> with WidgetsBindingObserver {
  final TextEditingController _ctrlCodice = TextEditingController();
  bool _caricamento = false;

  // Cooldown per "Re-invia"
  int _secondsLeft = 0;
  Timer? _timer;
  Timer? _pollTimer;
  bool _polling = false;

  String? _validaCodice(String? value) {
    final v = (value ?? '').trim();
    if (v.length != 6) return 'Inserisci il codice a 6 cifre';
    if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Solo cifre (6)';
    return null;
  }

  void _startCooldown([int seconds = 45]) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

Future<void> _checkOtpVerifiedAndExitIfNeeded() async {
  final supabase = Supabase.instance.client;

  try {
    await supabase.auth.refreshSession();
    final u = supabase.auth.currentUser;
    if (u == null) return;

    final meta = Map<String, dynamic>.from(u.userMetadata ?? {});
    final verified = meta['otp_verified'] == true;

    if (verified && mounted) {
      // torna alla root così AuthGate ricalcola lo stato e cambia pagina
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  } catch (_) {
    // silent
  }
}


  Future<void> _verificaOTP() async {
    final codice = _ctrlCodice.text.trim();
    final errore = _validaCodice(codice);
    if (errore != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errore)),
      );
      return;
    }

    setState(() => _caricamento = true);
    final supabase = Supabase.instance.client;

    try {
      // 1) Verifica OTP → Supabase crea/aggiorna la sessione
      await supabase.auth.verifyOTP(
        email: widget.email,
        token: codice,
        type: OtpType.email,
      );

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verifica riuscita ma sessione non trovata. Riprova ad accedere.',
            ),
          ),
        );
        return;
      }

      // 2) Leggiamo i metadati attuali
      final currentMeta = Map<String, dynamic>.from(
        currentUser.userMetadata ?? {},
      );

      // Flag OTP verificato
      currentMeta['otp_verified'] = true;

      // --- LOGICA: capire se è un flusso partner o no ---
      final String? signupFlow = currentMeta['signup_flow'] as String?;
      final partnerSignupRaw = currentMeta['partner_signup'];

      final bool partnerFromMeta = partnerSignupRaw is Map<String, dynamic>;
      final bool isPartnerFlowEffective =
          widget.isPartnerFlow || signupFlow == 'partner' || partnerFromMeta;

      final Map<String, dynamic>? partnerSignup = partnerFromMeta
          ? Map<String, dynamic>.from(partnerSignupRaw as Map)
          : null;

      // 3) Aggiorniamo i metadati (OTP + eventuale pulizia campi temporanei)
      await supabase.auth.updateUser(UserAttributes(data: currentMeta));
      await supabase.auth.refreshSession();

      // 4) Salva e-mail e crea user_profile SOLO per utenti normali
      await LastEmailStore.save(widget.email);
      if (!isPartnerFlowEffective) {
        await UserRepo().upsertMe();
      }

      if (!mounted) return;

      // 5) Flusso diverso in base al tipo di signup
      if (isPartnerFlowEffective) {
        // ----- FLUSSO PARTNER (NUOVO) -----
        // Qui NON inviamo più nessuna richiesta da app.
        // L'app deve solo verificare OTP e poi mostrare le pagine status / rimando al sito.

        final userId = currentUser.id;

        // crea/aggiorna profilo (senza downgrade) e imposta partner_candidate
        // (se hai la RPC anche in app: meglio, così è garantito lato DB)
        try {
          await supabase.rpc('ensure_partner_candidate_role');
        } catch (_) {
          // fallback: prova update diretto (se RLS lo consente)
          await supabase.from('user_profiles').upsert({
            'id': userId,
            'role': 'partner_candidate',
          });
        }

        // pulisci eventuali campi temporanei dai metadata (opzionale)
        final newMeta = Map<String, dynamic>.from(
          supabase.auth.currentUser?.userMetadata ?? {},
        );
        newMeta.remove('partner_signup');
        await supabase.auth.updateUser(UserAttributes(data: newMeta));
        await supabase.auth.refreshSession();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verificata! Continua la registrazione dal sito.')),
        );

        // torna alla root: AuthGate mostrerà la pagina "continua dal sito" o lo stato
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        // ----- FLUSSO USER NORMALE -----
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verifica completata!')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      String readable = 'Codice non valido: ${e.message}';
      if (msg.contains('expired')) {
        readable = 'Codice scaduto. Richiedi un nuovo codice.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(readable)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imprevisto: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _caricamento = false);
    }
  }

  Future<void> _reinviaCodice() async {
    if (_secondsLeft > 0) return; // già in cooldown

    final supabase = Supabase.instance.client;
    try {
      await supabase.auth.signInWithOtp(email: widget.email);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nuovo codice inviato.')));
      }
      _startCooldown(45);
    } on AuthException catch (e) {
      var readable = 'Errore invio codice: ${e.message}';
      if (e.message.toLowerCase().contains('rate limit')) {
        readable = 'Hai richiesto troppi codici: riprova più tardi.';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(readable)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore invio codice: $e')));
      }
    }
  }

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);

  // check immediato
  _checkOtpVerifiedAndExitIfNeeded();

  // polling ogni 4s (più reattivo)
  _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
    if (_polling) return;
    _polling = true;
    _checkOtpVerifiedAndExitIfNeeded().whenComplete(() => _polling = false);
  });
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _checkOtpVerifiedAndExitIfNeeded();
  }
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _pollTimer?.cancel();
  _timer?.cancel();
  _ctrlCodice.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // blocchiamo il "back" di Navigator (Android indietro, freccia AppBar, ecc.)
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Completa la verifica dell’e-mail oppure chiudi l’app.',
            ),
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verifica codice'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () async {
                final supabase = Supabase.instance.client;
                try {
                  await supabase.auth.signOut();
                } catch (_) {}

                if (!mounted) return;

                // Reset navigazione: vai alla root dell'app (metti la tua route iniziale)
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              child: Text(
                'Esci',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'E-mail: ${widget.email}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Inserisci il codice (6 cifre) che ti abbiamo inviato via e-mail.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _ctrlCodice,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Codice OTP',
                    hintText: '••••••',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_caricamento,
                  onSubmitted: (_) => _verificaOTP(),
                ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _caricamento ? null : _verificaOTP,
                        child: _caricamento
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Verifica e accedi'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: (_caricamento || _secondsLeft > 0)
                          ? null
                          : _reinviaCodice,
                      child: Text(
                        _secondsLeft > 0
                            ? 'Invia (${_secondsLeft}s)'
                            : 'Invia codice',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
