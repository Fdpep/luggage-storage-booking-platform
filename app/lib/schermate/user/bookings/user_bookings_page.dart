import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/schermate/user/bookings/booking_recap_screen.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';
import 'package:BagDrop/schermate/user/bookings/booking_qr_screen.dart';
import 'package:BagDrop/schermate/user/bookings/booking_final_recap_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';

class UserBookingsPage extends StatefulWidget {
  const UserBookingsPage({super.key});

  @override
  State<UserBookingsPage> createState() => _UserBookingsPageState();
}

class _UserBookingsPageState extends State<UserBookingsPage> {
  late Future<List<PartnerBooking>> _futureBookings;
  final _bookingRepo = PartnerBookingRepo(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _futureBookings = _bookingRepo.getMyBookings();
  }

  Future<void> _reload() async {
    setState(() {
      _futureBookings = _bookingRepo.getMyBookings();
    });
    await _futureBookings;
  }

  _StatusFilter _statusFilter = _StatusFilter.all;
  DateTimeRange? _dateRange;
  _BookingSort _sort = _BookingSort.dropoffDesc;

  String _normStatus(String s) => s.trim().toLowerCase();

  bool _isCancelledStatus(String s) {
    final st = _normStatus(s);
    return st == 'cancelled' || st == 'canceled' || st == 'cancelled_by_user';
  }

  _StatusFilter _mapToFilter(String status) {
    final st = _normStatus(status);

    // if (st == 'pending') return _StatusFilter.pending;
    if (st == 'in_store') return _StatusFilter.inStore;
    if (st == 'rejected' || st == 'cancelled_by_partner') {
      return _StatusFilter.rejected;
    }
    if (st == 'completed') return _StatusFilter.completed;
    if (_isCancelledStatus(st)) return _StatusFilter.cancelled;

    return _StatusFilter.confirmed;
  }

  bool _inRange(DateTime d, DateTimeRange r) {
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  List<PartnerBooking> _applyFilters(List<PartnerBooking> input) {
    var list = List<PartnerBooking>.from(input);

    if (_statusFilter != _StatusFilter.all) {
      list = list
          .where((b) => _mapToFilter(b.uiStatus) == _statusFilter)
          .toList();
    }

    if (_dateRange != null) {
      list = list
          .where((b) => _inRange(b.plannedDropoffAtLocal, _dateRange!))
          .toList();
    }

    int cmpDate(DateTime a, DateTime b) => a.compareTo(b);

    list.sort((a, b) {
      switch (_sort) {
        case _BookingSort.dropoffAsc:
          return cmpDate(a.plannedDropoffAtLocal, b.plannedDropoffAtLocal);
        case _BookingSort.dropoffDesc:
          return cmpDate(b.plannedDropoffAtLocal, a.plannedDropoffAtLocal);
        case _BookingSort.createdAsc:
          return cmpDate(a.createdAt, b.createdAt);
        case _BookingSort.createdDesc:
          return cmpDate(b.createdAt, a.createdAt);
      }
    });

    return list;
  }

  String _statusFilterLabel(_StatusFilter f) {
    switch (f) {
      case _StatusFilter.all:
        return 'Tutte';
      case _StatusFilter.confirmed:
        return 'Confermate';
      case _StatusFilter.inStore:
        return 'In deposito';
      case _StatusFilter.rejected:
        return 'Rifiutate';
      case _StatusFilter.cancelled:
        return 'Annullate';
      case _StatusFilter.completed:
        return 'Completate';
    }
  }

  String _sortLabel(_BookingSort s) {
    switch (s) {
      case _BookingSort.dropoffDesc:
        return 'Consegna ↓';
      case _BookingSort.dropoffAsc:
        return 'Consegna ↑';
      case _BookingSort.createdDesc:
        return 'Creazione ↓';
      case _BookingSort.createdAsc:
        return 'Creazione ↑';
    }
  }

  // ---- DATE PRESET (uguale al partner) ----

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) => _day(a) == _day(b);

  DateTimeRange _rangeDays(DateTime start, DateTime end) =>
      DateTimeRange(start: _day(start), end: _day(end));

