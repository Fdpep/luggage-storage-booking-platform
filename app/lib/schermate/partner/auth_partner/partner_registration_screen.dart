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
/// Ora strutturato a STEP:
/// 0 = Dati attività
/// 1 = Indirizzo
/// 2 = Capacità V2 (base M + extra + taglie accettate) + invio
class PartnerRegistrationScreen extends StatefulWidget {
  const PartnerRegistrationScreen({super.key});

  @override
  State<PartnerRegistrationScreen> createState() =>
      _PartnerRegistrationScreenState();
}

class _PartnerRegistrationScreenState extends State<PartnerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Step corrente: 0 = base, 1 = indirizzo, 2 = capacità
  int _step = 0;

  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Capacità – nuova logica

  /// Quanti bagagli MEDIUM (M) stanno nello spazio GENERALE
  final _baseMediumCtrl = TextEditingController();

  /// Capacità EXTRA dedicata solo a quella taglia
  final _extraSCtrl = TextEditingController();
  final _extraMCtrl = TextEditingController();
  final _extraLCtrl = TextEditingController();

  bool _acceptS = true;
bool _acceptM = true;
bool _acceptL = true;


  // Nota per admin
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

  /// Helpers capacità

  int _parseNonNegative(String? text) {
    final t = (text ?? '').trim();
    final n = int.tryParse(t);
    if (n == null || n < 0) return 0;
    return n;
  }

/// Equivalenze UI: 1M = 2S, 1L = 2M (quindi 1L = 4S)
({int baseS, int baseM, int baseL}) _computeBaseFromMedium() {
  final m = _parseNonNegative(_baseMediumCtrl.text);
  final baseS = m * 2;
  final baseM = m;
  final baseL = m ~/ 2; // floor
  return (baseS: baseS, baseM: baseM, baseL: baseL);
}

/// Valori V2 che salviamo nel DB:
/// - baseM (input)
/// - extraS/M/L (input)
/// - acceptS/M/L (toggle)
({int baseM, int extraS, int extraM, int extraL}) _computeV2Caps() {
  final baseM = _parseNonNegative(_baseMediumCtrl.text);
  final extraS = _parseNonNegative(_extraSCtrl.text);
  final extraM = _parseNonNegative(_extraMCtrl.text);
  final extraL = _parseNonNegative(_extraLCtrl.text);
  return (baseM: baseM, extraS: extraS, extraM: extraM, extraL: extraL);
}

bool get _hasAnySizeEnabled => _acceptS || _acceptM || _acceptL;



  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();

    _baseMediumCtrl.dispose();
    _extraSCtrl.dispose();
    _extraMCtrl.dispose();
    _extraLCtrl.dispose();

    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1) Validazione finale del form
    if (!(_formKey.currentState?.validate() ?? false)) return;

// 2) Controllo capacità V2
final v2 = _computeV2Caps();
if (v2.baseM <= 0) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Inserisci almeno 1 bagaglio M nello spazio generale.'),
    ),
  );
  return;
}
if (!_hasAnySizeEnabled) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Devi accettare almeno una taglia (S / M / L).'),
    ),
  );
  return;
}


    // 3) Controllo geocoding già fatto (lat/lng)
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

    // 4) OK, inviamo
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final client = Supabase.instance.client;

    // DEBUG
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
final v2 = _computeV2Caps();
final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

final repo = PartnerRepo(client);

