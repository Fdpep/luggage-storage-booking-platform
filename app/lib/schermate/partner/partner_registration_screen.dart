import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'partner_waiting_screen.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/supabase/partner_repo.dart';
import '../../services/supabase/maps/map_geocoding_service.dart';

/// Form per registrare/modificare un’attività come Partner BagDrop.
///
/// Flusso:
/// - PRIMA VOLTA:
///   - non esiste partner per l'utente → INSERT in public.partners (status = 'pending')
///   - INSERT in public.partner_requests (status = 'pending')
///
/// - RIPROVA DOPO RIFIUTO / NUOVA DOMANDA:
///   - esiste già un partner per owner_id:
///       -> UPDATE di quel partner (nome, indirizzo, capacity, prezzi, status='pending', reject_reason=NULL, is_active=false)
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
  final _capacityCtrl = TextEditingController();
  final _price2hCtrl = TextEditingController();
  final _priceDayCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _busy = false;
  bool _isGeocoding = false;
  double? _lat;
  double? _lng;
  String? _addressError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _capacityCtrl.dispose();
    _price2hCtrl.dispose();
    _priceDayCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
  if (!(_formKey.currentState?.validate() ?? false)) return;

  // Verifica geocoding
  if (_lat == null || _lng == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Clicca sulla lente accanto all\'indirizzo per confermare la posizione.',
        ),
      ),
    );
    return;
  }

  FocusScope.of(context).unfocus();
  setState(() => _busy = true);

  final client = Supabase.instance.client;

  // 🔍 DEBUG: controlliamo subito lo stato auth
  final session = client.auth.currentSession;
  final user = client.auth.currentUser;
  // ignore: avoid_print
  print('[PartnerRegistration] currentSession=${session != null}, userId=${user?.id}');

  final userId = user?.id;

  if (userId == null) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(content: Text('Utente non autenticato (nessuna sessione attiva).')),
      );
    }
    setState(() => _busy = false);
    return;
  }

  try {
    final capacity = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
    final price2h = double.tryParse(_price2hCtrl.text.trim());
    final priceDay = double.tryParse(_priceDayCtrl.text.trim());
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    // 🔧 Usiamo il repository, passandogli ANCHE lo userId
    final repo = PartnerRepo(client);

      await repo.submitPartnerApplication(
        userId: userId,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        capacity: capacity,
        price2h: price2h,
        pricePerDay: priceDay,
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Errore di autenticazione: ${e.message}')));
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}


  /// Usa la Google Geocoding API per tradurre l'indirizzo in lat/lng
  /// e li salva in `_lat` e `_lng`.
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
              'Indirizzo non trovato. Prova a essere più preciso (via, numero, città).';
          _lat = null;
          _lng = null;
        });
        return;
      }

      setState(() {
        _lat = result.lat;
        _lng = result.lng;
        _addressCtrl.text = result.formattedAddress; // indirizzo "pulito"
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
                  decoration: InputDecoration(
                    labelText: 'Indirizzo',
                    hintText: 'Via e numero civico, città',
                    suffixIcon: IconButton(
                      tooltip: 'Cerca sulla mappa',
                      icon: _isGeocoding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      onPressed: _isGeocoding ? null : _geocodeAddress,
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci l’indirizzo';
                    }
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

                // Capacità
                TextFormField(
                  controller: _capacityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Capacità totale bagagli',
                    hintText: 'Es. 30',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) {
                      return 'Inserisci un numero valido (>0)';
                    }
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

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
