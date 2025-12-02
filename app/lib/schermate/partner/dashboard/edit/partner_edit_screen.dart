import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';

import 'package:flutter/services.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';

/// Schermata per permettere al Partner di modificare la scheda del locale:
/// - nome / indirizzo
/// - descrizione breve
/// - telefono
/// - regole deposito
/// - orari di apertura (JSON settimanale + eccezioni in opening_hours)
/// - capacità massima per taglia (S/M/L) + totale (derivato)
/// - prezzi
/// - stato disponibilità (attivo / sospeso)
class PartnerEditScreen extends StatefulWidget {
  const PartnerEditScreen({super.key});

  @override
  State<PartnerEditScreen> createState() => _PartnerEditScreenState();
}

//modello locale di orari

class OpeningInterval {
  final TimeOfDay open;
  final TimeOfDay close;

  OpeningInterval({required this.open, required this.close});

  OpeningInterval copyWith({TimeOfDay? open, TimeOfDay? close}) {
    return OpeningInterval(open: open ?? this.open, close: close ?? this.close);
  }

  Map<String, dynamic> toJson() => {
    "open":
        "${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}",
    "close":
        "${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}",
  };

  static OpeningInterval? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    TimeOfDay parse(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return OpeningInterval(
      open: parse(json['open']),
      close: parse(json['close']),
    );
  }
}

//editor orari

class OpeningHoursEditor extends StatefulWidget {
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const OpeningHoursEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<OpeningHoursEditor> createState() => _OpeningHoursEditorState();
}

class _OpeningHoursEditorState extends State<OpeningHoursEditor> {
  // Per ogni giorno: orario mattina (open/close) e pomeriggio (open/close)
  late Map<String, TimeOfDay?> _morningOpen;
  late Map<String, TimeOfDay?> _morningClose;
  late Map<String, TimeOfDay?> _afternoonOpen;
  late Map<String, TimeOfDay?> _afternoonClose;

  static const days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  static const labels = {
    "mon": "Lunedì",
    "tue": "Martedì",
    "wed": "Mercoledì",
    "thu": "Giovedì",
    "fri": "Venerdì",
    "sat": "Sabato",
    "sun": "Domenica",
  };

  @override
  void initState() {
    super.initState();
    _morningOpen = {};
    _morningClose = {};
    _afternoonOpen = {};
    _afternoonClose = {};

    for (final d in days) {
      _morningOpen[d] = null;
      _morningClose[d] = null;
      _afternoonOpen[d] = null;
      _afternoonClose[d] = null;

      final list = widget.initialValue?[d] as List<dynamic>? ?? [];

      // Primo intervallo -> mattina
      if (list.isNotEmpty) {
        final m = list[0] as Map<String, dynamic>;
        _morningOpen[d] = _parseTime(m['open'] as String?);
        _morningClose[d] = _parseTime(m['close'] as String?);
      }

      // Secondo intervallo -> pomeriggio
      if (list.length > 1) {
        final p = list[1] as Map<String, dynamic>;
        _afternoonOpen[d] = _parseTime(p['open'] as String?);
        _afternoonClose[d] = _parseTime(p['close'] as String?);
      }
    }
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _timeToString(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _timeToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool _isStrictBefore(TimeOfDay a, TimeOfDay b) =>
      _timeToMinutes(a) < _timeToMinutes(b);

  /// Serializza in formato:
  /// mon: [ {open:"HH:MM", close:"HH:MM"}, { ... } ]
  Map<String, dynamic> _serialize() {
    final map = <String, dynamic>{};

    for (final d in days) {
      final intervals = <Map<String, dynamic>>[];

      final mo = _morningOpen[d];
      final mc = _morningClose[d];
      if (mo != null && mc != null) {
        intervals.add({
          'open': _timeToString(mo),
          'close': _timeToString(mc),
        });
      }

      final ao = _afternoonOpen[d];
      final ac = _afternoonClose[d];
      if (ao != null && ac != null) {
        intervals.add({
          'open': _timeToString(ao),
          'close': _timeToString(ac),
        });
      }

      map[d] = intervals;
    }

    return map;
  }

  Future<void> _pickTime(
    String day, {
    required bool morning,
    required bool isOpen,
  }) async {
    // Stato corrente
    final currentOpen =
        morning ? _morningOpen[day] : _afternoonOpen[day];
    final currentClose =
        morning ? _morningClose[day] : _afternoonClose[day];

    // Orario iniziale per il picker
    final initial = isOpen
        ? (currentOpen ?? const TimeOfDay(hour: 9, minute: 0))
        : (currentClose ??
            currentOpen ??
            const TimeOfDay(hour: 9, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;

    // Logica per apertura
    if (isOpen) {
      // Se esiste già una chiusura, apertura deve essere < chiusura
      if (currentClose != null && !_isStrictBefore(picked, currentClose)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'L\'ora di apertura deve essere precedente all\'ora di chiusura.',
            ),
          ),
        );
        return;
      }

      setState(() {
        if (morning) {
          _morningOpen[day] = picked;
        } else {
          _afternoonOpen[day] = picked;
        }
      });
    } else {
      // Logica per chiusura
      if (currentOpen == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imposta prima l\'orario di apertura.'),
          ),
        );
        return;
      }

