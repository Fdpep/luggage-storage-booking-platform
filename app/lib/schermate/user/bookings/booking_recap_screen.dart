import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/schermate/partner/user_view/partner_detail_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookingRecapScreen extends StatefulWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingRecapScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  @override
  State<BookingRecapScreen> createState() => _BookingRecapScreenState();
}

class _BookingRecapScreenState extends State<BookingRecapScreen> {
  bool _loadingPayments = true;
  String? _paymentsError;
  List<_BookingPaymentRow> _payments = const [];

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
          .map(_BookingPaymentRow.fromMap)
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

  int get _totalPaidCents => _payments.fold(0, (sum, p) => sum + p.amountCents);

  int _toCents(double euro) => (euro * 100).round();

  String _euroCents(int cents) {
    final s = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  String _durationLabel(BagDropDuration d) {
    switch (d) {
      case BagDropDuration.threeHours:
        return '3 ore';
      case BagDropDuration.oneDay:
        return '1 giorno';
      case BagDropDuration.oneAndHalfDay:
        return '1,5 giorni';
      case BagDropDuration.twoDays:
        return '2 giorni';
      case BagDropDuration.threeDays:
        return '3 giorni';
    }
  }

  /// Output: dd/MM/yyyy • HH:mm
  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final d = two(local.day);
    final m = two(local.month);
    final y = local.year.toString();
    final hh = two(local.hour);
    final mm = two(local.minute);
    return '$d/$m/$y • $hh:$mm';
  }

    String _formatDateTimeOrDash(DateTime? dt) => dt == null ? '—' : _formatDateTime(dt);


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final booking = widget.booking;
    final partner = widget.partner;

    final totalBags = booking.totalBags;
    final dropoff = booking.plannedDropoffLocal;
    final pickupRequested = booking.requestedPickupLocal;
    final pickupEffective = booking.plannedPickupLocal;

    // ✅ FIX già applicato: interval normalizzato (extraDays incluso)
    BagDropPricingInterval? interval;
    double? plannedTotalEuro;
    String durationLabel = '';
    int extraDays = 0;

    if (pickupRequested.isAfter(dropoff)) {
      interval = BagDropPricing.normalizeBookingInterval(
        start: dropoff,
        userEnd: pickupRequested,
        getCloseForDay: (_) => null,
      );

      extraDays = interval.extraDays;

      plannedTotalEuro = BagDropPricing.totalFor(
        duration: interval.duration,
        extraDays: interval.extraDays,
        bagsS: booking.bagsS,
        bagsM: booking.bagsM,
        bagsL: booking.bagsL,
      );

      durationLabel = _durationLabel(interval.duration);
    }

    String statusText;
    Color statusColor;
    switch (booking.status.toLowerCase()) {
      case 'pending':
        statusText = 'In attesa';
        statusColor = Colors.orange;
        break;
      case 'cancelled_by_partner':
      case 'rejected':
        statusText = 'Rifiutata';
        statusColor = Colors.red;
        break;
      case 'cancelled':
      case 'canceled':
      case 'cancelled_by_user':
        statusText = 'Annullata';
        statusColor = Colors.grey;
        break;
      case 'completed':
        statusText = 'Completata';
        statusColor = Colors.blue;
        break;
      default:
        statusText = 'Confermata';
        statusColor = Colors.green;
    }

    final plannedCents = plannedTotalEuro == null
        ? 0
        : _toCents(plannedTotalEuro!);
    // saldo calcolato ma NON mostrato (come richiesto)
    final _ = plannedCents - _totalPaidCents;

