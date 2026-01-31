import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/schermate/partner/user_view/booking_flow_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

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
      return const Center(child: Text('Posizione non disponibile'));
    }

    final position = LatLng(lat, lng);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: position, zoom: 15),
      markers: {
        Marker(markerId: const MarkerId('partner'), position: position),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      liteModeEnabled: true,
      onMapCreated: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.partner;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // ----- iOS section helpers -----
    Widget iosSection({required List<Widget> children}) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
    }

    Widget thinDivider({double? indent, double? endIndent}) => Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: cs.outlineVariant.withOpacity(0.35),
    );

    Widget sectionHeader({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.70),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      );
    }

    Widget iosTextSection({
      required IconData icon,
      required String title,
      String? subtitle,
      required Widget child,
    }) {
      return iosSection(
        children: [
          sectionHeader(icon: icon, title: title, subtitle: subtitle),
          thinDivider(indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: child,
          ),
        ],
      );
    }

    // ----- DATA -----
    final hasAddress =
        partner.address != null && partner.address!.trim().isNotEmpty;
    final addressText = hasAddress ? partner.address!.trim() : '';

    final hasCoords = partner.lat != null && partner.lng != null;

    // ----- MAPS actions -----
    Future<void> _launchExternal(Uri uri) async {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // niente dialog; se vuoi, puoi mostrare SnackBar qui
      }
    }

    Uri _appleMapsSearchUri(String q, {double? lat, double? lng}) {
      // Apple Maps: q=... oppure ll=lat,lng
      final params = <String, String>{'q': q};
      if (lat != null && lng != null) params['ll'] = '$lat,$lng';
      return Uri.parse(
        'http://maps.apple.com/?${Uri(queryParameters: params).query}',
      );
    }

    Uri _appleMapsDirectionsUri(String dest, {double? lat, double? lng}) {
      final params = <String, String>{'daddr': dest};
      if (lat != null && lng != null) params['daddr'] = '$lat,$lng';
      return Uri.parse(
        'http://maps.apple.com/?${Uri(queryParameters: params).query}',
      );
    }

    Uri _googleMapsSearchUri(String q, {double? lat, double? lng}) {
      final query = (lat != null && lng != null) ? '$lat,$lng' : q;
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      });
    }

    Uri _googleMapsDirectionsUri(String dest, {double? lat, double? lng}) {
      final destination = (lat != null && lng != null) ? '$lat,$lng' : dest;
      return Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': destination,
      });
    }

    Future<void> openInMaps() async {
      if (!hasAddress && !hasCoords) return;

      final lat = partner.lat;
      final lng = partner.lng;

      final isApple =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      final uri = isApple
          ? _appleMapsSearchUri(
              hasAddress ? addressText : 'BagDrop partner',
              lat: lat,
              lng: lng,
            )
          : _googleMapsSearchUri(
              hasAddress ? addressText : 'BagDrop partner',
              lat: lat,
              lng: lng,
            );

      await _launchExternal(uri);
    }

    Future<void> openDirections() async {
      if (!hasAddress && !hasCoords) return;

      final lat = partner.lat;
      final lng = partner.lng;

      final isApple =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      final uri = isApple
          ? _appleMapsDirectionsUri(
              hasAddress ? addressText : 'BagDrop partner',
              lat: lat,
              lng: lng,
            )
          : _googleMapsDirectionsUri(
              hasAddress ? addressText : 'BagDrop partner',
              lat: lat,
              lng: lng,
            );

      await _launchExternal(uri);
    }

    void copyAddress() {
      if (!hasAddress) return;
      Clipboard.setData(ClipboardData(text: addressText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Indirizzo copiato'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // CTA contrast
    final ctaTextColor =
        ThemeData.estimateBrightnessForColor(cs.primary) == Brightness.dark
        ? Colors.white
        : Colors.black;

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

              // HEADER partner (iOS section)
              iosSection(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            partner.name,
                            style: tt.headlineSmall?.copyWith(
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
                            border: Border.all(
                              color: cs.primary.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            'BagDrop partner',
                            style: tt.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasAddress) ...[
                    thinDivider(),
                    InkWell(
                      onTap: openInMaps,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: cs.onSurface.withOpacity(0.70),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                addressText,
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Copia indirizzo',
                              onPressed: copyAddress,
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(40, 40),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // DESCRIZIONE (ora uguale a Orari/Posizione)
              iosTextSection(
                icon: Icons.info_outline,
                title: 'Descrizione',
                child: Text(
                  (partner.description?.trim().isNotEmpty ?? false)
                      ? partner.description!.trim()
                      : 'Nessuna descrizione disponibile.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.88),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ORARI
              _OpeningHoursDropdown(hoursContent: _buildOpeningHours(theme)),

              const SizedBox(height: 12),

              // REGOLE
              iosTextSection(
                icon: Icons.rule_folder_outlined,
                title: 'Regole deposito',
                child: Text(
                  (partner.rules?.trim().isNotEmpty ?? false)
                      ? partner.rules!.trim()
                      : 'Nessuna regola specificata. Evita comunque oggetti di valore e materiali pericolosi.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.88),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // CONTATTI
              iosTextSection(
                icon: Icons.call_outlined,
                title: 'Contatti',
                child:
                    (partner.phone != null && partner.phone!.trim().isNotEmpty)
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              partner.phone!.trim(),
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              // TODO: launchUrl(Uri.parse('tel:${partner.phone!.trim()}'));
                            },
                            icon: const Icon(Icons.phone_outlined),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: const Size(44, 44),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Telefono non disponibile.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.75),
                        ),
                      ),
              ),

              const SizedBox(height: 12),

              // POSIZIONE (no più tagliata, bottoni full-width)
              iosSection(
                children: [
                  sectionHeader(
                    icon: Icons.map_outlined,
                    title: 'Posizione',
                    subtitle: (hasAddress || hasCoords)
                        ? 'Tocca la mappa o usa i pulsanti'
                        : 'Posizione non disponibile',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (hasAddress || hasCoords) ? openInMaps : null,
                        borderRadius: BorderRadius.circular(14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 180,
                            child: hasCoords
                                ? _buildMapPreview()
                                : Container(
                                    alignment: Alignment.center,
                                    color: cs.surface,
                                    child: Text(
                                      'Posizione non disponibile',
                                      style: tt.bodyMedium?.copyWith(
                                        color: cs.onSurface.withOpacity(0.70),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  thinDivider(indent: 14, endIndent: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: (hasAddress || hasCoords)
                                ? openInMaps
                                : null,
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Apri in Maps'),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: (hasAddress || hasCoords)
                                ? openDirections
                                : null,
                            icon: const Icon(
                              Icons.directions_rounded,
                              size: 18,
                            ),
                            label: const Text('Indicazioni'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: BorderSide(
                                color: cs.outlineVariant.withOpacity(0.45),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
            height: 52,
            child: ElevatedButton(
              onPressed: partner.acceptingBookings
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingFlowScreen(partner: partner),
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: cs.primary, // viola tema
                foregroundColor: Colors.white, // testo sempre bianco
                textStyle: tt.titleSmall?.copyWith(
                  // font coerente ma senza forzare colore nel Text
                  fontWeight: FontWeight.w900,
                ),
                disabledBackgroundColor: cs.surfaceVariant.withOpacity(0.35),
                disabledForegroundColor: cs.onSurface.withOpacity(0.55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              // 👇 niente style qui, così non override il colore
              child: Text(
                partner.acceptingBookings
                    ? 'Prenota ora'
                    : 'Prenotazioni sospese',
              ),
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

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            splashColor: cs.primary.withOpacity(0.06),
            highlightColor: cs.primary.withOpacity(0.04),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
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
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              'Tocca per vedere i dettagli',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
              ),
            ),
            trailing: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: cs.onSurfaceVariant,
            ),
            children: [
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withOpacity(0.35),
              ),
              const SizedBox(height: 10),
              hoursContent,
            ],
          ),
        ),
      ),
    );
  }
}

/// Titolo “BagDrop” in AppBar con brand:
/// - “Bag” bianco fisso
/// - “Drop” giallo brand
class _LogoTitle extends StatelessWidget {
  const _LogoTitle({this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'BagDrop',
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Bag',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                color: Colors.white,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: 'Drop',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                color: AppTheme.brandYellow,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
