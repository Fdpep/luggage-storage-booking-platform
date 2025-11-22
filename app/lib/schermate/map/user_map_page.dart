import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/partner.dart'; // adatta il path se usi import assoluti
import '../../services/supabase/location/location_service.dart'; // nuovo servizio
import '../../services/supabase/maps/map_geocoding_service.dart';
import '../../services/supabase/maps/maps_config.dart';
import '../../services/supabase/location/places_autocomplete_service.dart';
import '../partner/user_view/partner_detail_screen.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';

/// Pagina mappa utente con Google Maps:
/// - centra inizialmente su Milano
/// - prova a centrare sulla posizione reale dell'utente (se permessi ok)
/// - carica partner approvati + attivi da Supabase
/// - mostra marker per partner, tap → card in basso
/// - pulsanti + / - per zoom
/// - pulsante "Cerca attività" (per ora mostra una bottom sheet con input indirizzo)
/// - pulsante "Mia posizione" per ricentrare la mappa sull'utente
class UserMapPage extends StatefulWidget {
  const UserMapPage();

  @override
  State<UserMapPage> createState() => UserMapPageState();
}

class UserMapPageState extends State<UserMapPage> {
  /// Supabase client per leggere i partner
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Servizio per la posizione utente
  final LocationService _locationService = LocationService();

  /// Lista partner sulla mappa
  List<Partner> _partners = [];

  /// Partner selezionato (toccato)
  Partner? _selectedPartner;

  /// Stato caricamento / errore
  bool _isLoading = true;
  String? _errorMessage;

  /// Flag per capire se stiamo cercando la posizione utente
  bool _isLocatingUser = false;

  /// True se abbiamo ottenuto almeno una volta la posizione (permessi ok)
  bool _hasLocationPermission = false;

  /// Controller per la Google Map
  GoogleMapController? _mapController;

  /// Service per il geocoding testuale (es. "Milano Centrale" -> lat/lng).
  /// Usiamo la stessa API key che hai configurato per Google Maps.
  final _geoService = MapGeocodingService(apiKey: MapsConfig.googleMapsApiKey);

  /// Service per i suggerimenti di indirizzo (autocomplete).
  final _placesService = PlacesAutocompleteService(
    apiKey: MapsConfig.googleMapsApiKey,
  );

  /// True mentre stiamo cercando un indirizzo e centrando la mappa.
  bool _isSearchingArea = false;

  /// Centro di default: Milano
  static const LatLng _defaultCenter = LatLng(45.4642, 9.19);
  static const double _defaultZoom = 13.0;

