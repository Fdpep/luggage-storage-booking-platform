import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/schermate/partner/user_view/partner_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookingPaymentRow {
  final String kind; // 'base' | 'late_fee'
  final int amountCents;
  final DateTime paidAt;
  final DateTime? fromCoveredUntil;
  final DateTime? toCoveredUntil;
  final String? fromDurationKey;
  final String? toDurationKey;

  BookingPaymentRow({
    required this.kind,
    required this.amountCents,
    required this.paidAt,
    this.fromCoveredUntil,
    this.toCoveredUntil,
    this.fromDurationKey,
    this.toDurationKey,
  });

  factory BookingPaymentRow.fromMap(Map<String, dynamic> m) {
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.parse(v.toString()).toLocal();
    int cents(dynamic v) => (v is int) ? v : int.tryParse(v.toString()) ?? 0;

    return BookingPaymentRow(
      kind: (m['kind'] ?? 'late_fee').toString(),
      amountCents: cents(m['amount_cents']),
      paidAt: dt(m['paid_at']) ?? DateTime.now(),
      fromCoveredUntil: dt(m['from_covered_until']),
      toCoveredUntil: dt(m['to_covered_until']),
      fromDurationKey: m['from_duration_key']?.toString(),
      toDurationKey: m['to_duration_key']?.toString(),
    );
  }
}

class BookingFinalRecapScreen extends StatefulWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingFinalRecapScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  @override
  State<BookingFinalRecapScreen> createState() =>
      _BookingFinalRecapScreenState();
}

class _BookingFinalRecapScreenState extends State<BookingFinalRecapScreen> {
  bool _loadingPayments = true;
  String? _paymentsError;
  List<BookingPaymentRow> _payments = const [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _loadingPayments = true;
      _paymentsError = null;
    });

    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('booking_payments')
          .select()
          .eq('booking_id', widget.booking.id)
          .order('paid_at', ascending: true);

      final list = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(BookingPaymentRow.fromMap)
          .toList();

      if (!mounted) return;
      setState(() {
        _payments = list;
        _loadingPayments = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentsError = e.toString();
        _loadingPayments = false;
      });
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _euroCents(int cents) {
    final s = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  int get _totalPaidCents => _payments.fold(0, (sum, p) => sum + p.amountCents);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final booking = widget.booking;
    final partner = widget.partner;

    final plannedDropoff = booking.plannedDropoffAtLocal;
    final plannedPickup = booking
        .plannedPickupAtLocal; // (o covered_until se lo aggiungi al model)
    final effectiveDropoff = booking.effectiveDropoffAtLocal;
    final effectivePickup = booking.effectivePickupAtLocal;
    final requestedPickup = booking.requestedPickupAtLocal;

    final tolerance = const Duration(minutes: 15);
    final isLateCheckout =
        effectivePickup != null &&
        effectivePickup.isAfter(plannedPickup.add(tolerance));

    // NOTA: qui NON calcoliamo più "finalTotal" dal tempo.
    // Il totale trasparente = somma pagamenti (base + supplementi).

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

    int euroToCents(double v) => (v * 100).round();
    final plannedCents = euroToCents(plannedTotal);
    final dueCents = euroToCents(
      finalTotal,
    ); // dovuto per orari effettivi (se late)
    final extraCents = (dueCents - plannedCents) > 0
        ? (dueCents - plannedCents)
        : 0;
    final balanceCents = dueCents - _totalPaidCents; // >0 ancora da pagare

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1.5,
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            partner.address!,
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.7),
                            ),
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
                            builder: (_) =>
                                PartnerDetailScreen(partner: partner),
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

          // Orari prenotati
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                    label: 'Ritiro scelto',
                    value: _formatDateTime(requestedPickup),
                  ),
                  const SizedBox(height: 6),
                  _IconLabelRow(
                    icon: Icons.hourglass_bottom,
                    label: 'Scadenza fascia',
                    value: _formatDateTime(plannedPickup),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Orari effettivi
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.orange.shade700,
                        ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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

                  _InfoRow(
                    'Bagagli',
                    '${booking.totalBags} (S:${booking.bagsS} M:${booking.bagsM} L:${booking.bagsL})',
                  ),

                  const SizedBox(height: 8),
                  _InfoRow('Prezzo base (prenotato)', _euroCents(plannedCents)),

                  if (extraCents > 0) ...[
                    const SizedBox(height: 6),
                    _InfoRow(
                      'Sovrapprezzo (ritardo)',
                      '+ ${_euroCents(extraCents)}',
                      valueStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],

                  const Divider(height: 22),
                  Row(
                    children: [
                      const Text(
                        'Totale dovuto',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _euroCents(dueCents),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  _InfoRow(
                    'Totale pagato (registrato)',
                    _euroCents(_totalPaidCents),
                  ),
                  _InfoRow(
                    balanceCents > 0 ? 'Da pagare' : 'Saldo',
                    _euroCents(balanceCents.abs()),
                    valueStyle: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: balanceCents > 0
                          ? Colors.orange.shade800
                          : cs.primary,
                    ),
                  ),

                  const SizedBox(height: 10),
                  Text(
                    'Nota: il totale è calcolato automaticamente in base alle tariffe BagDropPricing e agli orari effettivi (se oltre tolleranza).',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          //////ALTRO STILE DI CARD ????????????????????????????????????????????
          ///
          ///
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pagamenti',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  _InfoRow(
                    'Bagagli',
                    '${booking.totalBags} (S:${booking.bagsS} M:${booking.bagsM} L:${booking.bagsL})',
                  ),

                  const SizedBox(height: 10),

                  if (_loadingPayments) ...[
                    const LinearProgressIndicator(minHeight: 4),
                    const SizedBox(height: 10),
                    Text(
                      'Caricamento storico pagamenti…',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ] else if (_paymentsError != null) ...[
                    Text(
                      'Impossibile caricare pagamenti: $_paymentsError',
                      style: TextStyle(fontSize: 12, color: cs.error),
                    ),
                  ] else if (_payments.isEmpty) ...[
                    Text(
                      'Nessun pagamento registrato (in test / mock).',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ] else ...[
                    ..._payments.map((p) {
                      final isBase = p.kind == 'base';
                      final title = isBase
                          ? 'Pagamento base'
                          : 'Supplemento (ritardo)';

                      final range =
                          (!isBase &&
                              (p.fromCoveredUntil != null ||
                                  p.toCoveredUntil != null))
                          ? 'Estensione: ${_formatDateTime(p.fromCoveredUntil)} → ${_formatDateTime(p.toCoveredUntil)}'
                          : null;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _euroCents(p.amountCents),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: isBase
                                          ? cs.primary
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pagato il ${_formatDateTime(p.paidAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.75),
                                ),
                              ),
                              if (range != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  range,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withOpacity(0.75),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    const Divider(height: 22),
                    Row(
                      children: [
                        const Text(
                          'Totale pagato',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _euroCents(_totalPaidCents),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),
                  Text(
                    'Nota: lo storico pagamenti mostra base + eventuali supplementi (anche multipli). Il ritardo si calcola dalla “scadenza fascia” + 15 min.',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.6),
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
          style:
              valueStyle ??
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
