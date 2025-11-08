import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart'; // per .sorted
import '../../venues/models/venue.dart';
import '../../bookings/screens/booking_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum SortBy { distance, price }

class _MapScreenState extends State<MapScreen> {
  LatLng _center = const LatLng(45.4642, 9.19); // Milano (fallback)
  final Distance _distance = const Distance();

  // UI state
  double _radiusKm = 2; // filtro raggio
  SortBy _sortBy = SortBy.distance;
  int? _selectedIndex; // per evidenziare venue selezionata

  // Dati demo (in produzione arriveranno dal backend)
  final List<Venue> _venues = [
    Venue(
      id: '1',
      name: 'Teatro alla Scala',
      address: 'Via Roma 1',
      lat: 45.465,
      lng: 9.190,
      minPrice: 5,
      distanceM: 0,
    ),
    Venue(
      id: '2',
      name: 'Libreria Duomo',
      address: 'Piazza Duomo',
      lat: 45.463,
      lng: 9.192,
      minPrice: 6,
      distanceM: 0,
    ),
    Venue(
      id: '3',
      name: 'Tabacchi Vittoria',
      address: 'Corso Vittorio',
      lat: 45.466,
      lng: 9.188,
      minPrice: 5,
      distanceM: 0,
    ),
    Venue(
      id: '4',
      name: 'Caffè Scala',
      address: 'Via Manzoni 12',
      lat: 45.471,
      lng: 9.192,
      minPrice: 7,
      distanceM: 0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _recomputeDistances();
  }

  // Calcola distanza dal centro per ogni venue
  void _recomputeDistances() {
    for (var i = 0; i < _venues.length; i++) {
      final v = _venues[i];
      final m = _distance.distance(LatLng(v.lat, v.lng), _center); // metri
      _venues[i] = Venue(
        id: v.id,
        name: v.name,
        address: v.address,
        lat: v.lat,
        lng: v.lng,
        minPrice: v.minPrice,
        distanceM: m,
      );
    }
    setState(() {});
  }

  // Applica filtro raggio + ordinamento
  List<Venue> get _visibleVenues {
    final filtered = _venues.where((v) => (v.distanceM / 1000.0) <= _radiusKm);
    switch (_sortBy) {
      case SortBy.distance:
        return filtered.sorted((a, b) => a.distanceM.compareTo(b.distanceM));
      case SortBy.price:
        return filtered.sorted((a, b) => a.minPrice.compareTo(b.minPrice));
    }
  }

  // Centro mappa su me (demo: sposta un po’ senza permessi)
  void _fakeLocateMe() {
    _center = LatLng(_center.latitude + 0.003, _center.longitude + 0.003);
    _recomputeDistances();
  }

  @override
  Widget build(BuildContext context) {
    final venues = _visibleVenues;

    final markers = <Marker>[
      // mio puntatore
      Marker(
        width: 40,
        height: 40,
        point: _center,
        child: const Icon(Icons.my_location, size: 28),
      ),
      // marker venue visibili
      ...venues.asMap().entries.map((e) {
        final i = e.key;
        final v = e.value;
        final selected = _selectedIndex == i;
        return Marker(
          width: 44,
          height: 44,
          point: LatLng(v.lat, v.lng),
          child: GestureDetector(
            onTap: () => setState(() => _selectedIndex = i),
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.location_on,
                  size: selected ? 40 : 32,
                  color: selected ? Colors.red : null,
                ),
                if (selected)
                  Positioned(
                    top: -22,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '€${v.minPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Flavio Della Penna è FROCIO, TANTO')),
      body: Stack(
        children: [
          // MAPPA
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider:
                      CancellableNetworkTileProvider(), // consigliato su web
                  userAgentPackageName: 'com.example.bagdrop',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),

          // CONTROLLI (in alto) - con chip
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                elevation: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune, size: 18),
                          const SizedBox(width: 8),
                          const Text('Filtri rapidi'),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Centrati (demo)',
                            onPressed: _fakeLocateMe,
                            icon: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          InputChip(
                            label: Text(
                                'Raggio: ${_radiusKm.toStringAsFixed(1)} km'),
                            avatar: const Icon(Icons.radar, size: 18),
                            onPressed: () async {
                              final v =
                                  await showModalBottomSheet<double>(
                                context: context,
                                builder: (_) =>
                                    _RadiusSheet(initial: _radiusKm),
                              );
                              if (v != null) setState(() => _radiusKm = v);
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Distanza'),
                            selected: _sortBy == SortBy.distance,
                            onSelected: (_) =>
                                setState(() => _sortBy = SortBy.distance),
                          ),
                          ChoiceChip(
                            label: const Text('Prezzo'),
                            selected: _sortBy == SortBy.price,
                            onSelected: (_) =>
                                setState(() => _sortBy = SortBy.price),
                          ),
                          Chip(
                            avatar: const Icon(
                              Icons.store_mall_directory,
                              size: 18,
                            ),
                            label:
                                Text('${_visibleVenues.length} attività'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // LISTA VENUE (in basso)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Card(
                  elevation: 8,
                  child: SizedBox(
                    height: 240,
                    child: Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.store_mall_directory),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Attività entro ${_radiusKm.toStringAsFixed(1)} km — da €5/giorno',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: venues.isEmpty
                              ? const Center(
                                  child: Text(
                                      'Nessuna attività nel raggio scelto'),
                                )
                              : ListView.builder(
                                  itemCount: venues.length,
                                  itemBuilder: (_, i) {
                                    final v = venues[i];
                                    final isSel = _selectedIndex == i;

                                    return InkWell(
                                      onTap: () =>
                                          setState(() => _selectedIndex = i),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 200),
                                        curve: Curves.easeOut,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSel
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                                  .withOpacity(0.4)
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSel
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .secondary
                                                : Theme.of(context)
                                                    .dividerColor
                                                    .withOpacity(0.2),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                  Icons.storefront,
                                                  size: 24),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(v.name,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                          )),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    v.address,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      Chip(
                                                        avatar: const Icon(
                                                            Icons.route,
                                                            size: 18),
                                                        label: Text(
                                                            '${(v.distanceM / 1000).toStringAsFixed(2)} km'),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                      Chip(
                                                        avatar: const Icon(
                                                            Icons.euro,
                                                            size: 18),
                                                        label: Text(
                                                            'da €${v.minPrice.toStringAsFixed(0)}/gg'),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton(
                                              onPressed: () =>
                                                  _showVenueBottomSheet(
                                                      context, v),
                                              child: const Text('Dettagli'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVenueBottomSheet(BuildContext context, Venue v) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.store, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    )),
                            const SizedBox(height: 4),
                            Text(v.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.route, size: 18),
                        label: Text(
                            '${(v.distanceM / 1000).toStringAsFixed(2)} km'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.euro, size: 18),
                        label: Text(
                            'da €${v.minPrice.toStringAsFixed(0)}/giorno'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ritiro in giornata incluso. Per i giorni multipli si applica la tariffa giornaliera.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.backpack),
                      label: const Text('Prenota ora'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => BookingScreen(venue: v)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet per scegliere il raggio in km
class _RadiusSheet extends StatefulWidget {
  final double initial;
  const _RadiusSheet({required this.initial});

  @override
  State<_RadiusSheet> createState() => _RadiusSheetState();
}

class _RadiusSheetState extends State<_RadiusSheet> {
  late double value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Raggio di ricerca',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Slider(
            value: value,
            min: 0.5,
            max: 5,
            divisions: 9,
            label: '${value.toStringAsFixed(1)} km',
            onChanged: (v) => setState(() => value = v),
          ),
          Row(
            children: [
              Text('${value.toStringAsFixed(1)} km'),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annulla')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop<double>(context, value),
                child: const Text('Applica'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
