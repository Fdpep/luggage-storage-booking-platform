import 'package:flutter/material.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/theme/app_theme.dart';

/// ---- PAYMENTS (stesso modello lato utente, portato anche lato partner) ----
class BookingPaymentRow {
  final String kind; // 'base' | 'late_fee' | altro
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

class PartnerBookingDetailScreen extends StatefulWidget {
  final PartnerBooking booking;

  const PartnerBookingDetailScreen({super.key, required this.booking});

  @override
  State<PartnerBookingDetailScreen> createState() =>
      _PartnerBookingDetailScreenState();
}

class _PartnerBookingDetailScreenState
    extends State<PartnerBookingDetailScreen> {
  PartnerBooking get booking => widget.booking;
  bool _rejecting = false;

  // ---- NEW: pagamenti ----
  bool _loadingPayments = true;
  String? _paymentsError;
  List<BookingPaymentRow> _payments = const [];

  int get _totalPaidCents => _payments.fold(0, (sum, p) => sum + p.amountCents);
  int get _supplementsPaidCents => _payments
      .where((p) => p.kind != 'base')
      .fold(0, (sum, p) => sum + p.amountCents);

  DateTime? get _coveredUntil {
    // se hai to_covered_until nei pagamenti, prendo l’ultimo disponibile (massimo)
    DateTime? best;
    for (final p in _payments) {
      final t = p.toCoveredUntil;
      if (t == null) continue;
      if (best == null || t.isAfter(best)) best = t;
    }
    return best;
  }

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
          .eq('booking_id', booking.id)
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

  String _formatDateTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm  $hh:$min';
  }

