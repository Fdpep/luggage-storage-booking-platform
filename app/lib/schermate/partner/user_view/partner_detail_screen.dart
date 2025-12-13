import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/schermate/partner/user_view/booking_flow_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';

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
    //_loadAvailability();  non serve la capacita totale
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

  // Giorni in ordine e label in italiano
  static const _dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _dayLabels = {
    'mon': 'Lunedì',
    'tue': 'Martedì',
    'wed': 'Mercoledì',
    'thu': 'Giovedì',
    'fri': 'Venerdì',
    'sat': 'Sabato',
    'sun': 'Domenica',
  };

  /// Normalizza opening_hours in formato settimanale:
  /// { "mon": [ {open:"HH:MM", close:"HH:MM"}, ... ], ... }
  Map<String, List<Map<String, dynamic>>> _normalizeOpeningWeekly(
    Map<String, dynamic>? raw,
  ) {
    final result = <String, List<Map<String, dynamic>>>{
      for (final d in _dayOrder) d: <Map<String, dynamic>>[],
    };

    // Nessun dato -> fallback 08:00-20:00 tutti i giorni
    if (raw == null) {
      final def = {'open': '08:00', 'close': '20:00'};
      for (final d in _dayOrder) {
        result[d] = [Map<String, dynamic>.from(def)];
      }
      return result;
    }

    final type = raw['type'] as String?;

    // Già weekly_v1
    if (type == 'weekly_v1') {
      for (final d in _dayOrder) {
        final list = raw[d] as List<dynamic>? ?? [];
        result[d] = list
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
      }
      return result;
    }

    // Vecchio formato daily_with_break
    if (type == 'daily_with_break') {
      final String? o1 = raw['open_1'] as String?;
      final String? c1 = raw['close_1'] as String?;
      final String? o2 = raw['open_2'] as String?;
      final String? c2 = raw['close_2'] as String?;

      final intervals = <Map<String, dynamic>>[];
      if (o1 != null && c1 != null) {
        intervals.add({'open': o1, 'close': c1});
      }
      if (o2 != null && c2 != null) {
        intervals.add({'open': o2, 'close': c2});
      }

      if (intervals.isEmpty) {
        // tutti chiusi
        return result;
      }

      for (final d in _dayOrder) {
        result[d] = intervals.map((i) => Map<String, dynamic>.from(i)).toList();
      }
      return result;
    }

    // Caso legacy: trattiamo raw come weekly senza "type"
    for (final d in _dayOrder) {
      final list = raw[d] as List<dynamic>? ?? [];
      result[d] = list
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    }

    return result;
  }

  List<DateTime> _parseDateList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => DateTime.tryParse(e as String? ?? ''))
          .whereType<DateTime>()
          .toList()
        ..sort();
    }
    return [];
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Widget _buildOpeningHours(ThemeData theme) {
    final opening = widget.partner.openingHours;
    if (opening == null || opening.isEmpty) {
      return const Text('Orari non disponibili');
    }

    final weekly = _normalizeOpeningWeekly(opening);
    final exceptions = opening['exceptions'] as Map<String, dynamic>?;

    final closedDates = _parseDateList(exceptions?['closed_dates']);
    final forcedOpenDates = _parseDateList(exceptions?['forced_open_dates']);

    final tt = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Giorni da lunedì a domenica
        ..._dayOrder.map((dayKey) {
          final label = _dayLabels[dayKey] ?? dayKey;
          final intervals = weekly[dayKey] ?? const <Map<String, dynamic>>[];

          String value;
          if (intervals.isEmpty) {
            value = 'Chiuso';
          } else {
            value = intervals
                .map((i) {
                  final o = (i['open'] ?? '').toString();
                  final c = (i['close'] ?? '').toString();
                  if (o.isEmpty || c.isEmpty) return '-';
                  return '$o - $c';
                })
                .join('  /  ');
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 95,
                  child: Text(
                    label,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(value, style: tt.bodyMedium)),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 12),

        // Chiusure straordinarie
        Text(
          'Chiusure straordinarie',
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (closedDates.isEmpty)
          Text('No', style: tt.bodyMedium)
        else
          Text(closedDates.map(_formatDate).join(', '), style: tt.bodyMedium),

        const SizedBox(height: 8),

        // Aperture straordinarie
        Text(
          'Aperture straordinarie',
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (forcedOpenDates.isEmpty)
          Text('No', style: tt.bodyMedium)
        else
          Text(
            forcedOpenDates.map(_formatDate).join(', '),
            style: tt.bodyMedium,
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoSection(cs),
              const SizedBox(height: 12),

              // Header “moderno”
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              partner.name,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'BagDrop partner',
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (partner.address != null &&
                          partner.address!.trim().isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: cs.onSurface.withOpacity(0.70),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                partner.address!.trim(),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Descrizione
              _SectionCard(
                icon: Icons.info_outline,
                title: 'Descrizione',
                child: Text(
                  (partner.description?.trim().isNotEmpty ?? false)
                      ? partner.description!.trim()
                      : 'Nessuna descrizione disponibile.',
                  style: textTheme.bodyMedium,
                ),
              ),

              const SizedBox(height: 12),

              // Orari (tendina moderna)
              _OpeningHoursDropdown(hoursContent: _buildOpeningHours(theme)),

              const SizedBox(height: 12),

              // Regole
              _SectionCard(
                icon: Icons.rule_folder_outlined,
                title: 'Regole deposito',
                child: Text(
                  (partner.rules?.trim().isNotEmpty ?? false)
                      ? partner.rules!.trim()
                      : 'Nessuna regola specificata. Evita comunque oggetti di valore e materiali pericolosi.',
                  style: textTheme.bodyMedium,
                ),
              ),

              const SizedBox(height: 12),

              // Capacità (chip moderni)
              _SectionCard(
                icon: Icons.inventory_2_outlined,
                title: 'Capacità e disponibilità',
                child: Builder(
                  builder: (context) {
                    final capS = partner.capacityS;
                    final capM = partner.capacityM;
                    final capL = partner.capacityL;

                    final totalFromSizes = capS + capM + capL;
                    final effectiveTotal = totalFromSizes > 0
                        ? totalFromSizes
                        : partner.capacity;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Riga 1: totale
                        _InfoChip(
                          icon: Icons.luggage_outlined,
                          label: 'Bagagli disponibili: $effectiveTotal',
                        ),

                        // Riga 2: taglie (solo se presenti)
                        if (totalFromSizes > 0) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (capS > 0)
                                _InfoChip(
                                  icon: Icons.circle_outlined,
                                  label: 'S: $capS',
                                ),
                              if (capM > 0)
                                _InfoChip(
                                  icon: Icons.circle_outlined,
                                  label: 'M: $capM',
                                ),
                              if (capL > 0)
                                _InfoChip(
                                  icon: Icons.circle_outlined,
                                  label: 'L: $capL',
                                ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Contatti
              _SectionCard(
                icon: Icons.call_outlined,
                title: 'Contatti',
                child:
                    (partner.phone != null && partner.phone!.trim().isNotEmpty)
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              partner.phone!.trim(),
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          // Se vuoi renderli “cliccabili”, qui agganci url_launcher (tel:, sms:, whatsapp)
                          IconButton(
                            onPressed: () {
                              // TODO: launchUrl(Uri.parse('tel:${partner.phone!.trim()}'));
                            },
                            icon: const Icon(Icons.phone_outlined),
                          ),
                        ],
                      )
                    : Text(
                        'Telefono non disponibile.',
                        style: textTheme.bodyMedium,
                      ),
              ),

              const SizedBox(height: 12),

              // Mappa
              _SectionCard(
                icon: Icons.map_outlined,
                title: 'Posizione',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildMapPreview(),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            height: 50,
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _OpeningHoursDropdown extends StatelessWidget {
  final Widget hoursContent;

  const _OpeningHoursDropdown({required this.hoursContent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.schedule_outlined, size: 20, color: cs.primary),
          ),
          title: Text(
            'Orari di apertura',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Tocca per vedere i dettagli',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
          trailing: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: cs.onSurfaceVariant,
          ),
          children: [hoursContent],
        ),
      ),
    );
  }
}

/// Titolo “BagDrop” in AppBar con brand:
/// - “Bag” chiaro
/// - “Drop” giallo
class _LogoTitle extends StatelessWidget {
  const _LogoTitle();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'Bag',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          TextSpan(text: ' '),
          TextSpan(
            text: 'Drop',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppTheme.brandYellow,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