      if (!_isStrictBefore(currentOpen, picked)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'L\'ora di chiusura deve essere successiva a quella di apertura.',
            ),
          ),
        );
        return;
      }

      setState(() {
        if (morning) {
          _morningClose[day] = picked;
        } else {
          _afternoonClose[day] = picked;
        }
      });
    }

    widget.onChanged(_serialize());
  }

  void _clearInterval(String day, {required bool morning}) {
    setState(() {
      if (morning) {
        _morningOpen[day] = null;
        _morningClose[day] = null;
      } else {
        _afternoonOpen[day] = null;
        _afternoonClose[day] = null;
      }
    });
    widget.onChanged(_serialize());
  }

  void _copyToAll(String day) {
    final mo = _morningOpen[day];
    final mc = _morningClose[day];
    final ao = _afternoonOpen[day];
    final ac = _afternoonClose[day];

    setState(() {
      for (final d in days) {
        if (d == day) continue;
        _morningOpen[d] = mo;
        _morningClose[d] = mc;
        _afternoonOpen[d] = ao;
        _afternoonClose[d] = ac;
      }
    });
    widget.onChanged(_serialize());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...days.map((day) {
          final mo = _morningOpen[day];
          final mc = _morningClose[day];
          final ao = _afternoonOpen[day];
          final ac = _afternoonClose[day];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // intestazione giorno + copia
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[day]!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        tooltip: "Copia su tutti i giorni",
                        onPressed: (mo == null &&
                                mc == null &&
                                ao == null &&
                                ac == null)
                            ? null
                            : () => _copyToAll(day),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Mattina
                  Text(
                    'Mattina',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(
                            day,
                            morning: true,
                            isOpen: true,
                          ),
                          child: Text(
                            mo == null
                                ? 'Ora apertura'
                                : 'Apre: ${mo.format(context)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: mo == null
                              ? null
                              : () => _pickTime(
                                    day,
                                    morning: true,
                                    isOpen: false,
                                  ),
                          child: Text(
                            mc == null
                                ? 'Ora chiusura'
                                : 'Chiude: ${mc.format(context)}',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Rimuovi fascia mattina',
                        onPressed: (mo == null && mc == null)
                            ? null
                            : () => _clearInterval(day, morning: true),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Pomeriggio
                  Text(
                    'Pomeriggio (opzionale)',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(
                            day,
                            morning: false,
                            isOpen: true,
                          ),
                          child: Text(
                            ao == null
                                ? 'Ora apertura'
                                : 'Apre: ${ao.format(context)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: ao == null
                              ? null
                              : () => _pickTime(
                                    day,
                                    morning: false,
                                    isOpen: false,
                                  ),
                          child: Text(
                            ac == null
                                ? 'Ora chiusura'
                                : 'Chiude: ${ac.format(context)}',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Rimuovi fascia pomeriggio',
                        onPressed: (ao == null && ac == null)
                            ? null
                            : () => _clearInterval(day, morning: false),
                      ),
                    ],
                  ),

                  if (mo == null &&
                      mc == null &&
                      ao == null &&
                      ac == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Se non imposti nessuna fascia il locale risulta chiuso in questo giorno.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}


class OpeningExceptionsEditor extends StatefulWidget {
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const OpeningExceptionsEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<OpeningExceptionsEditor> createState() =>
      _OpeningExceptionsEditorState();
}

class _OpeningExceptionsEditorState extends State<OpeningExceptionsEditor> {
  late List<DateTime> _closedDates;
  late List<DateTime> _forcedOpenDates;

  @override
  void initState() {
    super.initState();
    _closedDates = _parseDateList(widget.initialValue?['closed_dates']);
    _forcedOpenDates = _parseDateList(
      widget.initialValue?['forced_open_dates'],
    );
  }

  List<DateTime> _parseDateList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => DateTime.tryParse(e as String? ?? ''))
          .whereType<DateTime>()
          .toList()
        ..sort();
    }
    return [];
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString().padLeft(4, '0');
    return '$dd/$mm/$yyyy';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _notify() {
    if (_closedDates.isEmpty && _forcedOpenDates.isEmpty) {
      widget.onChanged(null);
    } else {
      widget.onChanged({
        'closed_dates': _closedDates
            .map((d) => d.toIso8601String().substring(0, 10))
            .toList(),
        'forced_open_dates': _forcedOpenDates
            .map((d) => d.toIso8601String().substring(0, 10))
            .toList(),
      });
    }
  }

  Future<void> _pickDate({required bool closed}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );

    if (picked == null) return;

    setState(() {
      final list = closed ? _closedDates : _forcedOpenDates;
      if (!list.any((d) => _sameDay(d, picked))) {
        list.add(picked);
        list.sort();
      }
    });

    _notify();
  }

  void _removeDate({required bool closed, required DateTime date}) {
    setState(() {
      final list = closed ? _closedDates : _forcedOpenDates;
      list.removeWhere((d) => _sameDay(d, date));
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Eccezioni calendario', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Puoi impostare giorni di chiusura straordinaria (es. festività) '
          'e giorni di apertura straordinaria (quando normalmente saresti chiuso).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),

        // CHIUSURE STRAORDINARIE
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Giorni di chiusura straordinaria',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickDate(closed: true),
                      icon: const Icon(Icons.add),
                      label: const Text('Aggiungi'),
                    ),
                  ],
                ),
                if (_closedDates.isEmpty)
                  Text(
                    'Nessuna chiusura straordinaria impostata.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ..._closedDates.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_formatDate(d)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeDate(closed: true, date: d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // APERTURE STRAORDINARIE
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Giorni di apertura straordinaria',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickDate(closed: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Aggiungi'),
                    ),
                  ],
                ),
                if (_forcedOpenDates.isEmpty)
                  Text(
                    'Nessuna apertura straordinaria impostata.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ..._forcedOpenDates.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_formatDate(d)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeDate(closed: false, date: d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PartnerEditScreenState extends State<PartnerEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _repo = PartnerRepo(Supabase.instance.client);

  Partner? _partner;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Controller dei campi testo
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();

  // Capacità per taglia
  final _capacitySCtrl = TextEditingController();
  final _capacityMCtrl = TextEditingController();
  final _capacityLCtrl = TextEditingController();

  final _price2hCtrl = TextEditingController();
  final _pricePerDayCtrl = TextEditingController();

  Map<String, dynamic>? _openingHoursStructured;
  Map<String, dynamic>? _openingExceptions;
  bool _isActive = true;
  bool _hasFutureBookings = false;

  /// Normalizza opening_hours in formato settimanale:
  /// - se è null → 08:00-20:00 tutti i giorni
  /// - se è 'daily_with_break' → stessi intervalli ogni giorno
  /// - se è 'weekly_v1' → lo lascia com'è
  /// - se è legacy (mon/tue/... senza type) → lo usa direttamente
  Map<String, dynamic> _normalizeOpeningWeekly(Map<String, dynamic>? raw) {
    const dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

    // Base: tutte le giornate "chiuse" (liste vuote)
    final result = <String, dynamic>{
      for (final d in dayKeys) d: <Map<String, dynamic>>[],
    };

    // Nessun dato -> fallback 08:00-20:00 tutti i giorni
    if (raw == null) {
      final def = OpeningInterval(
        open: const TimeOfDay(hour: 8, minute: 0),
        close: const TimeOfDay(hour: 20, minute: 0),
      ).toJson();
      for (final d in dayKeys) {
        result[d] = [def];
      }
      return result;
    }

    final type = raw['type'] as String?;

    // Già weekly_v1
    if (type == 'weekly_v1') {
      for (final d in dayKeys) {
        final list = raw[d] as List<dynamic>? ?? [];
        result[d] = list.map((e) => e as Map<String, dynamic>).toList();
      }
      return result;
    }

    // Vecchio formato daily_with_break
    if (type == 'daily_with_break') {
      final String? o1 = raw['open_1'] as String?;
      final String? c1 = raw['close_1'] as String?;
      final String? o2 = raw['open_2'] as String?;
      final String? c2 = raw['close_2'] as String?;

      final intervals = <Map<String, dynamic>>[];
      if (o1 != null && c1 != null) {
        intervals.add({'open': o1, 'close': c1});
      }
      if (o2 != null && c2 != null) {
        intervals.add({'open': o2, 'close': c2});
      }

      if (intervals.isEmpty) {
        // Nessun orario -> tutti chiusi
        return result;
      }

      for (final d in dayKeys) {
        result[d] = List<Map<String, dynamic>>.from(intervals);
      }
      return result;
    }

    // Caso legacy: trattiamo raw come weekly senza 'type'
    for (final d in dayKeys) {
      final list = raw[d] as List<dynamic>? ?? [];
      result[d] = list.map((e) => e as Map<String, dynamic>).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _rulesCtrl.dispose();
    _capacitySCtrl.dispose();
    _capacityMCtrl.dispose();
    _capacityLCtrl.dispose();
    _price2hCtrl.dispose();
    _pricePerDayCtrl.dispose();
    super.dispose();
  }

  /// Carica il partner associato all'utente corrente
  /// e popola i campi del form.
  Future<void> _loadPartner() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final partner = await _repo.getMyPartner();

      if (!mounted) return;

      if (partner == null) {
        setState(() {
          _loading = false;
          _partner = null;
          _error = 'Nessun locale associato a questo account.';
        });
        return;
      }

      _partner = partner;

      _nameCtrl.text = partner.name;
      _addressCtrl.text = partner.address ?? '';
      _descCtrl.text = partner.description ?? '';
      _phoneCtrl.text = partner.phone ?? '';
      _rulesCtrl.text = partner.rules ?? '';

      // Capacità S/M/L con fallback su capacity totale
      int capS = partner.capacityS;
      int capM = partner.capacityM;
      int capL = partner.capacityL;

      if (capS == 0 && capM == 0 && capL == 0 && partner.capacity > 0) {
        capM = partner.capacity;
      }

      _capacitySCtrl.text = capS.toString();
      _capacityMCtrl.text = capM.toString();
      _capacityLCtrl.text = capL.toString();

      if (partner.price2h != null) {
        _price2hCtrl.text = partner.price2h!
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }
      if (partner.pricePerDay != null) {
        _pricePerDayCtrl.text = partner.pricePerDay!
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }

      // Orari di apertura settimanali (weekly)
      _openingHoursStructured = _normalizeOpeningWeekly(partner.openingHours);

      // NUOVO: eccezioni calendario (se presenti nel JSON)
      final rawOpening = partner.openingHours;
      if (rawOpening != null &&
          rawOpening['exceptions'] is Map<String, dynamic>) {
        _openingExceptions = Map<String, dynamic>.from(
          rawOpening['exceptions'] as Map,
        );
      } else {
        _openingExceptions = null;
      }

      _isActive = partner.isActive;

      // Controllo se ci sono prenotazioni future
      final bookingRepo = PartnerBookingRepo(Supabase.instance.client);
      final hasFuture = await bookingRepo.hasActiveFutureBookingsForPartner(
        partner.id,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = null;
        _hasFutureBookings = hasFuture;
      });
    } catch (e, st) {
      debugPrint('Errore _loadPartner: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore durante il caricamento del locale.';
      });
    }
  }

  /// Converte una stringa in double, gestendo anche la virgola.
  double? _parsePrice(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final normalized = t.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  /// Salva le modifiche su Supabase usando PartnerRepo.updateBasics.
  Future<void> _save() async {
    if (_partner == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sText = _capacitySCtrl.text.trim();
    final mText = _capacityMCtrl.text.trim();
    final lText = _capacityLCtrl.text.trim();

    final capS = int.tryParse(sText) ?? 0;
    final capM = int.tryParse(mText) ?? 0;
    final capL = int.tryParse(lText) ?? 0;

    if (capS < 0 || capM < 0 || capL < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le capacità devono essere numeri ≥ 0.')),
      );
      return;
    }

    final totalCapacity = capS + capM + capL;
    if (totalCapacity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imposta almeno 1 posto totale tra S / M / L.'),
        ),
      );
      return;
    }

    final price2h = _parsePrice(_price2hCtrl.text);
    final pricePerDay = _parsePrice(_pricePerDayCtrl.text);

    // Orari di apertura settimanali (weekly_v1)
    Map<String, dynamic>? openingHours;
    if (_openingHoursStructured != null) {
      openingHours = {
        'type': 'weekly_v1',
        ..._openingHoursStructured!,
        if (_openingExceptions != null) 'exceptions': _openingExceptions,
      };
    }
    final canEditCapacityAndHours = !_hasFutureBookings;

    setState(() {
      _saving = true;
    });

    try {
      await _repo.updateBasics(
        partnerId: _partner!.id,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        capacity: canEditCapacityAndHours ? totalCapacity : null,
        capacityS: canEditCapacityAndHours ? capS : null,
        capacityM: canEditCapacityAndHours ? capM : null,
        capacityL: canEditCapacityAndHours ? capL : null,
        price2h: price2h,
        pricePerDay: pricePerDay,
        isActive: _isActive,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        rules: _rulesCtrl.text.trim().isEmpty ? null : _rulesCtrl.text.trim(),
        openingHours: canEditCapacityAndHours ? openingHours : null,
      );

      if (!mounted) return;

      if (_hasFutureBookings) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dati salvati. Orari e capacità non sono stati modificati perché ci sono prenotazioni future.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scheda locale aggiornata.')),
        );
      }

      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint('Errore salvataggio partner: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante il salvataggio. Riprova.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifica locale')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_partner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifica locale')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error ??
                  'Nessun locale trovato. Completa prima la registrazione dell’attività.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Modifica locale')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1) Nome attività
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome attività',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci il nome dell’attività';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // 2) Indirizzo
                TextFormField(
                  controller: _addressCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo',
                    hintText: 'Via / Piazza, numero civico, città',
                    border: OutlineInputBorder(),
                    helperText:
                        'Per modificare l\'indirizzo contatta il supporto BagDrop via email.',
                  ),
                  onTap: () {
                    // Messaggio veloce: l’indirizzo non è modificabile da qui
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Per modificare l\'indirizzo del locale scrivi a support@bagdrop.app',
                        ),
                      ),
                    );
                  },
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Indirizzo non disponibile: contatta il supporto.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),
                Text(
                  'Vuoi aggiornare l\'indirizzo del locale?\n'
                  'Scrivi a support@bagdrop.app indicando il nuovo indirizzo.',
                  style: theme.textTheme.bodySmall,
                ),

                const SizedBox(height: 12),

                // 3) Descrizione breve
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrizione breve',
                    hintText:
                        'Es. Bar accogliente vicino al Duomo, deposito sicuro...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 4) Telefono
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    hintText: 'Es. +39 333 1234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),

                // 5) Regole deposito
                TextFormField(
                  controller: _rulesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Regole deposito',
                    hintText:
                        'Es. Max 25kg a bagaglio, no oggetti di valore, no liquidi...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 6) Orari di apertura settimanali + eccezioni
                Text('Orari di apertura', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),

                Text(
                  'Imposta gli orari per ogni giorno della settimana.\n'
                  'Se fai orario continuato inserisci solo la prima fascia (mattina).\n'
                  'Più sotto puoi aggiungere giorni di chiusura/apertura straordinaria (es. Natale).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),

                if (_hasFutureBookings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Ci sono prenotazioni future: non puoi modificare orari, capacità e '
                      'eccezioni calendario finché non saranno concluse.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),

                IgnorePointer(
                  ignoring: _hasFutureBookings,
                  child: Opacity(
                    opacity: _hasFutureBookings ? 0.6 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OpeningHoursEditor(
                          initialValue: _openingHoursStructured,
                          onChanged: (value) {
                            setState(() {
                              _openingHoursStructured = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        OpeningExceptionsEditor(
                          initialValue: _openingExceptions,
                          onChanged: (value) {
                            setState(() {
                              _openingExceptions = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 7) Capacità per taglia
                Text(
                  'Capacità massima per taglia bagagli',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacitySCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli SMALL (S)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacityMCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli MEDIUM (M)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacityLCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli LARGE (L)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 12),

                // 8) Prezzi
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price2hCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Prezzo 2h (€)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pricePerDayCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Prezzo / giorno (€)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 9) Stato disponibilità
                SwitchListTile(
                  title: const Text('Locale attivo su BagDrop'),
                  subtitle: const Text(
                    'Disattiva per sospendere temporaneamente le prenotazioni.',
                  ),
                  value: _isActive,
                  onChanged: (v) {
                    setState(() {
                      _isActive = v;
                    });
                  },
                ),

                const SizedBox(height: 16),
                Text(
                  'Queste informazioni saranno visibili agli utenti nella scheda del locale (mappa + dettaglio).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salva modifiche'),
            ),
          ),
        ),
      ),
    );
  }
}
