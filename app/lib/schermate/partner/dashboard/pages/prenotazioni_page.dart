import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'partner_booking_detail_screen.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import '../../user_view/partner_drawer.dart';
import 'package:BagDrop/theme/app_theme.dart';

/// Pagina "Prenotazioni" dentro la PartnerShell.
/// Mostra tutte le prenotazioni ricevute dal locale.
class PrenotazioniPage extends StatefulWidget {
  final Partner? partner;

  const PrenotazioniPage({super.key, required this.partner});

  @override
  State<PrenotazioniPage> createState() => _PrenotazioniPageState();
}

class _PrenotazioniPageState extends State<PrenotazioniPage> {
  bool _loading = true;
  String? _error;
  List<PartnerBooking> _bookings = [];

  _StatusFilter _statusFilter = _StatusFilter.all;
  DateTimeRange? _dateRange;
  _BookingSort _sort = _BookingSort.dropoffDesc;

  String _normStatus(String s) => s.trim().toLowerCase();

  _StatusFilter _mapToFilter(String status) {
    final st = _normStatus(status);
    //if (st == 'pending') return _StatusFilter.pending;
    if (st == 'in_store') return _StatusFilter.inStore;
    if (st == 'rejected') return _StatusFilter.rejected;
    if (st == 'completed') return _StatusFilter.completed;
    /*if (st == 'cancelled' ||
        st == 'canceled' ||
        st == 'cancelled_by_user' ||
        st == 'cancelled_by_partner') {
      return _StatusFilter.cancelled;
    }*/
    // default: confermata/accepted ecc
    return _StatusFilter.confirmed;
  }

