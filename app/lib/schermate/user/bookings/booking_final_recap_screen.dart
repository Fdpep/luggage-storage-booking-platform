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

    final isNoShow = booking.isNoShowCompleted;
    final noShowClosedAt = booking.coveredUntil ?? plannedPickup; // fallback

    final tolerance = const Duration(minutes: 15);
    final isLateCheckout =
        effectivePickup != null &&
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

    int euroToCents(double v) => (v * 100).round();
    final plannedCents = euroToCents(plannedTotal);
    final dueCents = euroToCents(finalTotal);
    final extraCents = (dueCents - plannedCents) > 0
        ? (dueCents - plannedCents)
        : 0;
    final balanceCents = dueCents - _totalPaidCents;

    final extra = (finalTotal - plannedTotal);
    final extraClamped = extra < 0 ? 0.0 : extra;

    // ---- UI helpers locali (restyle iOS-like) ----
    Widget iosSection({required List<Widget> children}) => Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: children),
      ),
    );

    Widget thinDivider() => Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.7),
    );

    Widget sectionHeader(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        t,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );

    Widget rowIconKV({
      required IconData icon,
      required String k,
      required String v,
      bool subtle = false,
    }) {
      final labelColor = subtle
          ? cs.onSurface.withOpacity(0.6)
          : cs.onSurface.withOpacity(0.8);
      final valueColor = subtle
          ? cs.onSurface.withOpacity(0.6)
          : cs.onSurface.withOpacity(0.75);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                k,
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              v,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
    }

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
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Qui trovi orari prenotati vs effettivi e l’importo finale (inclusi eventuali sovrapprezzi).',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),

          //cliente non presentato
          if (isNoShow) ...[
            iosSection(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 20,
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cliente non si è presentato',
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'La prenotazione è stata chiusa automaticamente perché non è stato effettuato alcun check-in entro la fascia coperta.',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.72),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Chiusura: ${_formatDateTime(noShowClosedAt)}',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Partner section
          sectionHeader('Locale'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (partner.address != null &&
                        partner.address!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              partner.address!,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              thinDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PartnerDetailScreen(partner: partner),
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
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Orari prenotati
          sectionHeader('Orari prenotati'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              rowIconKV(
                icon: Icons.login,
                k: 'Check-in previsto',
                v: _formatDateTime(plannedDropoff),
              ),
              thinDivider(),
              rowIconKV(
                icon: Icons.logout,
                k: 'Ritiro scelto',
                v: _formatDateTime(requestedPickup),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Orari effettivi
          sectionHeader('Orari effettivi'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              rowIconKV(
                icon: Icons.login,
                k: 'Check-in effettivo',
                v: _formatDateTime(effectiveDropoff),
              ),
              thinDivider(),
              rowIconKV(
                icon: Icons.logout,
                k: 'Check-out effettivo',
                v: _formatDateTime(effectivePickup),
              ),
              if (isLateCheckout) ...[
                thinDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Check-out oltre la tolleranza di 15 min: applicato sovrapprezzo.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Pagamenti
          sectionHeader('Pagamenti'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bagagli',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${booking.totalBags} (S:${booking.bagsS} M:${booking.bagsM} L:${booking.bagsL})',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              thinDivider(),

              if (_loadingPayments) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 10),
                      Text(
                        'Caricamento storico pagamenti…',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_paymentsError != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Text(
                    'Impossibile caricare pagamenti: $_paymentsError',
                    style: tt.bodySmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else if (_payments.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Text(
                    'Nessun pagamento registrato (in test / mock).',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Column(
                    children: _payments.map((p) {
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
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.28),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: tt.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _euroCents(p.amountCents),
                                    style: tt.bodyMedium?.copyWith(
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
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.75),
                                ),
                              ),
                              if (range != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  range,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.75),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                thinDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Row(
                    children: [
                      Text(
                        'Totale pagato',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _euroCents(_totalPaidCents),
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),
          Text(
            'Nota: lo storico pagamenti mostra base + eventuali supplementi (anche multipli). Il ritardo si calcola dalla “scadenza fascia” + 15 min.',
            style: tt.bodySmall?.copyWith(
              fontSize: 11,
              color: cs.onSurface.withOpacity(0.6),
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
