import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/schermate/partner/user_view/booking_flow_screen.dart';

/// Schermata di dettaglio di un partner (vista dall'utente).
///
/// Mostra:
/// - foto del locale
/// - descrizione breve
/// - prezzi
/// - orari di apertura (se presenti)
/// - regole (peso massimo, oggetti vietati, ecc.)
/// - posizione su mappa
/// - capacità massima + disponibilità attuale
/// - pulsante "Prenota ora".
class PartnerDetailScreen extends StatefulWidget {
  final Partner partner;

  const PartnerDetailScreen({super.key, required this.partner});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  final _photoRepo = const PartnerPhotoRepo();

  List<PartnerPhoto> _photos = [];
  bool _loadingPhotos = true;
  int _currentPhotoIndex = 0;

  PartnerAvailability? _availability;
  bool _loadingAvailability = true;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadAvailability();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _photoRepo.fetchPhotosForPartner(widget.partner.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (e, st) {
      debugPrint('Errore nel caricamento foto partner: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingPhotos = false;
      });
    }
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _loadingAvailability = true;
      _availabilityError = null;
    });

    try {
      final client = Supabase.instance.client;
      final repo = PartnerBookingRepo(client);
      final availability = await repo.getPartnerAvailability(widget.partner.id);
      if (!mounted) return;
      setState(() {
        _availability = availability;
        _loadingAvailability = false;
      });
    } catch (e, st) {
      debugPrint('Errore nel calcolo disponibilità: $e\n$st');
      if (!mounted) return;
      setState(() {
        _availabilityError =
            'Impossibile calcolare la disponibilità in questo momento.';
        _loadingAvailability = false;
      });
    }
  }

  String _formatPrice(double? value, String label) {
    if (value == null) return '';
    return '$label ${value.toStringAsFixed(2)} €';
  }

  Widget _buildPhotoSection(ColorScheme cs) {
    if (_loadingPhotos) {
      return SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    if (_photos.isEmpty) {
      // Placeholder se non ci sono foto
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Icon(Icons.photo, size: 48)),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: PageView.builder(
              itemCount: _photos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPhotoIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final p = _photos[index];
                return Image.network(
                  p.url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                (progress.expectedTotalBytes ?? 1)
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: cs.surfaceVariant,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 40),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Indicatori pagina
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_photos.length, (index) {
            final isActive = index == _currentPhotoIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 10 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildOpeningHours(ThemeData theme) {
    final opening = widget.partner.openingHours;
    if (opening == null || opening.isEmpty) {
      return const Text('Orari non disponibili');
    }

    // Se hai codificato gli orari come { "text": "Lun-Ven 9-18..." }
    final text = opening['text'];
    if (text is String && text.trim().isNotEmpty) {
      return Text(text, style: theme.textTheme.bodyMedium);
    }

    // Fallback: mostriamo chiave: valore.toString()
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: opening.entries.map((e) {
        return Text('${e.key}: ${e.value}', style: theme.textTheme.bodyMedium);
      }).toList(),
    );
  }

  Widget _buildMapPreview() {
    final lat = widget.partner.lat;
    final lng = widget.partner.lng;
    if (lat == null || lng == null) {
      return const Text('Posizione non disponibile');
    }

    final position = LatLng(lat, lng);

    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: position, zoom: 15),
          markers: {
            Marker(markerId: const MarkerId('partner'), position: position),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          liteModeEnabled: true, // se hai abilitato Lite Mode
          onMapCreated: (_) {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.partner;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    final price2h = _formatPrice(partner.price2h, '2h da');
    final pricePerDay = _formatPrice(partner.pricePerDay, 'Giorno da');

    return Scaffold(
      appBar: AppBar(title: Text(partner.name)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoSection(cs),
              const SizedBox(height: 16),

              // Nome + indirizzo
              Text(
                partner.name,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (partner.address != null && partner.address!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(partner.address!, style: textTheme.bodyMedium),
                ),

              const SizedBox(height: 12),

              // Prezzi
              Row(
                children: [
                  if (price2h.isNotEmpty)
                    Text(
                      price2h,
                      style: textTheme.titleMedium?.copyWith(color: cs.primary),
                    ),
                  if (price2h.isNotEmpty && pricePerDay.isNotEmpty)
                    const SizedBox(width: 16),
                  if (pricePerDay.isNotEmpty)
                    Text(pricePerDay, style: textTheme.titleMedium),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Descrizione
              Text('Descrizione', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                (partner.description?.trim().isNotEmpty ?? false)
                    ? partner.description!.trim()
                    : 'Nessuna descrizione disponibile.',
                style: textTheme.bodyMedium,
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Orari di apertura
              Text('Orari di apertura', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              _buildOpeningHours(theme),

              const SizedBox(height: 16),
              const Divider(),

              // Regole
              Text('Regole deposito', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                (partner.rules?.trim().isNotEmpty ?? false)
                    ? partner.rules!.trim()
                    : 'Nessuna regola specificata. Evita comunque oggetti di valore e materiali pericolosi.',
                style: textTheme.bodyMedium,
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Capacità e disponibilità
              Text('Capacità e disponibilità', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final capS = partner.capacityS;
                  final capM = partner.capacityM;
                  final capL = partner.capacityL;

                  final totalFromSizes = capS + capM + capL;
                  final effectiveTotal =
                      totalFromSizes > 0 ? totalFromSizes : partner.capacity;

                  final availability = _availability;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Numero massimo di bagagli: $effectiveTotal',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      if (totalFromSizes > 0) ...[
                        if (capS > 0)
                          Text('• Small (S): $capS', style: textTheme.bodySmall),
                        if (capM > 0)
                          Text('• Medium (M): $capM',
                              style: textTheme.bodySmall),
                        if (capL > 0)
                          Text('• Large (L): $capL', style: textTheme.bodySmall),
                      ],
                      const SizedBox(height: 8),

                      if (_loadingAvailability) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Calcolo disponibilità in tempo reale...',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.outline),
                            ),
                          ],
                        ),
                      ] else if (_availabilityError != null) ...[
                        Text(
                          _availabilityError!,
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.error),
                        ),
                      ] else if (availability != null) ...[
                        Text(
                          'Disponibilità attuale: ${availability.availableTotal} su ${availability.capacityTotal} posti.',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (availability.capacityS > 0 ||
                            availability.capacityM > 0 ||
                            availability.capacityL > 0) ...[
                          if (availability.capacityS > 0)
                            Text(
                              '• Small (S): ${availability.availableS}/${availability.capacityS} disponibili',
                              style: textTheme.bodySmall,
                            ),
                          if (availability.capacityM > 0)
                            Text(
                              '• Medium (M): ${availability.availableM}/${availability.capacityM} disponibili',
                              style: textTheme.bodySmall,
                            ),
                          if (availability.capacityL > 0)
                            Text(
                              '• Large (L): ${availability.availableL}/${availability.capacityL} disponibili',
                              style: textTheme.bodySmall,
                            ),
                        ],
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Contatti
              Text('Contatti', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              if (partner.phone != null && partner.phone!.trim().isNotEmpty)
                Text('Telefono: ${partner.phone}', style: textTheme.bodyMedium)
              else
                Text('Telefono non disponibile.', style: textTheme.bodyMedium),
              if (partner.address != null && partner.address!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Indirizzo: ${partner.address}',
                    style: textTheme.bodyMedium,
                  ),
                ),

              const SizedBox(height: 16),
              const Divider(),

              // Mappa
              Text('Posizione', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildMapPreview(),

              const SizedBox(height: 80), // spazio per il bottone in basso
            ],
          ),
        ),
      ),

      // Bottone "Prenota ora" fisso in basso
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BookingFlowScreen(partner: partner),
                  ),
                );
              },
              child: const Text('Prenota ora'),
            ),
          ),
        ),
      ),
    );
  }
}
