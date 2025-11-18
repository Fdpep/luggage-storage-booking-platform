import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/partner.dart'; // adatta il path se usi import assoluti
import '../../services/supabase/location/location_service.dart'; // nuovo servizio



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

  /// Controller per la Google Map
  GoogleMapController? _mapController;

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

      final target = LatLng(pos.latitude, pos.longitude);
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            // zoom di default per vista utente, puoi regolarlo
            target: _defaultCenter,
            zoom: _defaultZoom,
          ),
        ),
      );
      // In realtà vogliamo zoomare sulla posizione vera:
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
    final validPartners =
        _partners.where((p) => p.lat != null && p.lng != null);

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
  /// ora apre una bottom sheet con un campo testo.
  /// In futuro collegherai qui il tuo MapGeocodingService
  /// per centrare la mappa su una zona (es. "Milano Centrale").
  Future<void> _onSearchPressed() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final textController = TextEditingController();

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
                onSubmitted: (value) {
                  Navigator.of(ctx).pop(value);
                },
              ),
              const SizedBox(height: 12),
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

    final query = result?.trim();
    if (query == null || query.isEmpty) return;

    // TODO: collega qui il tuo MapGeocodingService per ottenere lat/lng da `query`
    // Esempio concettuale (adatta a come è fatto il tuo service):
    //
    // final geocoding = MapGeocodingService();
    // final coords = await geocoding.geocodeAddress(query);
    // if (coords != null && _mapController != null) {
    //   await _mapController!.animateCamera(
    //     CameraUpdate.newLatLngZoom(
    //       LatLng(coords.lat, coords.lng),
    //       14,
    //     ),
    //   );
    // }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ricerca "$query" ricevuta.\nCollega qui il MapGeocodingService per centrare la mappa.',
        ),
      ),
    );
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
          myLocationEnabled: false, // per ora non mostriamo il "pallino blu"
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
                  onPressed: _onSearchPressed,
                  icon: const Icon(Icons.search),
                  label: const Text('Cerca attività'),
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
              // TODO: navigazione alla schermata dettagli partner
              // Navigator.of(context).push(...);
            },
          ),
      ],
    );
  }
}

/// Card in basso che mostra le informazioni principali
/// del partner selezionato sulla mappa.
///
/// Per ora:
/// - mostra nome, prezzi, capacità
/// - ha un placeholder per l'immagine di copertina
/// - espone un bottone "Apri scheda" (callback onOpenDetail)
class _PartnerBottomCard extends StatelessWidget {
  final Partner partner;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  const _PartnerBottomCard({
    required this.partner,
    required this.onClose,
    required this.onOpenDetail,
  });

  /// Helper per formattare i prezzi se presenti
  String _formatPrice(double? value, String label) {
    if (value == null) return '';
    // In futuro potrai internazionalizzare/format tare meglio con intl
    return '$label ${value.toStringAsFixed(2)} €';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
            borderRadius: BorderRadius.circular(16),
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
                    // Placeholder per immagine di copertina:
                    // in futuro potrai collegare PartnerPhotoRepo.fetchCoverPhoto(partner.id)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: cs.surfaceVariant,
                      ),
                      child: const Icon(Icons.photo, size: 32),
                    ),
                    const SizedBox(width: 12),
                    // Testi (nome, indirizzo, prezzi)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.name,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (partner.address != null &&
                              partner.address!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                partner.address!,
                                style: textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (price2h.isNotEmpty)
                                Text(
                                  price2h,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.primary,
                                  ),
                                ),
                              if (price2h.isNotEmpty && pricePerDay.isNotEmpty)
                                const SizedBox(width: 8),
                              if (pricePerDay.isNotEmpty)
                                Text(pricePerDay, style: textTheme.bodyMedium),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Pulsante chiusura card
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Riga inferiore: info extra + bottone "Apri scheda"
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Capacità: ${partner.capacity}',
                      style: textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: onOpenDetail,
                      child: const Text('Apri scheda'),
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