import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../autenticazione/verify_otp.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../services/supabase/maps/map_geocoding_service.dart';
import '../../../services/supabase/location/places_autocomplete_service.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

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

  // Suggerimenti indirizzo (autocomplete)
  List<PlaceSuggestion> _addressSuggestions = [];
  bool _isAddressAutocompleteLoading = false;
  // ignore: unused_field
  String _addressQuery = '';

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
    // 1) Validazione form
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

    // 2) Controllo geocoding (con retry automatico)
    if (_isGeocoding) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attendi che la ricerca dell\'indirizzo sia completata.',
          ),
        ),
      );
      return;
    }

    if (_lat == null || _lng == null) {
      await _geocodeAddress();

      if (!mounted) return;

      if (_lat == null || _lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile confermare l\'indirizzo.\n'
              'Controlla il testo o riprova usando la lente accanto al campo.',
            ),
          ),
        );
        return;
      }
    }


    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    try {
      final email = _emailCtrl.text.trim();
      final pwd = _pwdCtrl.text;

      // per creare la richiesta partner
      final capacity = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
      final price2h = _price2hCtrl.text.trim().isEmpty
          ? null
          : double.parse(_price2hCtrl.text.trim().replaceAll(',', '.'));
      final pricePerDay = _pricePerDayCtrl.text.trim().isEmpty
          ? null
          : double.parse(_pricePerDayCtrl.text.trim().replaceAll(',', '.'));
      final message = _messageCtrl.text.trim().isEmpty
          ? null
          : _messageCtrl.text.trim();

      // 3) Crea account auth per il partner
      await supabase.auth.signUp(
        email: email,
        password: pwd,
        data: {
          'source': 'bagdrop-partner-signup',
          'otp_verified': false, // parte sempre non verificato

          // *** NUOVI CAMPI IMPORTANTI ***
          'signup_flow': 'partner',        // ci dice che questo è un sign-up partner
          'partner_signup': {
            'name': _nameCtrl.text.trim(),
            'address': _addressCtrl.text.trim(),
            'capacity': capacity,
            'price2h': price2h,
            'pricePerDay': pricePerDay,
            'message': message,
            'lat': _lat,
            'lng': _lng,
          },
        },
      );


      // 4) Se non ha creato sessione subito, fai login esplicito
      /* if (supabase.auth.currentSession == null) {
        await supabase.auth.signInWithPassword(email: email, password: pwd);
      }  */
      //mando otp
      //await supabase.auth.signInWithOtp(email: email);

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw AuthException(
          'Registrazione partner completata ma sessione non trovata. Riprova ad accedere.',
        );
      }

      // DEBUG
      // ignore: avoid_print
      print('[PartnerSignup] userId (currentUser.id) = ${currentUser.id}');

      if (!mounted) return;

      // 5) Avvisa che deve completare la verifica
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registrazione effettuata. Invia e verifica codice OTP per completare.',
          ),
        ),
      );

      // 6) Vai alla schermata di verifica OTP, passando i dati partner
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SchermataVerifyOtp(
            email: email,
            postSignup: true,
            isPartnerFlow: true,
            partnerName: _nameCtrl.text.trim(),
            partnerAddress: _addressCtrl.text.trim(),
            partnerCapacity: capacity,
            partnerPrice2h: price2h,
            partnerPricePerDay: pricePerDay,
            partnerMessage: message,
            partnerLat: _lat!, // safe: li abbiamo controllati sopra
            partnerLng: _lng!,
          ),
        ),
      );
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

  /// Apre una bottom sheet con autocomplete indirizzo (Google Places).
  /// Quando scegli un suggerimento:
  ///  - compila il campo indirizzo
  ///  - chiama _geocodeAddress per riempire _lat / _lng.
  Future<void> _openAddressSearch() async {
    setState(() {
      _addressError = null;
    });

    // Leggi API key: dart-define su Web, .env su mobile
    final apiKey = kIsWeb
        ? const String.fromEnvironment('GOOGLE_MAPS_API_KEY')
        : (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '');

    if (apiKey.isEmpty) {
      setState(() {
        _addressError =
            'API key Google Maps mancante. Definisci GOOGLE_MAPS_API_KEY oppure passa il dart-define.';
      });
      return;
    }

    final placesService = PlacesAutocompleteService(apiKey: apiKey);

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final textController = TextEditingController(text: _addressCtrl.text);
        List<PlaceSuggestion> suggestions = [];
        String queryText = textController.text;
        bool isLoading = false;

        Future<void> _updateSuggestions(
          String value,
          void Function(void Function()) setModalState,
        ) async {
          final q = value.trim();
          if (q.length < 3) {
            setModalState(() => suggestions = []);
            return;
          }

          setModalState(() => isLoading = true);
          final res = await placesService.fetchSuggestions(q);
          setModalState(() {
            isLoading = false;
            suggestions = res;
          });
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cerca indirizzo attività',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: 'Via / Piazza, numero civico, città',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      setModalState(() => queryText = value);
                      _updateSuggestions(value, setModalState);
                    },
                    onSubmitted: (value) {
                      Navigator.of(ctx).pop(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  if (!isLoading &&
                      suggestions.isEmpty &&
                      queryText.trim().length < 3)
                    const Text(
                      'Digita almeno 3 caratteri per vedere i suggerimenti',
                      style: TextStyle(fontSize: 12),
                    ),
                  if (isLoading) const LinearProgressIndicator(),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: suggestions.length,
                        itemBuilder: (ctx, index) {
                          final s = suggestions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(s.description),
                            onTap: () {
                              Navigator.of(ctx).pop(s.description);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop(textController.text);
                      },
                      child: const Text('Usa questo indirizzo'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final chosen = selected?.trim();
    if (chosen == null || chosen.isEmpty) return;

    // 1) Aggiorniamo il campo indirizzo con il testo scelto
    setState(() {
      _addressCtrl.text = chosen;
    });

    // 2) E facciamo il geocoding "classico" per lat/lng
    await _geocodeAddress();
  }



/// Chiamato mentre l'utente scrive nell'indirizzo.
/// Usa PlacesAutocompleteService per mostrare i suggerimenti live.
  Future<void> _onAddressChanged(String value) async {
    setState(() {
      _addressQuery = value;
      _addressError = null;
    });

    final query = value.trim();
    if (query.length < 3) {
      setState(() => _addressSuggestions = []);
      return;
    }

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _addressError =
            'API key Google Maps mancante. Definisci GOOGLE_MAPS_API_KEY in .env.';
        _addressSuggestions = [];
      });
      return;
    }

    setState(() => _isAddressAutocompleteLoading = true);
    final placesService = PlacesAutocompleteService(apiKey: apiKey);
    final suggestions = await placesService.fetchSuggestions(query);

    if (!mounted) return;
    setState(() {
      _isAddressAutocompleteLoading = false;
      _addressSuggestions = suggestions;
    });
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
                        // La lente fa ancora il geocoding "manuale"
                        onPressed: _openAddressSearch,
                        //onPressed: _isGeocoding ? null : _geocodeAddress,
                      ),
                      errorText: _addressError,
                    ),
                    onTap: _openAddressSearch,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Inserisci un indirizzo';
                      return null;
                    },
                    enabled: !_busy,
                    onChanged: (value) {
                      if (_busy) return;
                      _onAddressChanged(value);
                    },
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
                  if (_isAddressAutocompleteLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(),
                    ),
                  if (_addressSuggestions.isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: _addressSuggestions.length,
                        itemBuilder: (context, index) {
                          final s = _addressSuggestions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(s.description),
                            onTap: () async {
                              // 1) Mettiamo il testo scelto nel campo
                              setState(() {
                                _addressCtrl.text = s.description;
                                _addressSuggestions = [];
                              });
                              // 2) Facciamo il geocoding per riempire _lat / _lng
                              await _geocodeAddress();
                            },
                          );
                        },
                      ),
                    ),
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