  _DatePreset _currentDatePreset() {
    if (_dateRange == null) return _DatePreset.all;

    final now = DateTime.now();
    final today = _day(now);
    final tomorrow = _day(now.add(const Duration(days: 1)));

    final r = _rangeDays(_dateRange!.start, _dateRange!.end);

    if (_sameDay(r.start, today) && _sameDay(r.end, today)) {
      return _DatePreset.today;
    }
    if (_sameDay(r.start, tomorrow) && _sameDay(r.end, tomorrow)) {
      return _DatePreset.tomorrow;
    }

    if (_sameDay(r.start, today) &&
        _sameDay(r.end, today.add(const Duration(days: 6)))) {
      return _DatePreset.next7;
    }
    if (_sameDay(r.start, today) &&
        _sameDay(r.end, today.add(const Duration(days: 29)))) {
      return _DatePreset.next30;
    }

    final first = DateTime(today.year, today.month, 1);
    final last = DateTime(today.year, today.month + 1, 0);
    if (_sameDay(r.start, first) && _sameDay(r.end, last)) {
      return _DatePreset.thisMonth;
    }

    return _DatePreset.custom;
  }

  String _datePresetLabel(_DatePreset p) {
    switch (p) {
      case _DatePreset.all:
        return 'Tutte';
      case _DatePreset.today:
        return 'Oggi';
      case _DatePreset.tomorrow:
        return 'Domani';
      case _DatePreset.next7:
        return 'Prossimi 7 giorni';
      case _DatePreset.next30:
        return 'Prossimi 30 giorni';
      case _DatePreset.thisMonth:
        return 'Questo mese';
      case _DatePreset.custom:
        return 'Personalizzato…';
    }
  }

  String _datePillValue() {
    if (_dateRange == null) return 'Tutte';
    final preset = _currentDatePreset();
    if (preset != _DatePreset.custom) return _datePresetLabel(preset);

    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final r = _rangeDays(_dateRange!.start, _dateRange!.end);
    return '${f(r.start)} → ${f(r.end)}';
  }