  String _formatDateTimeFull(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _euroCents(int cents) {
    final s = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  bool get _canReject {
    final kind = _StatusUI.from(booking.uiStatus).kind;
    // ✅ rifiutabile SOLO prima del check-in
    return kind == _StatusKind.pending || kind == _StatusKind.confirmed;
  }

  Future<String?> _askRejectReason(BuildContext context) {
    const presets = [
      'Bagaglio non conforme (taglia diversa)',
      'Cliente non si è presentato',
      'Capienza insufficiente',
      'Orario non rispettato',
      'Altro',
    ];

    final ctrl = TextEditingController();
    final focus = FocusNode();
    String? selected;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setM) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;

            final canConfirm = ctrl.text.trim().isNotEmpty; // ✅ OBBLIGATORIO

            void selectPreset(String p) {
              setM(() {
                selected = (selected == p) ? null : p;
                if (selected == null) return;

                if (selected == 'Altro') {
                  ctrl.text = '';
                } else {
                  ctrl.text = selected!;
                }
                ctrl.selection = TextSelection.collapsed(
                  offset: ctrl.text.length,
                );
              });
              FocusScope.of(ctx).requestFocus(focus);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rifiuta prenotazione',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seleziona una motivazione o scrivila. Il campo è obbligatorio.',
                    style: TextStyle(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final isSel = selected == p;
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSel,
                        onSelected: (_) => selectPreset(p),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    focusNode: focus,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Motivazione *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) => setM(() {}),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Annulla'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: !canConfirm
                              ? null
                              : () => Navigator.pop(ctx, ctrl.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Conferma rifiuto'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withOpacity(0.18)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Il rifiuto è consentito solo prima del check-in. '
                            'Se l’utente ha già pagato, verrà avviato il rimborso automatico.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _rejectBooking() async {
    if (!_canReject || _rejecting) return;

    final reason = await _askRejectReason(context);
    if (!mounted || reason == null || reason.trim().isEmpty) return;

    setState(() => _rejecting = true);

    try {
      final repo = PartnerBookingRepo(Supabase.instance.client);
      await repo.rejectBooking(bookingId: booking.id, reason: reason.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prenotazione rifiutata')));
      Navigator.pop(context, true); // ✅ segnala alla lista di refreshare
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  _StatusUI _statusUi(String status) => _StatusUI.from(status);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final totalBags = (booking.bagsS) + (booking.bagsM) + (booking.bagsL);

    final plannedDropoff = booking.plannedDropoffAtLocal;
    final plannedPickup = booking.plannedPickupAtLocal;

    final effectiveDropoff = booking.effectiveDropoffAtLocal;
    final effectivePickup = booking.effectivePickupAtLocal;

    final dropoffStr = _formatDateTime(plannedDropoff);
    final pickupStr = _formatDateTime(plannedPickup);

    final statusUi = _StatusUI.from(booking.uiStatus);

    // ---- NEW: logica riepilogo (in corso vs finale) ----
    final isFinalRecap =
        statusUi.kind == _StatusKind.completed ||
        statusUi.kind == _StatusKind.cancelled ||
        statusUi.kind == _StatusKind.rejected;

    final now = DateTime.now();
    final tolerance = const Duration(minutes: 15);

    DateTime priceEnd;
    if (effectivePickup != null) {
      priceEnd = effectivePickup;
    } else if (statusUi.kind == _StatusKind.inStore) {
      // in corso: stima “se checkout ora”, ma mai prima della fascia pagata base
      priceEnd = now.isAfter(plannedPickup) ? now : plannedPickup;
    } else {
      // non ancora in store: non ha senso stimare oltre il planned
      priceEnd = plannedPickup;
    }

    final plannedDuration = BagDropPricing.inferDuration(
      start: plannedDropoff,
      end: plannedPickup,
    );
    final dueDuration = BagDropPricing.inferDuration(
      start: plannedDropoff,
      end: priceEnd,
    );

    final plannedTotal = BagDropPricing.totalFor(
      duration: plannedDuration,
      bagsS: booking.bagsS,
      bagsM: booking.bagsM,
      bagsL: booking.bagsL,
    );
    final dueTotal = BagDropPricing.totalFor(
      duration: dueDuration,
      bagsS: booking.bagsS,
      bagsM: booking.bagsM,
      bagsL: booking.bagsL,
    );

    int euroToCents(double v) => (v * 100).round();
    final plannedCents = euroToCents(plannedTotal);
    final dueCents = euroToCents(dueTotal);

    final extraCents = (dueCents - plannedCents) > 0
        ? (dueCents - plannedCents)
        : 0;
    final balanceCents = dueCents - _totalPaidCents;

    final isLateCheckout =
        effectivePickup != null &&
        effectivePickup.isAfter(plannedPickup.add(tolerance));

    final mustPaySupplementNow =
        statusUi.kind == _StatusKind.inStore &&
        balanceCents > 0 &&
        now.isAfter(plannedPickup.add(tolerance));

    final canDoCheckIn =
        statusUi.kind == _StatusKind.pending ||
        statusUi.kind == _StatusKind.confirmed;
    final canDoCheckOut = statusUi.kind == _StatusKind.inStore;

    Widget kvRow({
      required IconData icon,
      required String k,
      required String v,
      Color? vColor,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.65)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                k,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              v,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: vColor ?? cs.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      );
    }

    Widget paymentChip({
      required String title,
      required String subtitle,
      required String amount,
      required bool isBase,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  amount,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isBase ? cs.primary : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Dettaglio prenotazione',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
              .copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.12)),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          // ✅ HERO HEADER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.brandPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${booking.firstName} ${booking.lastName}'.trim(),
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _StatusPill(ui: statusUi),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Consegna: $dropoffStr',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.history_toggle_off,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ritiro: $pickupStr',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isFinalRecap ? 'Riepilogo finale' : 'Riepilogo in corso',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          // Motivo rifiuto (callout)
          if (statusUi.kind == _StatusKind.rejected &&
              (booking.rejectReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _Callout(
              icon: Icons.info_outline,
              title: 'Motivazione rifiuto',
              text: booking.rejectReason!.trim(),
              tone: _CalloutTone.danger,
            ),
          ],

          const SizedBox(height: 12),

          // ✅ NEW: ORARI (previsti vs effettivi) + stato check-in/out
          _SectionCard(
            title: 'Check-in / Check-out',
            icon: Icons.verified_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                kvRow(
                  icon: Icons.login,
                  k: 'Check-in previsto',
                  v: _formatDateTimeFull(plannedDropoff),
                ),
                kvRow(
                  icon: Icons.login,
                  k: 'Check-in effettivo',
                  v: _formatDateTimeFull(effectiveDropoff),
                ),
                const SizedBox(height: 6),
                kvRow(
                  icon: Icons.logout,
                  k: 'Check-out previsto',
                  v: _formatDateTimeFull(plannedPickup),
                ),
                kvRow(
                  icon: Icons.logout,
                  k: 'Check-out effettivo',
                  v: _formatDateTimeFull(effectivePickup),
                ),
                if (!isFinalRecap) ...[
                  const SizedBox(height: 10),
                  _Callout(
                    icon: canDoCheckIn
                        ? Icons.login
                        : (canDoCheckOut ? Icons.logout : Icons.info_outline),
                    title: 'Operazione richiesta',
                    text: canDoCheckIn
                        ? 'Da fare: check-in (scansiona il QR dell’utente).'
                        : canDoCheckOut
                        ? (mustPaySupplementNow
                              ? 'Check-out in attesa: supplemento non pagato. Attendi il pagamento in app prima di completare.'
                              : 'Da fare: check-out (scansiona il QR dell’utente).')
                        : 'Nessuna operazione richiesta.',
                    tone: mustPaySupplementNow
                        ? _CalloutTone.danger
                        : _CalloutTone.neutral,
                  ),
                ],
                if (isLateCheckout) ...[
                  const SizedBox(height: 10),
                  _Callout(
                    icon: Icons.warning_amber_rounded,
                    title: 'Ritardo check-out',
                    text:
                        'Check-out oltre la tolleranza di 15 min: applicato sovrapprezzo.',
                    tone: _CalloutTone.danger,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Contatto
          _SectionCard(
            title: 'Contatto',
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.firstName} ${booking.lastName}'.trim(),
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if ((booking.phone ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoLine(icon: Icons.phone_outlined, text: booking.phone!),
                ],
                if ((booking.email ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoLine(icon: Icons.email_outlined, text: booking.email!),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Bagagli
          _SectionCard(
            title: 'Bagagli',
            icon: Icons.inventory_2_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Totale: $totalBags',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (booking.bagsS > 0)
                      _MiniPill(label: 'S × ${booking.bagsS}'),
                    if (booking.bagsM > 0)
                      _MiniPill(label: 'M × ${booking.bagsM}'),
                    if (booking.bagsL > 0)
                      _MiniPill(label: 'L × ${booking.bagsL}'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Note cliente
          if ((booking.notes ?? '').trim().isNotEmpty) ...[
            _Callout(
              icon: Icons.sticky_note_2_outlined,
              title: 'Note cliente',
              text: booking.notes!.trim(),
              tone: _CalloutTone.neutral,
            ),
            const SizedBox(height: 12),
          ],

          // ✅ NEW: PAGAMENTI + TOTALI + SUPPLEMENTI (allineato all’utente)
          _SectionCard(
            title: 'Pagamenti e importi',
            icon: Icons.payments_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                kvRow(
                  icon: Icons.receipt_long_outlined,
                  k: 'Pagamenti effettuati',
                  v: _loadingPayments ? '…' : '${_payments.length}',
                ),
                kvRow(
                  icon: Icons.check_circle_outline,
                  k: 'Totale pagato',
                  v: _loadingPayments ? '…' : _euroCents(_totalPaidCents),
                ),

                const SizedBox(height: 10),
                if (_coveredUntil != null) ...[
                  _Callout(
                    icon: Icons.verified_outlined,
                    title: 'Coperto fino',
                    text: _formatDateTimeFull(_coveredUntil),
                    tone: _CalloutTone.neutral,
                  ),
                  const SizedBox(height: 10),
                ],
                if (!_loadingPayments && _paymentsError != null) ...[
                  Text(
                    'Impossibile caricare pagamenti: $_paymentsError',
                    style: tt.bodySmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!_loadingPayments && _paymentsError == null) ...[
                  if (_payments.isEmpty)
                    Text(
                      'Nessun pagamento registrato.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    )
                  else
                    Column(
                      children: [
                        const SizedBox(height: 6),
                        ..._payments.map((p) {
                          final isBase = p.kind == 'base';
                          final title = isBase
                              ? 'Pagamento base'
                              : 'Supplemento';
                          final range =
                              (!isBase &&
                                  (p.fromCoveredUntil != null ||
                                      p.toCoveredUntil != null))
                              ? 'Estensione: ${_formatDateTimeFull(p.fromCoveredUntil)} → ${_formatDateTimeFull(p.toCoveredUntil)}'
                              : null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: paymentChip(
                              title: title,
                              subtitle:
                                  range ??
                                  'Pagato il ${_formatDateTimeFull(p.paidAt)}',
                              amount: _euroCents(p.amountCents),
                              isBase: isBase,
                            ),
                          );
                        }),
                        const SizedBox(height: 2),
                        if (_supplementsPaidCents > 0)
                          Text(
                            'Supplementi pagati: ${_euroCents(_supplementsPaidCents)}',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ],
      ),

      // ✅ NEW: bottom bar con azioni (check-in/out + rifiuto) senza dipendenze da scanner route
      bottomNavigationBar: (canDoCheckIn || canDoCheckOut || _canReject)
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canReject)
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _rejecting ? null : _rejectBooking,
                          icon: _rejecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.block),
                          label: Text(
                            _rejecting ? 'Rifiuto…' : 'Rifiuta prenotazione',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandYellow,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

enum _StatusKind { pending, confirmed, inStore, rejected, cancelled, completed }

class _StatusUI {
  final _StatusKind kind;
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatusUI({
    required this.kind,
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  static _StatusUI from(String status) {
    final st = status.trim().toLowerCase();

    if (st == 'pending') {
      return _StatusUI(
        kind: _StatusKind.pending,
        label: 'In attesa',
        bg: AppTheme.brandYellow.withOpacity(0.20),
        fg: Colors.black87,
        icon: Icons.hourglass_bottom,
      );
    }

    if (st == 'in_store') {
      return _StatusUI(
        kind: _StatusKind.inStore,
        label: 'In deposito',
        bg: Colors.blue.withOpacity(0.12),
        fg: Colors.blue.shade800,
        icon: Icons.lock_clock_outlined,
      );
    }

    // ✅ rifiutata lato partner
    if (st == 'rejected' || st == 'cancelled_by_partner') {
      return _StatusUI(
        kind: _StatusKind.rejected,
        label: 'Rifiutata',
        bg: Colors.red.withOpacity(0.12),
        fg: Colors.red.shade800,
        icon: Icons.block,
      );
    }

    if (st == 'completed') {
      return _StatusUI(
        kind: _StatusKind.completed,
        label: 'Completata',
        bg: Colors.blue.withOpacity(0.12),
        fg: Colors.blue.shade800,
        icon: Icons.check_circle_outline,
      );
    }

    if (st == 'cancelled' ||
        st == 'canceled' ||
        st == 'cancelled_by_user' ||
        st == 'expired') {
      return _StatusUI(
        kind: _StatusKind.cancelled,
        label: 'Annullata',
        bg: Colors.grey.withOpacity(0.14),
        fg: Colors.grey.shade800,
        icon: Icons.cancel_outlined,
      );
    }

    // default: confirmed
    return _StatusUI(
      kind: _StatusKind.confirmed,
      label: 'Confermata',
      bg: AppTheme.brandPurple.withOpacity(0.14),
      fg: AppTheme.brandPurple,
      icon: Icons.verified_outlined,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _StatusUI ui;
  const _StatusPill({required this.ui});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: ui.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ui.icon, size: 16, color: ui.fg),
          const SizedBox(width: 6),
          Text(
            ui.label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: ui.fg,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.65)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  const _MiniPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

enum _CalloutTone { neutral, danger }

class _Callout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final _CalloutTone tone;

  const _Callout({
    required this.icon,
    required this.title,
    required this.text,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = tone == _CalloutTone.danger
        ? Colors.red.withOpacity(0.08)
        : cs.surfaceContainerHighest.withOpacity(0.6);

    final Color border = tone == _CalloutTone.danger
        ? Colors.red.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.35);

    final Color fg = tone == _CalloutTone.danger
        ? Colors.red.shade800
        : cs.onSurface.withOpacity(0.85);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900, color: fg),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
