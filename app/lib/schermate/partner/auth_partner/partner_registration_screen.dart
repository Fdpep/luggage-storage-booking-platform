// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'partner_waiting_screen.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../services/supabase/partner_repo.dart';
import '../../../services/supabase/maps/map_geocoding_service.dart';
import '../../../services/supabase/location/places_autocomplete_service.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Form per registrare/modificare un’attività come Partner BagDrop.
///
/// Flusso:
/// - PRIMA VOLTA:
///   - non esiste partner per l'utente → INSERT in public.partners (status = 'pending')
///   - INSERT in public.partner_requests (status = 'pending')
///
/// - RIPROVA DOPO RIFIUTO / NUOVA DOMANDA:
///   - esiste già un partner per owner_id:
///       -> UPDATE di quel partner (nome, indirizzo, capacità S/M/L, prezzi, status='pending', reject_reason=NULL, is_active=false)
///   - su partner_requests:
///       -> se esiste una richiesta per quel partner → UPDATE (status='pending', admin_note=NULL, reviewed_* = NULL, message=nota nuova)
///       -> altrimenti INSERT nuova riga
///
/// Alla fine: vai alla PartnerWaitingScreen (solo messaggio + logout),
/// SENZA distruggere RootGate/AuthGate.
class PartnerRegistrationScreen extends StatefulWidget {
  const PartnerRegistrationScreen({super.key});

  @override
  State<PartnerRegistrationScreen> createState() =>
      _PartnerRegistrationScreenState();
}