await repo.submitPartnerApplication(
  userId: userId,
  name: _nameCtrl.text.trim(),
  address: _addressCtrl.text.trim(),

  // ===== V2 =====
  baseM: v2.baseM,
  extraS: v2.extraS,
  extraM: v2.extraM,
  extraL: v2.extraL,
  acceptS: _acceptS,
  acceptM: _acceptM,
  acceptL: _acceptL,

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

  /// STEP NAVIGATION
  Future<void> _nextStep() async {
    if (_busy) return;

    if (_step == 0) {
      // Validazione Nome attività
      if (!(_formKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Validazione Indirizzo + geocoding
      if (!(_formKey.currentState?.validate() ?? false)) return;

      if (_lat == null || _lng == null) {
        await _geocodeAddress();
        if (!mounted) return;
        if (_lat == null || _lng == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossibile confermare l\'indirizzo. Controlla il testo o usa la lente.',
              ),
            ),
          );
          return;
        }
      }

      setState(() => _step = 2);
    } else if (_step == 2) {
      // Step finale → submit
      await _submit();
    }
  }

  void _prevStep() {
    if (_busy) return;
    if (_step == 0) return;
    setState(() => _step -= 1);
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

    setState(() {
      _addressCtrl.text = chosen;
    });

    await _geocodeAddress();
  }

  // Usato per possibili evoluzioni di autocomplete live
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildStepHeader(),
                const SizedBox(height: 16),
                Expanded(child: _buildStepBody()),
                const SizedBox(height: 16),
                _buildBottomButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
    final cs = Theme.of(context).colorScheme;
    final steps = ['Attività', 'Indirizzo', 'Capacità'];

    return Row(
      children: List.generate(steps.length, (index) {
        final active = index == _step;
        final done = index < _step;

        Color fill;
        if (active) {
          fill = cs.primary;
        } else if (done) {
          fill = cs.primary.withOpacity(0.5);
        } else {
          fill = cs.surfaceVariant;
        }

        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: fill,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active || done ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 12,
                  color: active
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(done ? 0.8 : 0.6),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildStepActivity();
      case 1:
        return _buildStepAddress();
      case 2:
        return _buildStepCapacity();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepActivity() {
    return ListView(
      children: [
        Text(
          'Dati della tua attività',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Text(
          'Puoi aggiungere una breve nota per il team BagDrop (opzionale).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Nota per l’admin (opzionale)',
            hintText: 'Es. Siamo un nuovo bar in zona centro…',
          ),
          maxLines: 3,
          textInputAction: TextInputAction.done,
          enabled: !_busy,
        ),
      ],
    );
  }

  Widget _buildStepAddress() {
    return ListView(
      children: [
        Text(
          'Indirizzo dell’attività',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Indirizzo',
            hintText: 'Via / Piazza, numero civico, città',
            suffixIcon: IconButton(
              tooltip: 'Cerca sulla mappa',
              icon: const Icon(Icons.search),
              onPressed: _busy ? null : _openAddressSearch,
            ),
            errorText: _addressError,
          ),
          onTap: _busy ? null : _openAddressSearch,
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
        Text(
          'L’indirizzo verrà usato per mostrare il tuo locale sulla mappa e per calcolare le distanze.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildStepCapacity() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

final base = _computeBaseFromMedium();
final v2 = _computeV2Caps();

// preview “cap” solo UI (coerente col Partner.dart)
final baseU = v2.baseM * 2;
final capS = _acceptS ? (baseU + v2.extraS) : 0;
final capM = _acceptM ? ((baseU ~/ 2) + v2.extraM) : 0;
final capL = _acceptL ? ((baseU ~/ 4) + v2.extraL) : 0;


    return ListView(
      children: [
        Text(
          'Capacità del magazzino bagagli',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Partiamo dallo SPAZIO GENERALE: indica quanti bagagli MEDIUM (M) '
          'puoi ospitare contemporaneamente nello spazio principale.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // 1) Input base M generale
        TextFormField(
          controller: _baseMediumCtrl,
          decoration: const InputDecoration(
            labelText: 'Spazio generale (bagagli MEDIUM - M)',
            hintText: 'Es. 10',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n <= 0) {
              return 'Inserisci almeno 1 bagaglio M nello spazio generale';
            }
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        // 2) Riepilogo equivalenze automatiche
        Card(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secondo i calcoli BagDrop, questo spazio generale equivale a:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text('• ${base.baseS} bagagli SMALL (S)'),
                Text('• ${base.baseM} bagagli MEDIUM (M)'),
                Text('• ${base.baseL} bagagli LARGE (L)'),
                const SizedBox(height: 8),
                Text(
                  'Puoi partire da questi valori e ridurli per singola taglia.\n'
                  'Es: se non vuoi bagagli LARGE nello spazio generale → imposta 0.',
                  style: textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
  const SizedBox(height: 16),

Text(
  'Taglie che accetti nello spazio generale',
  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
),
const SizedBox(height: 8),

SwitchListTile.adaptive(
  title: const Text('Accetto SMALL (S)'),
  subtitle: Text('Capacità stimata: $capS'),
  value: _acceptS,
  onChanged: _busy ? null : (v) => setState(() => _acceptS = v),
),
SwitchListTile.adaptive(
  title: const Text('Accetto MEDIUM (M)'),
  subtitle: Text('Capacità stimata: $capM'),
  value: _acceptM,
  onChanged: _busy ? null : (v) => setState(() => _acceptM = v),
),
SwitchListTile.adaptive(
  title: const Text('Accetto LARGE (L)'),
  subtitle: Text('Capacità stimata: $capL'),
  value: _acceptL,
  onChanged: _busy ? null : (v) => setState(() => _acceptL = v),
),

if (!_hasAnySizeEnabled)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      'Devi attivare almeno una taglia.',
      style: TextStyle(color: theme.colorScheme.error),
    ),
  ),

        const SizedBox(height: 20),

        // 4) Spazio EXTRA dedicato
        Text(
          'Spazio EXTRA dedicato solo a una taglia\n(es. armadietti solo per S)',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        TextFormField(
          controller: _extraSCtrl,
          decoration: const InputDecoration(
            labelText: 'Extra SMALL (S)',
            hintText: 'Es. 5',
            helperText:
                'Questi posti sono riservati solo a S e non riducono lo spazio di M o L.',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n < 0) return 'Valore non valido';
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _extraMCtrl,
          decoration: const InputDecoration(
            labelText: 'Extra MEDIUM (M)',
            hintText: 'Es. 0',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n < 0) return 'Valore non valido';
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _extraLCtrl,
          decoration: const InputDecoration(
            labelText: 'Extra LARGE (L)',
            hintText: 'Es. 0',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n < 0) return 'Valore non valido';
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 16),

        // 5) Riepilogo capacità totale
        Card(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Riepilogo capacità totale',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
Text('Small (S): $capS'),
Text('Medium (M): $capM'),
Text('Large (L): $capL'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Il sistema userà questi numeri per bloccare le prenotazioni '
          'quando lo spazio è pieno.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _prevStep,
              child: const Text('Indietro'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _busy ? null : _nextStep,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_step < 2 ? 'Avanti' : 'Invia domanda'),
          ),
        ),
      ],
    );
  }
}