  /// Icone per marker normale / selezionato
  static final BitmapDescriptor _markerDefaultIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  static final BitmapDescriptor _markerSelectedIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  @override
  void initState() {
    super.initState();
    // All'avvio carichiamo i partner
    _loadPartners();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Carica i partner approvati + attivi da Supabase
  Future<void> _loadPartners() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _supabase
          .from('partners')
          .select()
          .eq('status', 'approved')
          .eq('is_active', true)
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      final partners = (data as List<dynamic>)
          .map((row) => Partner.fromMap(row as Map<String, dynamic>))
          .toList();

      setState(() {
        _partners = partners;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Errore caricamento partner per mappa: $e\n$st');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare i partner in questo momento.';
      });
    }
  }

  /// Prova a centrare la mappa sulla posizione attuale dell'utente
  Future<void> _initUserLocation() async {
    if (_mapController == null) return;

    setState(() {
      _isLocatingUser = true;
    });

    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos == null) {
        // Nessuna posizione (permesso negato o servizi disabilitati)
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile ottenere la tua posizione. Controlla i permessi o il GPS.',
            ),
          ),
        );
        return;
      }

      // Abbiamo una posizione valida → aggiorniamo lo state
      if (mounted) {
        setState(() {
          _hasLocationPermission = true;
        });
      }

      final target = LatLng(pos.latitude, pos.longitude);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 14),
      );
    } catch (e, st) {
      debugPrint('Errore posizione utente: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante il recupero della tua posizione.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLocatingUser = false;
      });
    }
  }

  /// Richiamato dal pulsante "Mia posizione"
  Future<void> _goToUserLocation() async {
    await _initUserLocation();
  }

  /// Costruisce il set di marker da mostrare sulla mappa
  Set<Marker> _buildMarkers() {
    // Filtra solo partner con coordinate valide (sicurezza lato Dart)
    final validPartners = _partners.where(
      (p) => p.lat != null && p.lng != null,
    );

    return validPartners.map((partner) {
      final isSelected = _selectedPartner?.id == partner.id;

      return Marker(
        markerId: MarkerId(partner.id),
        position: LatLng(partner.lat!, partner.lng!),
        icon: isSelected ? _markerSelectedIcon : _markerDefaultIcon,
        onTap: () {
          setState(() {
            _selectedPartner = partner;
          });
        },
      );
    }).toSet();
  }

  /// Tap sulla mappa vuota → deseleziona il partner
  void _onMapTap(LatLng position) {
    setState(() {
      _selectedPartner = null;
    });
  }

  /// Zoom in
  Future<void> _zoomIn() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.zoomIn());
  }

  /// Zoom out
  Future<void> _zoomOut() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.zoomOut());
  }

  /// bottone "Cerca attività":
  /// - mostra una bottom sheet con campo testo
  /// - mentre scrivi chiama PlacesAutocompleteService
  /// - tap su un suggerimento = centri la mappa su quell’indirizzo
  Future<void> _onSearchPressed() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final textController = TextEditingController();
        List<PlaceSuggestion> suggestions = [];
        String queryText = '';
        bool isLoading = false;

        Future<void> _updateSuggestions(
          String value,
          void Function(void Function()) setModalState,
        ) async {
          final query = value.trim();
          if (query.length < 3) {
            setModalState(() => suggestions = []);
            return;
          }

          setModalState(() => isLoading = true);
          final res = await _placesService.fetchSuggestions(query);
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
                    'Cerca una zona o indirizzo',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: 'Es. Milano Centrale, Duomo, Porta Romana...',
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
                              // Ritorniamo la descrizione come indirizzo da geocodificare
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
                      child: const Text('Cerca'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final query = result?.trim();
    if (query == null || query.isEmpty) return;

    await _searchAndCenterOn(query);
  }

  /// Usa MapGeocodingService per geocodificare una query testuale
  /// (es. "Milano Centrale") e centra la mappa sul primo risultato trovato.
  Future<void> _searchAndCenterOn(String query) async {
    // Se la mappa non è ancora pronta, evitiamo errori.
    if (_mapController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La mappa non è ancora pronta')),
      );
      return;
    }

    setState(() => _isSearchingArea = true);

    try {
      //
      // Esempio tipico:
      // final result = await _geoService.geocodeAddress(query);
      //
      // Qui assumo che ritorni un oggetto con campi `lat` e `lng` (double).
      final result = await _geoService.geocodeAddress(query);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun risultato trovato per questa ricerca'),
          ),
        );
        return;
      }

      // Se il tuo result ha nomi diversi (es. result.latitude), adattali qui.
      final target = LatLng(result.lat, result.lng);

      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 14),
      );
    } catch (e, st) {
      debugPrint('Errore durante il geocoding: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante la ricerca. Riprova.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSearchingArea = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        // 1) Google Map principale
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _defaultCenter,
            zoom: _defaultZoom,
          ),
          markers: _buildMarkers(),
          onMapCreated: (controller) {
            _mapController = controller;
            // appena la mappa è pronta, proviamo a centrarla sulla posizione utente
            _initUserLocation();
          },
          onTap: _onMapTap,
          myLocationEnabled:
              _hasLocationPermission, // per ora non mostriamo il "pallino blu"
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false, // usiamo i nostri pulsanti custom
          mapToolbarEnabled: false,
        ),

        // 2) Overlay caricamento
        if (_isLoading)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        // 3) Overlay errore
        if (_errorMessage != null && !_isLoading)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _errorMessage!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),

        // 4) Messaggio "nessun partner"
        if (!_isLoading && _errorMessage == null && _partners.isEmpty)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Nessun partner disponibile in questa zona.\n'
                  'Prova a ricaricare più tardi.',
                  style: textTheme.bodyMedium,
                ),
              ),
            ),
          ),

        // 5) Pulsante "Cerca attività" in alto
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSearchingArea ? null : _onSearchPressed,
                  icon: _isSearchingArea
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Cerca in zona'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 6) Pulsanti zoom + / -, più "Mia posizione" in basso a destra
        Positioned(
          right: 16,
          bottom: _selectedPartner != null ? 140 : 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                onPressed: _zoomIn,
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                onPressed: _zoomOut,
                child: const Icon(Icons.remove),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'my_location',
                onPressed: _isLocatingUser ? null : _goToUserLocation,
                child: _isLocatingUser
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ],
          ),
        ),

        // 7) Card in basso con il partner selezionato
        if (_selectedPartner != null)
          _PartnerBottomCard(
            partner: _selectedPartner!,
            onClose: () {
              setState(() {
                _selectedPartner = null;
              });
            },
            onOpenDetail: () {
              final selected = _selectedPartner;
              if (selected == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PartnerDetailScreen(partner: selected),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Card in basso che mostra le informazioni principali
/// del partner selezionato sulla mappa.
///
/// Ora:
/// - mostra nome, prezzi, capacità
/// - prova a caricare la foto di copertina tramite PartnerPhotoRepo
/// - se non trova cover → placeholder
/// - espone un bottone "Apri scheda" (callback onOpenDetail)
class _PartnerBottomCard extends StatefulWidget {
  final Partner partner;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  const _PartnerBottomCard({
    required this.partner,
    required this.onClose,
    required this.onOpenDetail,
  });

  @override
  State<_PartnerBottomCard> createState() => _PartnerBottomCardState();
}

class _PartnerBottomCardState extends State<_PartnerBottomCard> {
  final _photoRepo = const PartnerPhotoRepo();

  PartnerPhoto? _coverPhoto;
  bool _loadingCover = true;

  @override
  void initState() {
    super.initState();
    _loadCoverPhoto();
  }

  /// Carica la foto di copertina del partner (se presente).
  Future<void> _loadCoverPhoto() async {
    setState(() {
      _loadingCover = true;
    });

    try {
      final photo = await _photoRepo.fetchCoverPhoto(widget.partner.id);
      if (!mounted) return;
      setState(() {
        _coverPhoto = photo;
        _loadingCover = false;
      });
    } catch (e, st) {
      debugPrint('Errore nel caricamento cover partner: $e\n$st');
      if (!mounted) return;
      setState(() {
        _coverPhoto = null;
        _loadingCover = false;
      });
    }
  }

  /// Helper per formattare i prezzi se presenti
  String _formatPrice(double? value, String label) {
    if (value == null) return '';
    // In futuro potrai internazionalizzare/format tare meglio con intl
    return '$label ${value.toStringAsFixed(2)} €';
  }

  /// Widget che mostra:
  /// - spinner mentre carica
  /// - cover se presente
  /// - placeholder se non c'è nulla
  Widget _buildCoverImage(ColorScheme cs) {
    final borderRadius = BorderRadius.circular(12);

    if (_loadingCover) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: cs.surfaceVariant,
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_coverPhoto == null) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: cs.surfaceVariant,
        ),
        child: const Icon(Icons.photo, size: 32),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        _coverPhoto!.url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: cs.surfaceVariant,
            ),
            child: const Icon(Icons.broken_image, size: 28),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final partner = widget.partner;
    final price2h = _formatPrice(partner.price2h, '2h da');
    final pricePerDay = _formatPrice(partner.pricePerDay, 'Giorno da');

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Riga principale: immagine + info + X di chiusura
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Immagine di copertina (o placeholder)
                    _buildCoverImage(cs),
                    const SizedBox(width: 12),
                    // Testi (nome, indirizzo, prezzi)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nome partner
                          Text(
                            partner.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          // Indirizzo
                          if (partner.address != null &&
                              partner.address!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                partner.address!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: textTheme.bodySmall?.color
                                      ?.withOpacity(0.8),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          const SizedBox(height: 8),

                          // Prezzi → Wrap per evitare overflow
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (price2h.isNotEmpty)
                                Text(
                                  price2h,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (pricePerDay.isNotEmpty)
                                Text(pricePerDay, style: textTheme.bodyMedium),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Pulsante chiusura card
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Riga inferiore: capacità + bottone "Apri scheda"
                Row(
                  children: [
                    // Icona + testo capacità → flessibile
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.luggage, size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Capacità: ${partner.capacity}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    TextButton.icon(
                      onPressed: widget.onOpenDetail,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      label: const Text('Apri scheda'),
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