  void _onDatePresetSelected(_DatePreset p) async {
    final now = DateTime.now();
    final today = _day(now);

    if (p == _DatePreset.all) {
      setState(() => _dateRange = null);
      return;
    }

    if (p == _DatePreset.today) {
      setState(() => _dateRange = _rangeDays(today, today));
      return;
    }

    if (p == _DatePreset.tomorrow) {
      final t = today.add(const Duration(days: 1));
      setState(() => _dateRange = _rangeDays(t, t));
      return;
    }

    if (p == _DatePreset.next7) {
      setState(
        () =>
            _dateRange = _rangeDays(today, today.add(const Duration(days: 6))),
      );
      return;
    }

    if (p == _DatePreset.next30) {
      setState(
        () =>
            _dateRange = _rangeDays(today, today.add(const Duration(days: 29))),
      );
      return;
    }

    if (p == _DatePreset.thisMonth) {
      final first = DateTime(today.year, today.month, 1);
      final last = DateTime(today.year, today.month + 1, 0);
      setState(() => _dateRange = _rangeDays(first, last));
      return;
    }

    // custom
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = _rangeDays(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Prenotazioni',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterMenuPill<_StatusFilter>(
                    icon: Icons.tune,
                    label: 'Stato',
                    value: _statusFilterLabel(_statusFilter),
                    selected: _statusFilter,
                    items: _StatusFilter.values
                        .map(
                          (v) => _FilterMenuItem<_StatusFilter>(
                            value: v,
                            label: _statusFilterLabel(v),
                          ),
                        )
                        .toList(),
                    onSelected: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(width: 10),
                  _DateMenuPill(
                    value: _datePillValue(),
                    selectedPreset: _currentDatePreset(),
                    onSelected: _onDatePresetSelected,
                    onClear: _dateRange == null
                        ? null
                        : () => setState(() => _dateRange = null),
                  ),
                  const SizedBox(width: 10),
                  _FilterMenuPill<_BookingSort>(
                    icon: Icons.sort,
                    label: 'Consegna',
                    value: _sortLabel(_sort),
                    selected: _sort,
                    items: const [
                      _FilterMenuItem(
                        value: _BookingSort.dropoffDesc,
                        label: 'Più recenti',
                      ),
                      _FilterMenuItem(
                        value: _BookingSort.dropoffAsc,
                        label: 'Meno recenti',
                      ),
                    ],
                    onSelected: (v) => setState(() => _sort = v),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<PartnerBooking>>(
        future: _futureBookings,
        builder: (context, snapshot) {
          final cs = Theme.of(context).colorScheme;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Impossibile caricare le prenotazioni.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            );
          }

          final bookings = snapshot.data ?? [];
          final filtered = _applyFilters(bookings);

          if (bookings.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                _HintCard(
                  'Non hai ancora prenotazioni. Quando prenoti, appariranno qui.',
                ),
              ],
            );
          }

          if (filtered.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                _HintCard('Nessuna prenotazione con questi filtri.'),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final booking = filtered[index];
                return _BookingListItem(booking: booking, onChanged: _reload);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Card di lista con partner + stato + data.
/// - NON tocca minimamente UI/Logica di "in_store" e "completed" (restano come nel codice iniziale)
/// - Aggiunge solo: annullamento SOLO per "confirmed" + estetica dedicata per "cancelled"
class _BookingListItem extends StatefulWidget {
  final PartnerBooking booking;
  final VoidCallback onChanged;

  const _BookingListItem({required this.booking, required this.onChanged});

  @override
  State<_BookingListItem> createState() => _BookingListItemState();
}

class _BookingListItemState extends State<_BookingListItem> {
  final _partnerRepo = PartnerRepo(Supabase.instance.client);
  final _bookingRepo = PartnerBookingRepo(Supabase.instance.client);

  late Future<Partner?> _futurePartner;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _futurePartner = _partnerRepo.getPartnerById(widget.booking.partnerId);
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatCountdown(Duration diff, {String prefix = 'Manca'}) {
    final isNeg = diff.isNegative;
    final d = diff.abs();
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);

    if (h > 0) {
      return isNeg ? 'In ritardo di ${h}h ${m}m' : '$prefix ${h}h ${m}m';
    }
    final mins = d.inMinutes;
    return isNeg ? 'In ritardo di ${mins} min' : '$prefix ${mins} min';
  }

  bool _isRejectedStatus(String statusRaw) {
    final st = statusRaw.trim().toLowerCase();
    return st == 'rejected' || st == 'cancelled_by_partner';
  }

  bool _isCancelledStatus(String s) {
    final st = s.trim().toLowerCase();
    return st == 'cancelled' || st == 'canceled' || st == 'cancelled_by_user';
  }

  Widget _buildInStoreReminder(
    BuildContext context, {
    required DateTime dropoff,
    required DateTime pickup,
  }) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    // tolleranza checkout
    const tolerance = Duration(minutes: 15);
    final deadline = pickup.add(tolerance);

    final diffToPickup = pickup.difference(now); // >0 se manca
    final diffToDeadline = deadline.difference(
      now,
    ); // >0 se siamo ancora in tolleranza

    final bool beforePickup = diffToPickup > Duration.zero;
    final bool inTolerance = !beforePickup && diffToDeadline > Duration.zero;
    final bool afterDeadline = !beforePickup && !inTolerance;

    // colori e testi
    final Color accent = beforePickup
        ? Colors.blue.shade600
        : (inTolerance ? Colors.orange.shade700 : Colors.red.shade600);

    final String title = beforePickup
        ? 'Ritiro previsto'
        : (inTolerance ? 'Ritiro scaduto (tolleranza)' : 'Checkout scaduto');

    final String pillText = beforePickup
        ? _formatCountdown(diffToPickup, prefix: 'Manca')
        : (inTolerance
              ? _formatCountdown(diffToDeadline, prefix: 'Tolleranza')
              : _formatCountdown(
                  deadline.difference(now),
                )); // NEG => "In ritardo"

    final String note = beforePickup
        ? 'Ricorda di fare il check-out entro l’orario previsto.'
        : (inTolerance
              ? 'Se fai il check-out entro la tolleranza, non dovrebbe esserci sovrapprezzo.'
              : '⚠️ Oltre la tolleranza: potrebbe essere richiesto un sovrapprezzo al check-out.');

    // progress: dropoff -> pickup
    final totalSec = pickup.difference(dropoff).inSeconds;
    double? progress;
    if (totalSec > 0) {
      final elapsedSec = now.difference(dropoff).inSeconds;
      progress = (elapsedSec / totalSec).clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pillText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(pickup),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: cs.onSurface.withOpacity(0.9),
            ),
          ),
          if (!beforePickup) ...[
            const SizedBox(height: 4),
            Text(
              'Scadenza tolleranza: ${_formatDate(deadline)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(0.65),
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: cs.onSurface.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            note,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, String statusRaw) {
    final cs = Theme.of(context).colorScheme;
    final status = statusRaw.toLowerCase();

    switch (status) {
      case 'confirmed':
        return Colors.green.shade600;

      // case 'pending':
      //   return Colors.orange.shade700;

      case 'in_store':
        return Colors.blue.shade600;

      case 'completed':
        return Colors.indigo.shade600;

      case 'cancelled':
      case 'canceled':
      case 'cancelled_by_user':
        return Colors.grey.shade700;

      case 'cancelled_by_partner':
      case 'rejected':
        return Colors.red.shade700;

      default:
        return cs.onSurface.withOpacity(0.7);
    }
  }

  String _statusLabel(String statusRaw) {
    switch (statusRaw.toLowerCase()) {
      case 'confirmed':
        return 'Confermata';
      case 'in_store':
        return 'In deposito';
      case 'completed':
        return 'Completata';
      case 'cancelled':
      case 'canceled':
      case 'cancelled_by_user':
        return 'Annullata';
      case 'rejected':
      case 'cancelled_by_partner':
        return 'Rifiutata';
      default:
        return statusRaw;
    }
  }

  IconData _statusIcon(String statusRaw) {
    switch (statusRaw.toLowerCase()) {
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'in_store':
        return Icons.lock_clock_outlined;
      case 'completed':
        return Icons.verified_outlined;
      case 'cancelled':
      case 'canceled':
      case 'cancelled_by_user':
        return Icons.event_busy_outlined;
      case 'cancelled_by_partner':
      case 'rejected':
        return Icons.block_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Future<bool> _confirmCancel(BuildContext context) async {
    return (await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Annullare la prenotazione?',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Questa operazione è irreversibile. La prenotazione verrà annullata definitivamente.',
                      style: TextStyle(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Torna indietro'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Annulla'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        )) ??
        false;
  }

  Future<void> _cancelBooking() async {
    if (_cancelling) return;

    final ok = await _confirmCancel(context);
    if (!ok || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await _bookingRepo.cancelBookingByUser(bookingId: widget.booking.id);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prenotazione annullata')));

      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Widget _cancelledAestheticBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min, // ✅ centra il gruppo icona + testo
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 18,
              color: cs.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 10),
            Text(
              'Prenotazione annullata.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final booking = widget.booking;

    // ⚠️ come nel tuo file (non cambiare logica dati)
    final dropoff = booking.plannedDropoffLocal;
    final pickup = booking.plannedPickupAtLocal;
    final now = DateTime.now();
    final canCancelByTime = now.isBefore(dropoff);

    final statusRaw = booking.uiStatus.trim().toLowerCase();
    final isCancelled = _isCancelledStatus(statusRaw);
    final isCompleted = statusRaw == 'completed';
    final isConfirmed = statusRaw == 'confirmed';

    final isRejected = _isRejectedStatus(statusRaw);

    // QR: come nel codice iniziale (NON tocchiamo la logica)
    final qrAvailable =
        !isCompleted && (statusRaw == 'confirmed' || statusRaw == 'in_store');

    return FutureBuilder<Partner?>(
      future: _futurePartner,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final partner = snapshot.data;
        final hasError = snapshot.hasError;
        final now = DateTime.now();
        final canCancelByTime = now.isBefore(
          dropoff,
        ); // dropoff = booking.plannedDropoffLocal
        final partnerName = isLoading
            ? 'Caricamento attività...'
            : (partner?.name ?? 'Attività non disponibile');

        // ==========================
        // 1) CANCELLED: invariata
        // ==========================
        if (isCancelled) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            context,
                            statusRaw,
                          ).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon(statusRaw),
                              size: 14,
                              color: _statusColor(context, statusRaw),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _statusLabel(statusRaw),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _statusColor(context, statusRaw),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDate(dropoff),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'creata il ${_formatDate(booking.createdAt)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Errore nel caricamento dell’attività.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.luggage_outlined,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Bagagli: ${booking.bagsS + booking.bagsM + booking.bagsL}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  _cancelledAestheticBanner(context),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: partner == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookingRecapScreen(
                                    partner: partner,
                                    booking: booking,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Riepilogo'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // ==========================
        // 1B) REJECTED: estetica rossa dedicata
        // ==========================
        if (isRejected) {
          final red = Colors.red.shade700;
          final reason = (booking.rejectReason ?? '').trim();
          final reasonText = reason.isEmpty
              ? 'Motivazione non specificata.'
              : reason;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              //side: BorderSide(color: red.withOpacity(0.18)),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                //color: red.withOpacity(0.035),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER: pill rifiutata + date (dropoff e creazione)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 14, color: red),
                            const SizedBox(width: 6),
                            Text(
                              'Rifiutata',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDate(dropoff),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.82),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'creata il ${_formatDate(booking.createdAt)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Nome partner
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Errore nel caricamento dell’attività.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Date utili (consegna/ritiro)
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Consegna: ${_formatDate(dropoff)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withOpacity(0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ritiro: ${_formatDate(pickup)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withOpacity(0.75),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Bags quick line
                  Row(
                    children: [
                      Icon(
                        Icons.luggage_outlined,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bagagli: ${booking.bagsS + booking.bagsM + booking.bagsL}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withOpacity(0.80),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'S:${booking.bagsS}  M:${booking.bagsM}  L:${booking.bagsL}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(0.60),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // BOX motivo rifiuto (stile moderno, rosso)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(
                        0.55,
                      ), // resta pulito sopra il rosso light
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: red.withOpacity(0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: red),
                            const SizedBox(width: 8),
                            Text(
                              'Motivazione del rifiuto',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface.withOpacity(0.92),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reasonText,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            color: cs.onSurface.withOpacity(0.82),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.currency_exchange_outlined,
                              size: 16,
                              color: red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Se era stato effettuato un pagamento, verrà avviato il rimborso secondo le tempistiche del metodo di pagamento.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.25,
                                  color: cs.onSurface.withOpacity(0.70),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(height: 1, color: cs.onSurface.withOpacity(0.08)),
                  const SizedBox(height: 12),

                  // Azioni: solo Riepilogo (niente QR)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: partner == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookingRecapScreen(
                                    partner: partner,
                                    booking: booking,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text(
                        'Riepilogo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // =====================================
        // 2) CONFIRMED: RESTYLING + FIX OVERFLOW
        // =====================================

        if (isConfirmed) {
          final statusColor = _statusColor(context, statusRaw);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: cs.onSurface.withOpacity(0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER: pill stato (sx) + date (dx)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon(statusRaw),
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _statusLabel(statusRaw),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDate(dropoff),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.82),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'creata il ${_formatDate(booking.createdAt)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Nome partner
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'Errore nel caricamento dell’attività.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Riga "bagagli" (sx) + "annulla" (dx) con vincolo orario:
                  // - annullabile SOLO prima dell'orario di dropoff (check-in pianificato)
                  // - dopo quell'orario: bottone disabled + microhint
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.luggage_outlined,
                              size: 16,
                              color: cs.onSurface.withOpacity(0.70),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Bagagli: ${booking.bagsS + booking.bagsM + booking.bagsL}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurface.withOpacity(0.75),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Annulla: disabilitato se oltre orario o se sta annullando
                      OutlinedButton.icon(
                        onPressed: (_cancelling || !canCancelByTime)
                            ? null
                            : _cancelBooking,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: (_cancelling || !canCancelByTime)
                              ? cs.onSurface.withOpacity(0.35)
                              : Colors.red.shade700,
                        ),
                        label: Text(
                          _cancelling
                              ? '...'
                              : (canCancelByTime
                                    ? 'Annulla prenotazione'
                                    : 'Non annullabile'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: (_cancelling || !canCancelByTime)
                                ? cs.onSurface.withOpacity(0.45)
                                : Colors.red.shade700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: (_cancelling || !canCancelByTime)
                                ? cs.onSurface.withOpacity(0.12)
                                : Colors.red.shade200,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),

                  // Hint sotto riga (solo se non annullabile per orario)
                  if (!canCancelByTime) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: cs.onSurface.withOpacity(0.55),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Annullabile fino a ${_formatDate(dropoff)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(0.60),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  Divider(height: 1, color: cs.onSurface.withOpacity(0.08)),
                  const SizedBox(height: 12),

                  // AZIONI SOTTO: Riepilogo + QR (logica invariata)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: partner == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingRecapScreen(
                                        partner: partner,
                                        booking: booking,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                          ),
                          label: const Text(
                            'Riepilogo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (partner == null || !qrAvailable)
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingQrScreen(
                                        bookingId: booking.id,
                                        bookingCode: booking.bookingCode,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text(
                            'QR code',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // =========================================
        // 3) ALTRI STATI: IDENTICO A PRIMA (in_store/completed ecc.)
        // =========================================
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(
                          context,
                          statusRaw,
                        ).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(statusRaw),
                            size: 14,
                            color: _statusColor(context, statusRaw),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _statusLabel(statusRaw),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _statusColor(context, statusRaw),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDate(dropoff),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'creata il ${_formatDate(booking.createdAt)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  partnerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Errore nel caricamento dell’attività.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.luggage_outlined,
                      size: 16,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bagagli: ${booking.bagsS + booking.bagsM + booking.bagsL}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
                if (statusRaw == 'in_store') ...[
                  const SizedBox(height: 10),
                  _buildInStoreReminder(
                    context,
                    dropoff: dropoff,
                    pickup: pickup,
                  ),
                ],
                const SizedBox(height: 8),
                if (isCompleted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: partner == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookingFinalRecapScreen(
                                    partner: partner,
                                    booking: booking,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('Riepilogo finale'),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: partner == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingRecapScreen(
                                        partner: partner,
                                        booking: booking,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                          ),
                          label: const Text('Riepilogo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (partner == null || !qrAvailable)
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingQrScreen(
                                        bookingId: booking.id,
                                        bookingCode: booking.bookingCode,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('QR code'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Versione light di SectionTitle / HintCard per riusare lo stile in questa pagina.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
        fontSize: 18,
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

enum _StatusFilter {
  all,
  // pending,
  confirmed,
  inStore,
  rejected,
  cancelled,
  completed,
}

enum _BookingSort { dropoffAsc, dropoffDesc, createdAsc, createdDesc }

enum _DatePreset { all, today, tomorrow, next7, next30, thisMonth, custom }

class _FilterMenuItem<T> {
  final T value;
  final String label;
  const _FilterMenuItem({required this.value, required this.label});
}

class _FilterMenuPill<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final T selected;
  final List<_FilterMenuItem<T>> items;
  final ValueChanged<T> onSelected;

  const _FilterMenuPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: '',
      onSelected: onSelected,
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (ctx) => items
          .map(
            (it) => PopupMenuItem<T>(
              value: it.value,
              child: Row(
                children: [
                  Expanded(child: Text(it.label)),
                  if (it.value == selected) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          )
          .toList(),
      child: _FilterPillVisual(icon: icon, label: label, value: value),
    );
  }
}

class _FilterPillVisual extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FilterPillVisual({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.expand_more,
            size: 18,
            color: Colors.white.withOpacity(0.95),
          ),
        ],
      ),
    );
  }
}

class _DateMenuPill extends StatelessWidget {
  final String value;
  final _DatePreset selectedPreset;
  final ValueChanged<_DatePreset> onSelected;
  final VoidCallback? onClear;

  const _DateMenuPill({
    required this.value,
    required this.selectedPreset,
    required this.onSelected,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DatePreset>(
      tooltip: '',
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (ctx) => _DatePreset.values.map((p) {
        return PopupMenuItem<_DatePreset>(
          value: p,
          child: Row(
            children: [
              Expanded(child: Text(_label(p))),
              if (p == selectedPreset) const Icon(Icons.check, size: 18),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            const Text(
              'Data',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more,
                size: 18,
                color: Colors.white.withOpacity(0.95),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(_DatePreset p) {
    switch (p) {
      case _DatePreset.all:
        return 'Tutte';
      case _DatePreset.today:
        return 'Oggi';
      case _DatePreset.tomorrow:
        return 'Domani';
      case _DatePreset.next7:
        return 'Prossimi 7 giorni';
      case _DatePreset.next30:
        return 'Prossimi 30 giorni';
      case _DatePreset.thisMonth:
        return 'Questo mese';
      case _DatePreset.custom:
        return 'Personalizzato…';
    }
  }
}
