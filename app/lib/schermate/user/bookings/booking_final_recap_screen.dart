import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/schermate/partner/user_view/partner_detail_screen.dart';

class BookingFinalRecapScreen extends StatelessWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingFinalRecapScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Orari prenotati (planned)
    final plannedDropoff = booking.plannedDropoffAtLocal;
    final plannedPickup = booking.plannedPickupAtLocal;

    // Orari effettivi (effective)
    final effectiveDropoff = booking.effectiveDropoffAtLocal;
    final effectivePickup = booking.effectivePickupAtLocal;

    // Regola tolleranza checkout
    final tolerance = const Duration(minutes: 15);
    final isLateCheckout = effectivePickup != null &&
        effectivePickup.isAfter(plannedPickup.add(tolerance));

    // Prezzi: base (planned) + finale (se late allora calcolo su end effettivo, altrimenti planned)
    final plannedDuration = BagDropPricing.inferDuration(
      start: plannedDropoff,
      end: plannedPickup,
    );

    final priceEnd = (isLateCheckout && effectivePickup != null)
        ? effectivePickup
        : plannedPickup;

    final finalDuration = BagDropPricing.inferDuration(
      start: plannedDropoff,
      end: priceEnd,
    );

    final plannedTotal = BagDropPricing.totalFor(
      duration: plannedDuration,
      bagsS: booking.bagsS,
      bagsM: booking.bagsM,
      bagsL: booking.bagsL,
    );

    final finalTotal = BagDropPricing.totalFor(
      duration: finalDuration,
      bagsS: booking.bagsS,
      bagsM: booking.bagsM,
      bagsL: booking.bagsL,
    );

    final extra = (finalTotal - plannedTotal);
    final extraClamped = extra < 0 ? 0.0 : extra;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const Text('Riepilogo finale'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Riepilogo finale',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Qui trovi orari prenotati vs effettivi e l’importo finale (inclusi eventuali sovrapprezzi).',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),

          // Partner card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partner.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  if (partner.address != null && partner.address!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 16, color: cs.onSurface.withOpacity(0.6)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            partner.address!,
                            style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PartnerDetailScreen(partner: partner),
                          ),
                        );
                      },
                      icon: const Icon(Icons.store_mall_directory_outlined, size: 18),
                      label: const Text('Dettagli locale'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Orari prenotati
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Orari prenotati',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  _IconLabelRow(
                    icon: Icons.login,
                    label: 'Check-in previsto',
                    value: _formatDateTime(plannedDropoff),
                  ),
                  const SizedBox(height: 6),
                  _IconLabelRow(
                    icon: Icons.logout,
                    label: 'Check-out previsto',
                    value: _formatDateTime(plannedPickup),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Orari effettivi
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Orari effettivi',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  _IconLabelRow(
                    icon: Icons.login,
                    label: 'Check-in effettivo',
                    value: _formatDateTime(effectiveDropoff),
                  ),
                  const SizedBox(height: 6),
                  _IconLabelRow(
                    icon: Icons.logout,
                    label: 'Check-out effettivo',
                    value: _formatDateTime(effectivePickup),
                  ),
                  if (isLateCheckout) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Check-out oltre la tolleranza di 15 min: applicato sovrapprezzo.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.75),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Pagamento finale
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pagamento finale',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  _InfoRow('Bagagli', '${booking.totalBags} (S:${booking.bagsS} M:${booking.bagsM} L:${booking.bagsL})'),

                  const SizedBox(height: 8),
                  _InfoRow('Prezzo base (prenotato)', BagDropPricing.formatEuro(plannedTotal)),

                  if (extraClamped > 0.0) ...[
                    const SizedBox(height: 6),
                    _InfoRow('Sovrapprezzo (ritardo)', '+ ${BagDropPricing.formatEuro(extraClamped)}',
                        valueStyle: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.orange.shade800,
                        )),
                  ],

                  const Divider(height: 22),
                  Row(
                    children: [
                      const Text(
                        'Totale pagato',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        BagDropPricing.formatEuro(finalTotal),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Text(
                    'Nota: il totale è calcolato automaticamente in base alle tariffe BagDropPricing e agli orari effettivi (se oltre tolleranza).',
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6)),
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

class _IconLabelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _IconLabelRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoRow(this.label, this.value, {this.valueStyle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: valueStyle ?? const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
