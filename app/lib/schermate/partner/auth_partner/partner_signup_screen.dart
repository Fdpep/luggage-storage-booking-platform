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

  // Step corrente:
  // 0 = Dati account
  // 1 = Dati attività + indirizzo
  // 2 = Capacità + nota + privacy + invio
  int _step = 0;

  // Credenziali account
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwd2Ctrl = TextEditingController();

  // Dati attività
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Capacità – nuova logica

  /// Quanti bagagli MEDIUM (M) stanno nello spazio GENERALE
  final _baseMediumCtrl = TextEditingController();

  /// Capacità GENERALE accettata per taglia
  final _generalSCtrl = TextEditingController();
  final _generalMCtrl = TextEditingController();
  final _generalLCtrl = TextEditingController();

  /// Capacità EXTRA dedicata solo a quella taglia
  final _extraSCtrl = TextEditingController();
  final _extraMCtrl = TextEditingController();
  final _extraLCtrl = TextEditingController();

  // Messaggio al team
  final _messageCtrl = TextEditingController();

  int _parseNonNegative(String? text) {
    final t = (text ?? '').trim();
    final n = int.tryParse(t);
    if (n == null || n < 0) return 0;
    return n;
  }

  ({int baseS, int baseM, int baseL}) _computeBaseFromMedium() {
    final m = _parseNonNegative(_baseMediumCtrl.text);
    final baseS = m * 2;
    final baseM = m;
    final baseL = (m * 0.5).floor();
    return (baseS: baseS, baseM: baseM, baseL: baseL);
  }

  ({int capS, int capM, int capL, int total}) _computeFinalCapacities() {
    final base = _computeBaseFromMedium();

    final genS = _generalSCtrl.text.trim().isEmpty
        ? base.baseS
        : _parseNonNegative(_generalSCtrl.text);
    final genM = _generalMCtrl.text.trim().isEmpty
        ? base.baseM
        : _parseNonNegative(_generalMCtrl.text);
    final genL = _generalLCtrl.text.trim().isEmpty
        ? base.baseL
        : _parseNonNegative(_generalLCtrl.text);

    final extraS = _parseNonNegative(_extraSCtrl.text);
    final extraM = _parseNonNegative(_extraMCtrl.text);
    final extraL = _parseNonNegative(_extraLCtrl.text);

    final capS = genS + extraS;
    final capM = genM + extraM;
    final capL = genL + extraL;
    final total = capS + capM + capL;

    return (capS: capS, capM: capM, capL: capL, total: total);
  }

  int get _totalCapacity => _computeFinalCapacities().total;


  // Suggerimenti indirizzo (autocomplete)
  List<PlaceSuggestion> _addressSuggestions = [];
  bool _isAddressAutocompleteLoading = false;
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

    _baseMediumCtrl.dispose();
    _generalSCtrl.dispose();
    _generalMCtrl.dispose();
    _generalLCtrl.dispose();
    _extraSCtrl.dispose();
    _extraMCtrl.dispose();
    _extraLCtrl.dispose();

    _messageCtrl.dispose();
    super.dispose();
  }


  Future<void> _submit() async {
    // Validazione finale
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

    if (_totalCapacity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Imposta almeno 1 bagaglio complessivo tra S, M e L.'),
        ),
      );
      return;
    }

    // Controllo geocoding (con retry automatico)
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

      final caps = _computeFinalCapacities();
      final capS = caps.capS;
      final capM = caps.capM;
      final capL = caps.capL;
      final capacity = caps.total;

      if (capacity <= 0) {
        throw AuthException(
          'Inserisci almeno 1 posto tra S, M e L (spazio generale + extra).',
        );
      }

      final message = _messageCtrl.text.trim().isEmpty
          ? null
          : _messageCtrl.text.trim();

      // Crea account auth per il partner
      await supabase.auth.signUp(
        email: email,
        password: pwd,
        data: {
          'source': 'bagdrop-partner-signup',
          'otp_verified': false,
          'signup_flow': 'partner',
          'partner_signup': {
            'name': _nameCtrl.text.trim(),
            'address': _addressCtrl.text.trim(),
            'capacity': capacity,
            'capacity_s': capS,
            'capacity_m': capM,
            'capacity_l': capL,
            'message': message,
            'lat': _lat,
            'lng': _lng,
          },
        },
      );

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw AuthException(
          'Registrazione partner completata ma sessione non trovata. Riprova ad accedere.',
        );
      }

      // ignore: avoid_print
      print('[PartnerSignup] userId (currentUser.id) = ${currentUser.id}');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registrazione effettuata. Invia e verifica codice OTP per completare.',
          ),
        ),
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SchermataVerifyOtp(
            email: email,
            postSignup: true,
            isPartnerFlow: true,
            partnerName: _nameCtrl.text.trim(),
            partnerAddress: _addressCtrl.text.trim(),
            partnerCapacity: capacity,
            partnerMessage: message,
            partnerLat: _lat!,
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

  /// Gestione dei NEXT per step
  Future<void> _nextStep() async {
    if (_busy) return;

    if (_step == 0) {
      // Validazione campi account
      if (!(_formKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Validazione nome + indirizzo + geocoding
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

  /// Usa la Google Geocoding API per convertire l'indirizzo in lat/lng
  /// e salva il risultato in `_lat` e `_lng`.
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
  /// Quando scegli un suggerimento:
  ///  - compila il campo indirizzo
  ///  - chiama _geocodeAddress per riempire _lat / _lng.
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

  /// Autocomplete live (non usato direttamente nel flow attuale, ma pronto)
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
    final steps = ['Account', 'Attività', 'Capacità'];

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
        return _buildStepAccount();
      case 1:
        return _buildStepBusiness();
      case 2:
        return _buildStepCapacity();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepAccount() {
    return ListView(
      children: [
        Text(
          'Dati account',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Crea l’account con cui accederai all’area partner BagDrop.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
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
              onPressed:
                  _busy ? null : () => setState(() => _showPwd = !_showPwd),
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
              onPressed:
                  _busy ? null : () => setState(() => _showPwd2 = !_showPwd2),
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
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _buildStepBusiness() {
    return ListView(
      children: [
        Text(
          'Dati attività',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Queste informazioni saranno visibili nella scheda del tuo locale.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 8),
        Text(
          'L’indirizzo verrà usato per mostrare il tuo locale sulla mappa e nelle ricerche.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildStepCapacity() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final base = _computeBaseFromMedium();
    final caps = _computeFinalCapacities();

    return ListView(
      children: [
        Text(
          'Capacità magazzino bagagli',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Indica prima quanti bagagli MEDIUM (M) possono stare nello SPAZIO GENERALE. '
          'Da lì stimiamo lo spazio equivalente per S e L.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // 1) Base M
        TextFormField(
          controller: _baseMediumCtrl,
          decoration: const InputDecoration(
            labelText: 'Spazio generale (bagagli MEDIUM - M)',
            hintText: 'Es: 10',
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

        Card(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Spazio generale equivalente:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('• ${base.baseS} Small (S)'),
                Text('• ${base.baseM} Medium (M)'),
                Text('• ${base.baseL} Large (L)'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Capacità GENERALE che vuoi accettare',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        TextFormField(
          controller: _generalSCtrl,
          decoration: InputDecoration(
            labelText: 'Small (S) – generale',
            hintText: base.baseS.toString(),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n > base.baseS) {
              return 'Non puoi superare il suggerito (${base.baseS})';
            }
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _generalMCtrl,
          decoration: InputDecoration(
            labelText: 'Medium (M) – generale',
            hintText: base.baseM.toString(),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n > base.baseM) {
              return 'Non puoi superare il suggerito (${base.baseM})';
            }
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _generalLCtrl,
          decoration: InputDecoration(
            labelText: 'Large (L) – generale',
            hintText: base.baseL.toString(),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: (v) {
            final n = _parseNonNegative(v);
            if (n > base.baseL) {
              return 'Non puoi superare il suggerito (${base.baseL})';
            }
            return null;
          },
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 20),

        Text(
          'Spazio EXTRA dedicato (solo S / solo M / solo L)',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        TextFormField(
          controller: _extraSCtrl,
          decoration: const InputDecoration(
            labelText: 'Extra SMALL (S)',
            hintText: 'Es: 5',
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
            hintText: 'Es: 0',
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
            hintText: 'Es: 0',
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
        const SizedBox(height: 12),

        Text(
          'Capacità totale: $_totalCapacity bagagli',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Questi valori saranno usati da BagDrop per evitare overbooking.',
          style: textTheme.bodySmall,
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
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _nextStep,
            icon: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_step < 2 ? Icons.arrow_forward : Icons.send),
            label: Text(_step < 2 ? 'Avanti' : 'Invia richiesta'),
          ),
        ),
      ],
    );
  }
}