    final bool paymentsOk = !_loadingPayments && _paymentsError == null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Riepilogo prenotazione',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Controlla i dettagli della tua prenotazione prima di recarti in negozio.',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),

          // SECTION: Partner + stato + date
          _iosSection(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                    partner.address!.trim(),
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
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        statusText,
                        style: tt.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _thinDivider(context),

              _rowIconKV(
                context,
                icon: Icons.login,
                k: 'Consegna prevista',
                v: _formatDateTime(dropoff),
              ),
              _thinDivider(context),
              _rowIconKV(
                context,
                icon: Icons.logout,
                k: 'Ritiro scelto',
                v: _formatDateTime(pickupRequested),
              ),
              _thinDivider(context),
              _rowIconKV(
                context,
                icon: Icons.hourglass_bottom,
                k: 'Scadenza fascia',
                v: _formatDateTime(pickupEffective),
              ),
              _thinDivider(context),
              _rowIconKV(
                context,
                icon: Icons.schedule_outlined,
                k: 'Prenotazione creata il',
                v: _formatDateTime(booking.createdAt),
                subtle: true,
              ),

              // ✅ Pulsante centrato + giallo soft
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

          // SECTION: Dati contatto
          _sectionHeader(context, 'Dati di contatto'),
          const SizedBox(height: 8),
          _iosSection(
            context,
            children: [
              _rowKV(
                context,
                'Nome',
                '${booking.firstName} ${booking.lastName}',
              ),
              _thinDivider(context),
              _rowKV(context, 'Email', booking.email),
              if (booking.phone.isNotEmpty) ...[
                _thinDivider(context),
                _rowKV(context, 'Telefono', booking.phone),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // SECTION: Bagagli
          _sectionHeader(context, 'Bagagli'),
          const SizedBox(height: 8),
          _iosSection(
            context,
            children: [
              _rowKV(context, 'Totale bagagli', '$totalBags', boldValue: true),
              _thinDivider(context),
              _rowKV(context, 'Small (S)', '${booking.bagsS}'),
              _thinDivider(context),
              _rowKV(context, 'Medium (M)', '${booking.bagsM}'),
              _thinDivider(context),
              _rowKV(context, 'Large (L)', '${booking.bagsL}'),
            ],
          ),

          const SizedBox(height: 16),

          // SECTION: Pagamenti e importi (stile come lato partner)
          _sectionHeader(context, 'Pagamenti e importi'),
          const SizedBox(height: 8),
          _iosSection(
            context,
            children: [
              // ✅ Mini recap bagagli + importi (coerente con sezione che ti piace)
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
/*
                    // Importi previsti (manteniamo anche questa info)
                    const SizedBox(height: 12),
                    if (plannedTotalEuro == null) ...[
                      Text(
                        'Durata non valida: controlla che data e orario di ritiro siano successivi alla consegna.',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Totale previsto',
                        style: tt.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        BagDropPricing.formatEuro(plannedTotalEuro),
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        extraDays > 0
                            ? 'Durata tariffaria: $durationLabel + $extraDays giorni extra'
                            : 'Durata tariffaria: $durationLabel',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (extraDays > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Extra: +€2 per bagaglio per ogni giorno oltre i 3 giorni.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],  */
                  ],
                ),
              ),
              _thinDivider(context),

              // ✅ Storico pagamenti (base + supplementi)
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
                      final kind = p.kind.toLowerCase();
                      final isBase = kind == 'base';
                      final title = isBase
                          ? 'Pagamento base'
                          : 'Supplemento (ritardo)';

                      final range =
                          (!isBase &&
                              (p.fromCoveredUntil != null ||
                                  p.toCoveredUntil != null))
                          ? 'Estensione: ${_formatDateTimeOrDash(p.fromCoveredUntil)} → ${_formatDateTimeOrDash(p.toCoveredUntil)}'
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
                _thinDivider(context),
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

// -----------------------
// UI helpers (iOS-like)
// -----------------------

Widget _iosSection(BuildContext context, {required List<Widget> children}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
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
}

Widget _sectionHeader(BuildContext context, String title) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      title,
      style: tt.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
        color: cs.onSurface,
      ),
    ),
  );
}

Widget _thinDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 1,
    color: cs.outlineVariant.withOpacity(0.7),
  );
}

Widget _rowKV(
  BuildContext context,
  String k,
  String v, {
  bool boldValue = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          v,
          style: tt.bodyMedium?.copyWith(
            fontWeight: boldValue ? FontWeight.w900 : FontWeight.w700,
            color: cs.onSurface.withOpacity(boldValue ? 1.0 : 0.75),
          ),
        ),
      ],
    ),
  );
}

Widget _rowIconKV(
  BuildContext context, {
  required IconData icon,
  required String k,
  required String v,
  bool subtle = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
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

class _IconLabelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const _IconLabelRow({
    required this.icon,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defaultLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: cs.onSurface.withOpacity(0.85),
    );
    final defaultValueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.9));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle ?? defaultLabelStyle),
              const SizedBox(height: 2),
              Text(value, style: valueStyle ?? defaultValueStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookingPaymentRow {
  final String kind; // 'base' | 'late_fee' (o simili)
  final int amountCents;
  final DateTime paidAt;

  // ✅ opzionali: per mostrare l’estensione coperta dal supplemento
  final DateTime? fromCoveredUntil;
  final DateTime? toCoveredUntil;

  _BookingPaymentRow({
    required this.kind,
    required this.amountCents,
    required this.paidAt,
    this.fromCoveredUntil,
    this.toCoveredUntil,
  });

  factory _BookingPaymentRow.fromMap(Map<String, dynamic> m) {
    int cents(dynamic v) => (v is int) ? v : int.tryParse(v.toString()) ?? 0;

   DateTime? dtN(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // rende ISO: "YYYY-MM-DD HH:mm:ss+00" -> "YYYY-MM-DDTHH:mm:ss+00"
  final iso = s.contains('T') ? s : s.replaceFirst(' ', 'T');

  try {
    return DateTime.parse(iso).toLocal();
  } catch (_) {
    return null;
  }
}


    DateTime dt(dynamic v) => dtN(v) ?? DateTime.now();

    return _BookingPaymentRow(
      kind: (m['kind'] ?? 'base').toString(),
      amountCents: cents(m['amount_cents']),
      paidAt: dt(m['paid_at']),
      // NB: se nel DB i campi hanno nomi diversi, cambia qui le chiavi
      fromCoveredUntil: dtN(m['from_covered_until'] ?? m['fromCoveredUntil']),
      toCoveredUntil: dtN(m['to_covered_until'] ?? m['toCoveredUntil']),
    );
  }
}

