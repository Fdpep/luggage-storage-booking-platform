import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase/user_repo.dart';
import '../../utils/last_email_store.dart';
import '../../services/supabase/partner_repo.dart';
import '../partner/partner_waiting_screen.dart';

//import '../home_shell.dart';

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
  final int? partnerCapacity;
  final double? partnerPrice2h;
  final double? partnerPricePerDay;
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
    this.partnerPrice2h,
    this.partnerPricePerDay,
    this.partnerMessage,
    this.partnerLat,
    this.partnerLng,
  });

  @override
  State<SchermataVerifyOtp> createState() => _SchermataVerifyOtpState();
}

class _SchermataVerifyOtpState extends State<SchermataVerifyOtp> {
  final TextEditingController _ctrlCodice = TextEditingController();
  bool _caricamento = false;

  // Cooldown per "Re-invia"
  int _secondsLeft = 0;
  Timer? _timer;

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

  Future<void> _verificaOTP() async {
    final codice = _ctrlCodice.text.trim();
    final errore = _validaCodice(codice);
    if (errore != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errore)));
      return;
    }

    setState(() => _caricamento = true);
    final supabase = Supabase.instance.client;

    try {
      // 1) Verifica OTP → qui Supabase crea/aggiorna la sessione
      await supabase.auth.verifyOTP(
        email: widget.email,
        token: codice,
        type: OtpType.email,
      );

      // 2) Segna l'utente come "verificato via OTP" nei metadati
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Verifica riuscita ma sessione non trovata. Riprova ad accedere.',
              ),
            ),
          );
        }
        return;
      }

      // 3) Segna l'utente come "verificato via OTP" nei metadati
      final currentMeta = Map<String, dynamic>.from(
        currentUser.userMetadata ?? {},
      );
      currentMeta['otp_verified'] = true;

      await supabase.auth.updateUser(UserAttributes(data: currentMeta));

      // (opzionale, ma utile) forza refresh della sessione
      await supabase.auth.refreshSession();

      // 4) Salva e-mail e upsert profilo
      await LastEmailStore.save(widget.email);
      if (!widget.isPartnerFlow) {
        await UserRepo().upsertMe();
      }

      if (!mounted) return;

      // 5) Navigazione diversa a seconda del flusso:
      if (widget.isPartnerFlow) {
        // ----- FLUSSO PARTNER -----

        final userId = currentUser.id;

        // Controllo che i dati partner fondamentali ci siano
        if (widget.partnerName == null ||
            widget.partnerAddress == null ||
            widget.partnerLat == null ||
            widget.partnerLng == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dati registrazione partner mancanti. Ripeti la registrazione.',
              ),
            ),
          );
          return;
        }

        // 5a) Imposta ruolo 'partner' in user_profiles
        await supabase
            .from('user_profiles')
            .update({'role': 'partner'})
            .eq('id', userId);

        // 5b) Crea la richiesta partner (partners + partner_requests)
        final repo = PartnerRepo(supabase);
        await repo.submitPartnerApplication(
          userId: userId,
          name: widget.partnerName!,
          address: widget.partnerAddress!,
          capacity: widget.partnerCapacity ?? 0,
          price2h: widget.partnerPrice2h,
          pricePerDay: widget.partnerPricePerDay,
          message: widget.partnerMessage,
          lat: widget.partnerLat,
          lng: widget.partnerLng,
        );

        // 5c) Snack + vai alla schermata di attesa partner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verifica completata! Richiesta partner inviata.'),
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PartnerWaitingScreen()),
          (route) => route.isFirst,
        );
      } else {
        // ----- FLUSSO USER NORMALE -----
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Verifica completata!')));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      String readable = 'Codice non valido: ${e.message}';
      if (msg.contains('expired')) {
        readable = 'Codice scaduto. Richiedi un nuovo codice.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(readable)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
    } finally {
      if (mounted) setState(() => _caricamento = false);
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
  void dispose() {
    _timer?.cancel();
    _ctrlCodice.dispose();

    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifica codice'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
    );
  }
}
