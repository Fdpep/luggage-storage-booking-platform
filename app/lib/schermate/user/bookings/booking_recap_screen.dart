import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/schermate/user/bookings/booking_partner_detail_screen.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';

class BookingRecapScreen extends StatelessWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingRecapScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final totalBags = booking.bagsS + booking.bagsM + booking.bagsL;
    final dropoff = booking.plannedDropoffLocal;
    final pickup = booking.plannedPickupLocal;

    // Calcolo durata + prezzo
    BagDropDuration? duration;
    double? totalPrice;
    String durationLabel = '';

    if (pickup.isAfter(dropoff)) {
      duration = BagDropPricing.inferDuration(start: dropoff, end: pickup);
      totalPrice = BagDropPricing.totalFor(
        duration: duration,
        bagsS: booking.bagsS,
        bagsM: booking.bagsM,
        bagsL: booking.bagsL,
      );

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
        default:
          durationLabel = '';
      }
    }

    String _statusText;
    Color _statusColor;
    switch (booking.status.toLowerCase()) {
      case 'pending':
        _statusText = 'In attesa';
        _statusColor = Colors.orange;
        break;
      case 'cancelled':
      case 'canceled':
        _statusText = 'Annullata';
        _statusColor = Colors.red;
        break;
      case 'completed':
        _statusText = 'Completata';
        _statusColor = Colors.blue;
        break;
      default:
        _statusText = 'Confermata';
        _statusColor = Colors.green;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Riepilogo prenotazione')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Riepilogo prenotazione',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Controlla i dettagli della tua prenotazione prima di recarti in negozio.',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),

          // Card partner + stato + date
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Partner + stato chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partner.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            if (partner.address != null &&
                                partner.address!.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                partner.address!,
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consegna prevista: ${_formatDateTime(dropoff)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ritiro previsto: ${_formatDateTime(pickup)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Prenotazione creata il ${_formatDateTime(booking.createdAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookingPartnerDetailScreen(
                              partner: partner,
                              booking: booking,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 18,
                      ),
                      label: const Text('Dettagli locale'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Dati contatto
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dati di contatto',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow('Nome', '${booking.firstName} ${booking.lastName}'),
                  _InfoRow('Email', booking.email),
                  if (booking.phone.isNotEmpty)
                    _InfoRow('Telefono', booking.phone),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Bagagli
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bagagli',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow('Totale bagagli', '$totalBags'),
                  _InfoRow('Small (S)', '${booking.bagsS}'),
                  _InfoRow('Medium (M)', '${booking.bagsM}'),
                  _InfoRow('Large (L)', '${booking.bagsL}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Prezzo totale
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Prezzo totale',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (totalPrice == null)
                    Text(
                      'Durata non valida: controlla che data e orario di ritiro siano successivi alla consegna.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    )
                  else ...[
                    Text(
                      BagDropPricing.formatEuro(totalPrice),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (durationLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Durata tariffaria: $durationLabel',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Note
          if (booking.notes != null && booking.notes!.trim().isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      booking.notes!,
                      style: TextStyle(color: cs.onSurface.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
