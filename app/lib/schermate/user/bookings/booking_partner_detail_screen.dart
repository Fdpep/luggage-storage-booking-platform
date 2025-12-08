import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';

import 'booking_recap_screen.dart';

class BookingPartnerDetailScreen extends StatefulWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingPartnerDetailScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  @override
  State<BookingPartnerDetailScreen> createState() =>
      _BookingPartnerDetailScreenState();
}

class _BookingPartnerDetailScreenState
    extends State<BookingPartnerDetailScreen> {
  final _photoRepo = const PartnerPhotoRepo();

  List<PartnerPhoto> _photos = [];
  bool _loadingPhotos = true;
  int _currentPhotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
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

  /// Prezzo "3h da X €" dal listino globale (taglia M come riferimento).
  String _shortPrice3h() {
    if (BagDropPricing.m3h <= 0) return '';
    return '3h da ${BagDropPricing.formatEuro(BagDropPricing.m3h)}';
  }

  /// Prezzo "Giorno da X €" dal listino globale (taglia M).
  String _shortPriceDay() {
    if (BagDropPricing.m1d <= 0) return '';
    return 'Giorno da ${BagDropPricing.formatEuro(BagDropPricing.m1d)}';
  }

  Widget _buildPhotoSection(ColorScheme cs) {
    if (_loadingPhotos) {
      return SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    if (_photos.isEmpty) {
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
          liteModeEnabled: true,
          onMapCreated: (_) {},
        ),
      ),
    );
  }

  Widget _buildOpeningHours(ThemeData theme) {
    final opening = widget.partner.openingHours;
    if (opening == null || opening.isEmpty) {
      return const Text('Orari non disponibili');
    }

    // Caso 1: formato compatto "text"
    final text = opening['text'];
    if (text is String && text.trim().isNotEmpty) {
      return Text(text, style: theme.textTheme.bodyMedium);
    }

    // Mappa dayKey -> label in italiano
    const dayLabels = {
      'mon': 'Lunedì',
      'tue': 'Martedì',
      'wed': 'Mercoledì',
      'thu': 'Giovedì',
      'fri': 'Venerdì',
      'sat': 'Sabato',
      'sun': 'Domenica',
    };

    // Ordine dei giorni
    const orderedDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    // Eccezioni (se presenti)
    Map<String, dynamic>? exceptions;
    if (opening['exceptions'] is Map<String, dynamic>) {
      exceptions = Map<String, dynamic>.from(
        opening['exceptions'] as Map<String, dynamic>,
      );
    }

    final closedDates = <String>{};
    final forcedOpenDates = <String>{};

    if (exceptions != null) {
      final rawClosed = exceptions['closed_dates'];
      if (rawClosed is List) {
        closedDates.addAll(
          rawClosed
              .map((e) => e.toString())
              .where((s) => s.length >= 10)
              .map((s) => s.substring(0, 10)),
        );
      }

      final rawForced = exceptions['forced_open_dates'];
      if (rawForced is List) {
        forcedOpenDates.addAll(
          rawForced
              .map((e) => e.toString())
              .where((s) => s.length >= 10)
              .map((s) => s.substring(0, 10)),
        );
      }
    }

    String formatInterval(Map<String, dynamic> interval) {
      final open = interval['open'] as String? ?? '';
      final close = interval['close'] as String? ?? '';
      return '$open - $close';
    }

    Widget buildWeekly() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: orderedDays.map((dayKey) {
          final label = dayLabels[dayKey] ?? dayKey;
          final list = opening[dayKey] as List<dynamic>? ?? const [];

          if (list.isEmpty) {
            return Text('$label: chiuso', style: theme.textTheme.bodyMedium);
          }

          final intervals = list
              .map((e) => (e as Map).cast<String, dynamic>())
              .map(formatInterval)
              .join('  •  ');

          return Text('$label: $intervals', style: theme.textTheme.bodyMedium);
        }).toList(),
      );
    }

    final children = <Widget>[];

    // Orari settimanali
    children.add(buildWeekly());
    children.add(const SizedBox(height: 8));

    // Liste ordinate per le eccezioni
    final closedList = closedDates.toList()..sort();
    final forcedList = forcedOpenDates.toList()..sort();

    // Chiusure straordinarie
    children.add(
      Text(
        'Chiusure straordinarie:',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    children.add(
      Text(
        closedList.isEmpty ? 'No' : closedList.join(', '),
        style: theme.textTheme.bodySmall,
      ),
    );

    children.add(const SizedBox(height: 4));

    // Aperture straordinarie
    children.add(
      Text(
        'Aperture straordinarie:',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    children.add(
      Text(
        forcedList.isEmpty ? 'No' : forcedList.join(', '),
        style: theme.textTheme.bodySmall,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.partner;
    final booking = widget.booking;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    // Prezzi globali BagDrop (non più letti dal partner)
    final price3h = _shortPrice3h();
    final priceDay = _shortPriceDay();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              partner.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Prenotazione del ${booking.createdAt.day.toString().padLeft(2, '0')}/${booking.createdAt.month.toString().padLeft(2, '0')}/${booking.createdAt.year}',
              style: textTheme.bodySmall?.copyWith(
                color: cs.onPrimary.withOpacity(0.85),
              ),
            ),
          ],
        ),
      ),

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
              // Prezzi (da listino globale BagDrop)
              Row(
                children: [
                  if (price3h.isNotEmpty)
                    Text(
                      price3h,
                      style: textTheme.titleMedium?.copyWith(color: cs.primary),
                    ),
                  if (price3h.isNotEmpty && priceDay.isNotEmpty)
                    const SizedBox(width: 16),
                  if (priceDay.isNotEmpty)
                    Text(priceDay, style: textTheme.titleMedium),
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

              const SizedBox(height: 80), // spazio per i bottoni in basso
            ],
          ),
        ),
      ),

      // Bottoni in basso: Recap e QR
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingRecapScreen(
                          booking: booking,
                          partner: partner,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Riepilogo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Placeholder: da implementare con QR code reale
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'QR code in arrivo in uno step successivo.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('QR code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