  bool _inRange(DateTime d, DateTimeRange r) {
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  List<PartnerBooking> get _filteredBookings {
    var list = List<PartnerBooking>.from(_bookings);

    if (_statusFilter != _StatusFilter.all) {
      list = list
          .where((b) => _mapToFilter(b.uiStatus) == _statusFilter)
          .toList();
    }
    if (_dateRange != null) {
      list = list
          .where((b) => _inRange(b.plannedDropoffLocal, _dateRange!))
          .toList();
    }

    int cmpDate(DateTime a, DateTime b) => a.compareTo(b);

    list.sort((a, b) {
      switch (_sort) {
        case _BookingSort.dropoffAsc:
          return cmpDate(a.plannedDropoffLocal, b.plannedDropoffLocal);
        case _BookingSort.dropoffDesc:
          return cmpDate(b.plannedDropoffLocal, a.plannedDropoffLocal);
        case _BookingSort.createdAsc:
          return cmpDate(a.createdAt, b.createdAt);
        case _BookingSort.createdDesc:
          return cmpDate(b.createdAt, a.createdAt);
      }
    });

    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    if (widget.partner == null) {
      setState(() {
        _loading = false;
        _error =
            'Nessuna attività associata a questo account.\nCompleta prima la registrazione del locale.';
        _bookings = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final items = await repo.getBookingsForPartner(widget.partner!.id);

      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Errore _loadBookings PrenotazioniPage: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore durante il caricamento delle prenotazioni.';
      });
    }
  }

  Future<String?> _openRejectSheet(BuildContext context) {
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
                    'Scegli una motivazione oppure scrivila. Il campo è obbligatorio.',
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
                          child: const Text('Conferma rifiuto'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _canReject(PartnerBooking b) {
    final s = (b.status).toLowerCase();
    return ![
      'in_store',
      'completed',
      'cancelled',
      'cancelled_by_user',
      'cancelled_by_partner',
      'expired',
    ].contains(s);
  }

  String _statusFilterLabel(_StatusFilter f) {
    switch (f) {
      case _StatusFilter.all:
        return 'Tutte';
      //case _StatusFilter.pending:
      // return 'In attesa';
      case _StatusFilter.confirmed:
        return 'Confermate';
      case _StatusFilter.inStore:
        return 'In deposito';
      case _StatusFilter.rejected:
        return 'Rifiutate';
      case _StatusFilter.completed:
        return 'Completate';
      // case _StatusFilter.cancelled:
      // return 'Annullate';
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

  String _dateRangeLabel(DateTimeRange r) {
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${f(r.start)} → ${f(r.end)}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
  }

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

    if (_sameDay(r.start, today) && _sameDay(r.end, today))
      return _DatePreset.today;
    if (_sameDay(r.start, tomorrow) && _sameDay(r.end, tomorrow))
      return _DatePreset.tomorrow;

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
    if (_sameDay(r.start, first) && _sameDay(r.end, last))
      return _DatePreset.thisMonth;

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

    // ✅ Personalizzato…
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
      drawer: const PartnerDrawer(),
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

      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: _buildBodySliver(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodySliver() {
    if (_loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final list = _filteredBookings;

    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: Text(
            'Nessuna prenotazione con questi filtri.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final booking = list[index];

        return _BookingCardModern(
          booking: booking,
          canReject: _canReject(booking),
          onOpenDetail: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PartnerBookingDetailScreen(booking: booking),
                  ),
                )
                .then((changed) {
                  if (changed == true) _loadBookings();
                });
          },
          onReject: () => _openRejectSheet(context),
        );
      }, childCount: list.length),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(_error!, textAlign: TextAlign.center)],
      );
    }

    if (_bookings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Non hai ancora ricevuto prenotazioni.\n'
            'Quando un utente prenota il tuo locale, vedrai qui i dettagli.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final booking = _bookings[index];

        return _BookingCardModern(
          booking: booking,
          canReject: _canReject(booking),
          onOpenDetail: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PartnerBookingDetailScreen(booking: booking),
                  ),
                )
                .then((changed) {
                  if (changed == true) _loadBookings();
                });
          },
          onReject: () => _openRejectSheet(context),
        );
      },
    );
  }
}

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
      offset: const Offset(0, 52), // menu “sotto” la pill
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

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              if (onClear != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final _StatusFilter status;
  final DateTimeRange? dateRange;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  const _FiltersBar({
    required this.status,
    required this.dateRange,
    required this.onStatusChanged,
    required this.onPickDate,
    required this.onClearDate,
  });

  String _labelDate(DateTimeRange r) {
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${f(r.start)} → ${f(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    ChoiceChip chip(_StatusFilter v, String label) {
      return ChoiceChip(
        label: Text(label),
        selected: status == v,
        onSelected: (_) => onStatusChanged(v),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(_StatusFilter.all, 'Tutte'),
              const SizedBox(width: 8),
              chip(_StatusFilter.confirmed, 'Confermate'),
              const SizedBox(width: 8),
              chip(_StatusFilter.rejected, 'Rifiutate'),
              const SizedBox(width: 8),
              chip(_StatusFilter.completed, 'Completate'),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      dateRange == null
                          ? 'Data: tutte'
                          : _labelDate(dateRange!),
                    ),
                  ],
                ),
              ),
            ),
            if (dateRange != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Rimuovi filtro data',
                onPressed: onClearDate,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

enum _StatusFilter { all, confirmed, inStore, rejected, completed }

enum _BookingSort { dropoffAsc, dropoffDesc, createdAsc, createdDesc }

enum _DatePreset { all, today, tomorrow, next7, next30, thisMonth, custom }

/// Card singola prenotazione.
class _BookingCardModern extends StatelessWidget {
  final PartnerBooking booking;
  final VoidCallback onOpenDetail;
  final VoidCallback? onReject;
  final bool canReject;

  const _BookingCardModern({
    required this.booking,
    required this.onOpenDetail,
    required this.canReject,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final d = booking.plannedDropoffLocal;
    final dropoffStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    final statusUi = _StatusUI.from(booking.uiStatus);
    final showRejectReason =
        statusUi.kind == _StatusKind.rejected &&
        (booking.rejectReason ?? '').trim().isNotEmpty;

    final isInStore = statusUi.kind == _StatusKind.inStore;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpenDetail,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${booking.firstName} ${booking.lastName}'.trim(),
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _StatusPill(ui: statusUi),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      tooltip: 'Azioni',
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'detail',
                          child: Text('Apri dettagli'),
                        ),
                        if (canReject)
                          const PopupMenuItem(
                            value: 'reject',
                            child: Text('Rifiuta'),
                          ),
                      ],
                      onSelected: (v) {
                        if (v == 'detail') onOpenDetail();
                        if (v == 'reject' && onReject != null) onReject!();
                      },
                      icon: Icon(
                        Icons.more_horiz,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Consegna: $dropoffStr',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Bags
                Text(
                  'Bagagli: ${booking.totalBags}',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (booking.bagsS > 0)
                      _MiniPill(label: 'S × ${booking.bagsS}'),
                    if (booking.bagsM > 0)
                      _MiniPill(label: 'M × ${booking.bagsM}'),
                    if (booking.bagsL > 0)
                      _MiniPill(label: 'L × ${booking.bagsL}'),
                  ],
                ),

                if (isInStore) ...[
                  const SizedBox(height: 12),
                  _InStoreReminder(
                    dropoff: booking.plannedDropoffLocal,
                    pickup: booking.plannedPickupAtLocal,
                  ),
                ],

                // Motivo rifiuto (callout bello)
                if (showRejectReason) ...[
                  const SizedBox(height: 12),
                  _Callout(
                    icon: Icons.info_outline,
                    text: 'Motivo: ${booking.rejectReason!.trim()}',
                    tone: _CalloutTone.danger,
                  ),
                ],

                // Note
                if ((booking.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Callout(
                    icon: Icons.sticky_note_2_outlined,
                    text: booking.notes!.trim(),
                    tone: _CalloutTone.neutral,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
    if (st == 'rejected') {
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
        st == 'cancelled_by_partner') {
      return _StatusUI(
        kind: _StatusKind.cancelled,
        label: 'Annullata',
        bg: Colors.grey.withOpacity(0.14),
        fg: Colors.grey.shade800,
        icon: Icons.cancel_outlined,
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

    // ✅ Confermata in tema BagDrop (viola)
    return _StatusUI(
      kind: _StatusKind.confirmed,
      label: 'Confermata',
      bg: AppTheme.brandPurple.withOpacity(0.14),
      fg: AppTheme.brandPurple,
      icon: Icons.verified_outlined,
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
                onTap: onClear, // ✅ pulisce senza aprire il menu
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
  final String text;
  final _CalloutTone tone;

  const _Callout({required this.icon, required this.text, required this.tone});

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
            child: Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipMini extends StatelessWidget {
  final String label;
  final Color color;

  const _ChipMini({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: tt.labelSmall),
    );
  }
}

class _InStoreReminder extends StatelessWidget {
  final DateTime dropoff;
  final DateTime pickup;

  const _InStoreReminder({required this.dropoff, required this.pickup});

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    const tolerance = Duration(minutes: 15);
    final deadline = pickup.add(tolerance);

    final diffToPickup = pickup.difference(now);
    final diffToDeadline = deadline.difference(now);

    final bool beforePickup = diffToPickup > Duration.zero;
    final bool inTolerance = !beforePickup && diffToDeadline > Duration.zero;

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
              : _formatCountdown(deadline.difference(now)));

    final String note = beforePickup
        ? 'Ricorda di fare il check-out entro l’orario previsto.'
        : (inTolerance
              ? 'Se il cliente fa il check-out entro la tolleranza, non dovrebbe esserci sovrapprezzo.'
              : '⚠️ Oltre la tolleranza: potrebbe essere richiesto un sovrapprezzo al check-out.');

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
}
