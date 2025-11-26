import 'package:flutter/material.dart';

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
    final totalBags = booking.bagsS + booking.bagsM + booking.bagsL;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riepilogo prenotazione'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Partner
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                  const SizedBox(height: 8),
                  Text(
                    'Prenotazione creata il ${_formatDateTime(booking.createdAt)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Dati contatto
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dati di contatto',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bagagli',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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

          // Note
          if (booking.notes != null &&
              booking.notes!.trim().isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.9),
                      ),
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
