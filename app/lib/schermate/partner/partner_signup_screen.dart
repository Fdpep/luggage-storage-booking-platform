import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase/partner_repo.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/supabase/maps/map_geocoding_service.dart';

class PartnerSignUpScreen extends StatefulWidget {
  const PartnerSignUpScreen({super.key});

  @override
  State<PartnerSignUpScreen> createState() => _PartnerSignUpScreenState();
}

class _PartnerSignUpScreenState extends State<PartnerSignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  // Credenziali account
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwd2Ctrl = TextEditingController();

  // Dati attività
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _price2hCtrl = TextEditingController();
  final _pricePerDayCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  bool _busy = false;
  bool _showPwd = false;
  bool _showPwd2 = false;
  bool _acceptDocs = false;

  bool _isGeocoding = false;
  double? _lat;
  double? _lng;
  String? _addressError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _pwd2Ctrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _capacityCtrl.dispose();
    _price2hCtrl.dispose();
    _pricePerDayCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_acceptDocs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Devi accettare i Documenti contrattuali & Privacy per continuare.',
          ),
        ),
      );
      return;
    }

    // Verifichiamo che l'indirizzo sia stato geocodificato.
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conferma l\'indirizzo cliccando sulla lente accanto al campo.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    try {
      final email = _emailCtrl.text.trim();
      final pwd = _pwdCtrl.text;

      // 1) Crea account utente per l’attività
      await supabase.auth.signUp(
        email: email,
        password: pwd,
        data: {'source': 'bagdrop-partner-signup'},
      );
      // Se Supabase non crea subito una sessione, eseguiamo login esplicito
      if (supabase.auth.currentSession == null) {
        await supabase.auth.signInWithPassword(email: email, password: pwd);
      }

      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        throw Exception(
          'Registrazione partner fallita: utente non autenticato dopo signUp.',
        );
      }

      // 1bis) Marca il partner come "verificato" lato metadati → fa scattare il trigger SQL  
   
      final user = supabase.auth.currentUser!;
      final meta = Map<String, dynamic>.from(user.userMetadata ?? {});
      meta['otp_verified'] = true;  //COMMENTARE SE SI VUOLE LASCIARE A FALSE E CANCELLARE SE NON VERIFICATO
      meta['source'] = 'bagdrop-partner-signup';

      await supabase.auth.updateUser(UserAttributes(data: meta));

      // 2) Imposta ruolo 'partner' in user_profiles
      await supabase
          .from('user_profiles')
          .update({'role': 'partner'})
          .eq('id', uid);

      // 🔁 forza il refresh della sessione per far ricaricare il ruolo all’AuthGate
      await supabase.auth.refreshSession();

      // 3) Crea la richiesta partner (partners + partner_requests)
      final repo = PartnerRepo(supabase);

      final capacity = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
      final price2h = _price2hCtrl.text.trim().isEmpty
          ? null
          : double.parse(_price2hCtrl.text.trim().replaceAll(',', '.'));
      final pricePerDay = _pricePerDayCtrl.text.trim().isEmpty
          ? null
          : double.parse(_pricePerDayCtrl.text.trim().replaceAll(',', '.'));

      await repo.submitPartnerApplication(
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        capacity: capacity,
        price2h: price2h,
        pricePerDay: pricePerDay,
        message: _messageCtrl.text.trim().isEmpty
            ? null
            : _messageCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Richiesta inviata! Il nostro team la valuterà a breve.',
          ),
        ),
      );

      // Torna alla root: l’AuthGate ora vede role=partner e mostrerà PartnerShell
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore autenticazione: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Usa la Google Geocoding API per convertire l'indirizzo in lat/lng
  /// e salva il risultato in `_lat` e `_lng`.
  Future<void> _geocodeAddress() async {
    final rawAddress = _addressCtrl.text.trim();
    if (rawAddress.isEmpty) {
      setState(() {
        _addressError = 'Inserisci un indirizzo prima di cercare.';
      });
      return;
    }

    setState(() {
      _isGeocoding = true;
      _addressError = null;
    });

    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _addressError =
              'API key Google Maps mancante. Definisci GOOGLE_MAPS_API_KEY in .env.';
        });
        return;
      }

      final service = MapGeocodingService(apiKey: apiKey);
      final result = await service.geocodeAddress(rawAddress);

      if (result == null) {
        setState(() {
          _addressError =
              'Indirizzo non trovato. Prova con via, numero civico e città.';
          _lat = null;
          _lng = null;
        });
        return;
      }

      setState(() {
        _lat = result.lat;
        _lng = result.lng;
        _addressCtrl.text = result.formattedAddress; // indirizzo pulito
        _addressError = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeocoding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrazione partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crea il tuo account BagDrop come partner e invia la richiesta '
                    'per attivare la tua attività nel network.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // --- SEZIONE ACCOUNT ---
                  const Text(
                    'Dati account',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _emailCtrl,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      hintText: 'nome@attivita.com',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Inserisci un’e-mail';
                      if (!t.contains('@')) return 'E-mail non valida';
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _pwdCtrl,
                    obscureText: !_showPwd,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _showPwd = !_showPwd),
                        icon: Icon(
                          _showPwd ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.length < 6) {
                        return 'Minimo 6 caratteri';
                      }
                      return null;
                    },
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _pwd2Ctrl,
                    obscureText: !_showPwd2,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Conferma password',
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _showPwd2 = !_showPwd2),
                        icon: Icon(
                          _showPwd2 ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v != _pwdCtrl.text) {
                        return 'Le password non coincidono';
                      }
                      return null;
                    },
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),

                  const SizedBox(height: 24),

                  // --- SEZIONE ATTIVITÀ ---
                  const Text(
                    'Dati attività',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome attività',
                      hintText: 'Es: Bar Duomo',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Inserisci il nome dell’attività';
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Indirizzo',
                      hintText: 'Via / Piazza, numero civico, città',
                      suffixIcon: IconButton(
                        tooltip: 'Cerca sulla mappa',
                        icon: _isGeocoding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        onPressed: _isGeocoding ? null : _geocodeAddress,
                      ),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Inserisci un indirizzo';
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  if (_addressError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _addressError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _capacityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Capacità totale (numero di bagagli)',
                      hintText: 'Es: 30',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Inserisci un numero';
                      final n = int.tryParse(t);
                      if (n == null || n <= 0) {
                        return 'Numero non valido';
                      }
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _price2hCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo per 2 ore (EUR, opzionale)',
                      hintText: 'Es: 5.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _pricePerDayCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo per giorno (EUR, opzionale)',
                      hintText: 'Es: 12.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Messaggio al team (opzionale)',
                      hintText: 'Es: info aggiuntive sulla tua attività...',
                    ),
                    maxLines: 3,
                    enabled: !_busy,
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Checkbox(
                        value: _acceptDocs,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _acceptDocs = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Ho letto e accetto i Documenti contrattuali & Privacy.',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Invia richiesta come partner'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
