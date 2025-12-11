import 'package:flutter/material.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';

class PartnerBookingDetailScreen extends StatelessWidget {
  final PartnerBooking booking;

  const PartnerBookingDetailScreen({super.key, required this.booking});

  String _formatDateTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${hh}:${min}';
  }

  String _formatDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    return '$dd/$mm/$yyyy';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final totalBags =
        (booking.bagsS ?? 0) + (booking.bagsM ?? 0) + (booking.bagsL ?? 0);

    // Drop-off (consegna) – usiamo la proprietà già esistente nel modello
    final dropoff = booking.plannedDropoffLocal;
    final dropoffStr = _formatDateTime(dropoff);

    // Se nel modello hai anche plannedPickupLocal, puoi usarlo qui.
    // Per ora gestiamo in modo difensivo.
    DateTime? pickup;
    String pickupStr = 'Non disponibile';
    try {
      // Se hai aggiunto booking.plannedPickupLocal nel modello,
      // puoi decommentare questa riga:
      // pickup = booking.plannedPickupLocal;
      if (pickup != null) {
        pickupStr = _formatDateTime(pickup);
      }
    } catch (_) {
      // Ignoriamo se la proprietà non esiste ancora
    }

    final status = (booking.status ?? 'confirmed').toLowerCase();
    Color chipBg;
    String statusLabel;
    switch (status) {
      case 'cancelled':
      case 'canceled':
        chipBg = Colors.red.withOpacity(0.1);
        statusLabel = 'Annullata';
        break;
      case 'pending':
        chipBg = Colors.orange.withOpacity(0.1);
        statusLabel = 'In attesa';
        break;
      case 'completed':
        chipBg = Colors.blue.withOpacity(0.1);
        statusLabel = 'Completata';
        break;
      default:
        chipBg = Colors.green.withOpacity(0.1);
        statusLabel = 'Confermata';
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio prenotazione')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stato
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Contatto
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contatto',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${booking.firstName ?? ''} ${booking.lastName ?? ''}'
                        .trim(),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if ((booking.phone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(booking.phone!, style: tt.bodySmall),
                  ],
                  if ((booking.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(booking.email!, style: tt.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Orari
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Data e orari',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Consegna prevista:',
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(dropoffStr, style: tt.bodyMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Ritiro previsto:',
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(pickupStr, style: tt.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bagagli
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bagagli',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Totale: $totalBags'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if ((booking.bagsS ?? 0) > 0)
                        Chip(
                          label: Text('S × ${booking.bagsS}'),
                          backgroundColor: cs.primary.withOpacity(0.08),
                        ),
                      if ((booking.bagsM ?? 0) > 0)
                        Chip(
                          label: Text('M × ${booking.bagsM}'),
                          backgroundColor: cs.primary.withOpacity(0.08),
                        ),
                      if ((booking.bagsL ?? 0) > 0)
                        Chip(
                          label: Text('L × ${booking.bagsL}'),
                          backgroundColor: cs.primary.withOpacity(0.08),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Note
          if ((booking.notes ?? '').trim().isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Note cliente',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(booking.notes!.trim(), style: tt.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Prezzo totale – calcolato in base a durata + numero bagagli
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  // Ricostruiamo start/end dal booking
                  final start = dropoff; // già calcolato sopra

                  DateTime? end;
                  if (booking.endDate != null && booking.endTime != null) {
                    final endDate = booking.endDate!;
                    final parts = booking.endTime!.split(':');
                    final hh = int.tryParse(parts[0]) ?? 0;
                    final mm = parts.length > 1
                        ? int.tryParse(parts[1]) ?? 0
                        : 0;
                    end = DateTime(
                      endDate.year,
                      endDate.month,
                      endDate.day,
                      hh,
                      mm,
                    );
                  }

                  if (end == null || !end.isAfter(start)) {
                    return const Text(
                      'Durata non disponibile: controlla che data/ora di ritiro siano impostate.',
                      style: TextStyle(fontSize: 12),
                    );
                  }

                  final duration = BagDropPricing.inferDuration(
                    start: start,
                    end: end,
                  );

                  final total = BagDropPricing.totalFor(
                    duration: duration,
                    bagsS: booking.bagsS ?? 0,
                    bagsM: booking.bagsM ?? 0,
                    bagsL: booking.bagsL ?? 0,
                  );

                  String durationLabel;
                  switch (duration) {
                    case BagDropDuration.threeHours:
                      durationLabel = '3 ore';
                      break;
                    case BagDropDuration.oneDay:
                      durationLabel = '1 giorno';
                      break;
                    case BagDropDuration.oneAndHalfDay:
                      durationLabel = '1,5 giorni';
                      break;
                    case BagDropDuration.twoDays:
                      durationLabel = '2 giorni';
                      break;
                    case BagDropDuration.threeDays:
                      durationLabel = '3 giorni';
                      break;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prezzo totale',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        BagDropPricing.formatEuro(total),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Durata tariffaria: $durationLabel',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