class _PartnerRegistrationScreenState extends State<PartnerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // 🔹 NUOVO: capacità per taglia
  final _capacitySCtrl = TextEditingController();
  final _capacityMCtrl = TextEditingController();
  final _capacityLCtrl = TextEditingController();

  final _price2hCtrl = TextEditingController();
  final _priceDayCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  // Suggerimenti indirizzo (autocomplete)
  List<PlaceSuggestion> _addressSuggestions = [];
  bool _isAddressAutocompleteLoading = false;
  String _addressQuery = '';

  bool _busy = false;
  bool _isGeocoding = false;
  double? _lat;
  double? _lng;
  String? _addressError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _capacitySCtrl.dispose();
    _capacityMCtrl.dispose();
    _capacityLCtrl.dispose();
    _price2hCtrl.dispose();
    _priceDayCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1) Validazione base del form
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 2) Se il geocoding è ancora in corso, chiedi di aspettare
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

    // 3) Se non abbiamo ancora lat/lng, proviamo un geocoding automatico
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

    // 4) OK, indirizzo valido → procediamo con l’invio
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final client = Supabase.instance.client;

    // DEBUG: controlliamo lo stato auth
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;
    // ignore: avoid_print
    print(
      '[PartnerRegistration] currentSession=${session != null}, userId=${user?.id}',
    );

    final userId = user?.id;

    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Utente non autenticato (nessuna sessione attiva).'),
        ),
      );
      setState(() => _busy = false);
      return;
    }

    try {
      // 🔹 Leggiamo capacità per taglia
      final capS = int.tryParse(_capacitySCtrl.text.trim()) ?? 0;
      final capM = int.tryParse(_capacityMCtrl.text.trim()) ?? 0;
      final capL = int.tryParse(_capacityLCtrl.text.trim()) ?? 0;

      // capacità totale (ridondante, ma utile per compat/riassunto)
      final totalCapacity = capS + capM + capL;

      final price2h = double.tryParse(_price2hCtrl.text.trim());
      final priceDay = double.tryParse(_priceDayCtrl.text.trim());
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

      final repo = PartnerRepo(client);

      await repo.submitPartnerApplication(
        userId: userId,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        // compat: teniamo anche la capacità totale
        capacity: totalCapacity,
        // 🔹 NUOVO: salviamo capacità per taglia
        capacityS: capS,
        capacityM: capM,
        capacityL: capL,
        message: note,
        lat: _lat,
        lng: _lng,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Domanda inviata. Il nostro team la visionerà a breve.',
          ),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PartnerWaitingScreen()),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore database: ${e.message}')));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore di autenticazione: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  /// Usa la Google Geocoding API per tradurre l'indirizzo in lat/lng
  /// e li salva in `_lat` e `_lng`.
  Future<void> _geocodeAddress() async {
    final rawAddress = _addressCtrl.text.trim();
    if (rawAddress.isEmpty) {
      if (!mounted) return;
      setState(() {
        _addressError = 'Inserisci un indirizzo prima di cercare.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isGeocoding = true;
      _addressError = null;
    });

    try {
      final apiKey = _readGoogleApiKey();
      if (apiKey.isEmpty) {
        if (!mounted) return;
        setState(() {
          _addressError =
              'API key Google Maps mancante. Definisci GOOGLE_MAPS_API_KEY '
              'in .env (mobile) o come --dart-define su Web.';
        });
        return;
      }

      final service = MapGeocodingService(apiKey: apiKey);
      final result = await service.geocodeAddress(rawAddress);

      if (!mounted) return;

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
        _addressCtrl.text = result.formattedAddress;
        _addressError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addressError = 'Errore durante il geocoding: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeocoding = false;
      });
    }
  }

  String _readGoogleApiKey() {
    if (kIsWeb) {
      const key = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
      return key;
    } else {
      return dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    }
  }

  /// Apre una bottom sheet con autocomplete indirizzo (Google Places).
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
  /// (Al momento non è più collegato al TextField, ma lo lasciamo per evoluzioni future)
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
        title: const Text('Domanda per diventare Partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compila i dati della tua attività. '
                  'Un admin BagDrop verificherà la richiesta.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),

                // Nome attività
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome attività',
                    hintText: 'Es. Bar Centrale',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci il nome dell’attività';
                    }
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                // Indirizzo
                TextFormField(
                  controller: _addressCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Indirizzo',
                    hintText: 'Via / Piazza, numero civico, città',
                    suffixIcon: IconButton(
                      tooltip: 'Cerca sulla mappa',
                      icon: const Icon(Icons.search),
                      onPressed: _openAddressSearch,
                    ),
                    errorText: _addressError,
                  ),
                  onTap: _openAddressSearch,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Inserisci un indirizzo';
                    return null;
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
                            setState(() {
                              _addressCtrl.text = s.description;
                              _addressSuggestions = [];
                            });
                            await _geocodeAddress();
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),

                // 🔹 NUOVO BLOCCO: capacità per taglia
                Text(
                  'Capacità massima per taglia bagagli',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacitySCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli SMALL (S)',
                    hintText: 'Es. 10',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    final n = int.tryParse(t);
                    if (n == null || n < 0) {
                      return 'Inserisci un numero valido (≥ 0)';
                    }
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _capacityMCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli MEDIUM (M)',
                    hintText: 'Es. 10',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    final n = int.tryParse(t);
                    if (n == null || n < 0) {
                      return 'Inserisci un numero valido (≥ 0)';
                    }
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _capacityLCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli LARGE (L)',
                    hintText: 'Es. 10',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    final n = int.tryParse(t);
                    if (n == null || n < 0) {
                      return 'Inserisci un numero valido (≥ 0)';
                    }
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 16),

                // Prezzo 2h
                TextFormField(
                  controller: _price2hCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prezzo per 2 ore (opzionale)',
                    hintText: 'Es. 4.50',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                // Prezzo giorno
                TextFormField(
                  controller: _priceDayCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prezzo per giorno (opzionale)',
                    hintText: 'Es. 10.00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                // Nota per l’admin
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota per l’admin (opzionale)',
                    hintText: 'Es. Siamo un nuovo bar in zona centro…',
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  enabled: !_busy,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Invia domanda'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
