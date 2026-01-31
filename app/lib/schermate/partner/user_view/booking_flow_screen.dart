// è la pagina che vede l'utente cliccando il tasto prenota ora dalla scheda dell'attività
import 'package:BagDrop/schermate/partner/dashboard/pages/bagdrop_pricing_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:flutter/cupertino.dart';

class BookingFlowScreen extends StatefulWidget {
  final Partner partner;

  const BookingFlowScreen({super.key, required this.partner});

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final _formContactKey = GlobalKey<FormState>();

  // Step corrente:
  // 0 = contatto
  // 1 = data + orario
  // 2 = bagagli
  // 3 = riepilogo
  int _step = 0;
  bool _busy = false;
  // 0 = +3 ore, 1 = tutto il giorno
  int? _selectedPresetIndex;
  int _plusDaysPreset = 0;

  // CONTATTO
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // DATA / ORARIO
  /// Giorno di consegna bagagli
  DateTime? _selectedDate;

  /// Giorno di ritiro bagagli
  DateTime? _endDate;

  /// Orario di consegna
  TimeOfDay? _startTime;

  /// Orario di ritiro
  TimeOfDay? _endTime;

  // End effettivo (scadenza fascia) - quello che salveremo a DB
  DateTime? _effectiveEndDate;
  TimeOfDay? _effectiveEndTime;

  // per debug/UI
  BagDropPricingInterval? _normalizedPricingInterval;

  /// Orari di apertura settimanali normalizzati.
  /// Per ogni giorno (mon..sun) abbiamo una lista di intervalli {open, close} "HH:MM".
  late Map<String, List<Map<String, dynamic>>> _weeklyHours;

  /// Eccezioni calendario: chiusure / aperture straordinarie per date specifiche.
  /// Le chiavi sono stringhe "YYYY-MM-DD".
  Set<String> _closedDateKeys = {};
  Set<String> _forcedOpenDateKeys = {};

  PartnerAvailability? _availability;
  bool _loadingAvailability = false;

  // BAGAGLI
  int _bagsS = 0;
  int _bagsM = 0;
  int _bagsL = 0;

  /// Unità equivalenti in "mezze M":
  /// 1S = 1, 1M = 2, 1L = 4
  int _equivalentUnits2x({required int s, required int m, required int l}) {
    return s * 1 + m * 2 + l * 4;
  }

  int _currentRequestedUnits2x() =>
      _equivalentUnits2x(s: _bagsS, m: _bagsM, l: _bagsL);

  String _weekdayKey(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
        return 'fri';
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
      default:
        return 'sun';
    }
  }

  @override
  void initState() {
    super.initState();

    // Data di default = oggi (l’utente può cambiarla con il date picker).
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    // Orario di default = ora attuale (usato solo per la modalità "3 ore").
    _startTime = TimeOfDay.fromDateTime(now);
    // Normalizza opening_hours (weekly_v1 / legacy) + eccezioni calendario
    _initOpeningHours();
    // 🔹 Prefill dati contatto dall'utente loggato (metadata Supabase)
    _prefillContactFromCurrentUser();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Converte un TimeOfDay in minuti da mezzanotte (utile per confronti).
  int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Prima apertura del giorno corrente (_selectedDate) in base a weekly + eccezioni.
  /// - se la data è chiusa (weekly vuoto + non forced_open, oppure closed_dates) → null
  /// - se è apertura straordinaria su giorno normalmente chiuso → 00:00
  TimeOfDay? get _firstOpenTime {
    if (_selectedDate == null) return null;

    final date = _selectedDate!;
    final dateKey = _dateKey(date);

    // Chiusura straordinaria → nessuna apertura
    if (_closedDateKeys.contains(dateKey)) {
      return null;
    }

    final dayKey = _weekdayKey(date.weekday);
    final list = _weeklyHours[dayKey] ?? const <Map<String, dynamic>>[];

    // Giorno normalmente chiuso e non forzato aperto → nessuna apertura
    if (list.isEmpty && !_forcedOpenDateKeys.contains(dateKey)) {
      return null;
    }

    // Giorno normalmente chiuso ma apertura straordinaria → aperto tutto il giorno
    if (list.isEmpty && _forcedOpenDateKeys.contains(dateKey)) {
      return const TimeOfDay(hour: 0, minute: 0);
    }

    // Prendiamo l'apertura più precoce tra gli intervalli
    TimeOfDay? best;
    for (final m in list) {
      final t = _parseTimeOfDay(m['open'] as String?);
      if (t == null) continue;
      if (best == null || _timeOfDayToMinutes(t) < _timeOfDayToMinutes(best)) {
        best = t;
      }
    }
    return best;
  }

  /// Ultima chiusura del giorno corrente (_selectedDate) in base a weekly + eccezioni.
  /// - se la data è chiusa → null
  /// - se è apertura straordinaria su giorno normalmente chiuso → 23:59
  TimeOfDay? get _lastCloseTime {
    if (_selectedDate == null) return null;

    final date = _selectedDate!;
    final dateKey = _dateKey(date);

    if (_closedDateKeys.contains(dateKey)) {
      return null;
    }

    final dayKey = _weekdayKey(date.weekday);
    final list = _weeklyHours[dayKey] ?? const <Map<String, dynamic>>[];

    if (list.isEmpty && !_forcedOpenDateKeys.contains(dateKey)) {
      return null;
    }

    if (list.isEmpty && _forcedOpenDateKeys.contains(dateKey)) {
      return const TimeOfDay(hour: 23, minute: 59);
    }

    TimeOfDay? best;
    for (final m in list) {
      final t = _parseTimeOfDay(m['close'] as String?);
      if (t == null) continue;
      if (best == null || _timeOfDayToMinutes(t) > _timeOfDayToMinutes(best)) {
        best = t;
      }
    }
    return best;
  }

  /// Ritorna true se per quella data, in base a weekly_v1 + eccezioni,
  /// il locale è chiuso (nessun intervallo per quel giorno).
  bool _isClosedDay(DateTime date) {
    final keyDate = _dateKey(date);

    // Chiusura straordinaria ha precedenza
    if (_closedDateKeys.contains(keyDate)) {
      return true;
    }

    // Apertura straordinaria ha precedenza su weekly chiuso
    if (_forcedOpenDateKeys.contains(keyDate)) {
      return false;
    }

    final dayKey = _weekdayKey(date.weekday);
    final list = _weeklyHours[dayKey] ?? const <Map<String, dynamic>>[];

    return list.isEmpty;
  }

  TimeOfDay? _lastCloseTimeForDate(DateTime date) {
    final dateKey = _dateKey(date);

    if (_closedDateKeys.contains(dateKey)) return null;

    final dayKey = _weekdayKey(date.weekday);
    final list = _weeklyHours[dayKey] ?? const <Map<String, dynamic>>[];

    if (list.isEmpty && !_forcedOpenDateKeys.contains(dateKey)) return null;
    if (list.isEmpty && _forcedOpenDateKeys.contains(dateKey)) {
      return const TimeOfDay(hour: 23, minute: 59);
    }

    TimeOfDay? best;
    for (final m in list) {
      final t = _parseTimeOfDay(m['close'] as String?);
      if (t == null) continue;
      if (best == null || _timeOfDayToMinutes(t) > _timeOfDayToMinutes(best)) {
        best = t;
      }
    }
    return best;
  }

  DateTime? _closeDateTimeForDay(DateTime day) {
    final close = _lastCloseTimeForDate(day);
    if (close == null) return null;
    return DateTime(day.year, day.month, day.day, close.hour, close.minute);
  }

  /// Ritorna true se l'orario [time] per la data [date]
  /// rientra in almeno uno degli intervalli di apertura del locale.
  ///
  /// - tiene conto di weekly_v1
  /// - tiene conto di eccezioni (closed_dates / forced_open_dates)
  bool _isTimeWithinOpeningHours(DateTime date, TimeOfDay time) {
    final dateKey = _dateKey(date);

    // Se la data è marcata come chiusa → sempre false
    if (_closedDateKeys.contains(dateKey)) {
      return false;
    }

    final dayKey = _weekdayKey(date.weekday);
    final list = _weeklyHours[dayKey] ?? const <Map<String, dynamic>>[];

    // Giorno normalmente chiuso ma apertura straordinaria → consideriamo aperto tutto il giorno
    if (list.isEmpty && _forcedOpenDateKeys.contains(dateKey)) {
      return true; // qualsiasi orario è ok quel giorno
    }

    // Giorno chiuso (nessun intervallo e nessuna apertura straordinaria)
    if (list.isEmpty) {
      return false;
    }

    final minutes = _timeOfDayToMinutes(time);

    for (final m in list) {
      final openT = _parseTimeOfDay(m['open'] as String?);
      final closeT = _parseTimeOfDay(m['close'] as String?);
      if (openT == null || closeT == null) continue;

      final openMin = _timeOfDayToMinutes(openT);
      final closeMin = _timeOfDayToMinutes(closeT);

      // Intervallo chiuso [open, close]
      if (minutes >= openMin && minutes <= closeMin) {
        return true;
      }
    }

    return false;
  }

  /// Valida la combinazione data/orario di consegna e ritiro.
  ///
  /// Ritorna:
  /// - null  → tutto ok
  /// - testo → messaggio di errore da mostrare
  String? _validateDateTimeSelection() {
    if (_selectedDate == null ||
        _startTime == null ||
        _endDate == null ||
        _endTime == null) {
      return 'Seleziona giorno e orario di consegna e di ritiro.';
    }

    final startDt = _startDateTime;
    final endDtRequested = _endDateTime;

    if (startDt == null || endDtRequested == null) {
      return 'Seleziona giorno e orario di consegna e di ritiro.';
    }

    final startDateOnly = DateTime(startDt.year, startDt.month, startDt.day);
    final endReqDateOnly = DateTime(
      endDtRequested.year,
      endDtRequested.month,
      endDtRequested.day,
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final in7Days = today.add(const Duration(days: 7));

    // ❌ Niente date nel passato (giorno di consegna)
    if (startDateOnly.isBefore(today)) {
      return 'La data di consegna è nel passato.';
    }

    // ❌ Niente consegne oltre 7 giorni
    if (startDateOnly.isAfter(in7Days)) {
      return 'Puoi prenotare al massimo entro 7 giorni da oggi.';
    }

    // ❌ Orario di consegna nel passato (se consegni oggi)
    // ✅ Tolleranza: consegna oggi può essere fino a 2 minuti "nel passato"
    if (startDateOnly.isAtSameMomentAs(today)) {
      const grace = Duration(minutes: 2);
      final limit = now.subtract(grace);

      // vietato solo se è più vecchio di 2 minuti
      if (startDt.isBefore(limit)) {
        return 'L\'orario di consegna non può essere nel passato (tolleranza 2 minuti).';
      }
    }

    // ❌ Requested end deve essere dopo start
    if (!startDt.isBefore(endDtRequested)) {
      return 'L\'orario di ritiro deve essere successivo a quello di consegna.';
    }

    // ❌ Giorno consegna chiuso
    if (_isClosedDay(startDateOnly)) {
      return 'Nel giorno di consegna il locale è chiuso. Scegli un\'altra data.';
    }

    // ❌ Orario consegna dentro apertura
    if (!_isTimeWithinOpeningHours(startDateOnly, _startTime!)) {
      return 'L\'orario di consegna è fuori dagli orari di apertura del locale.';
    }

    // ❌ Requested end: giorno/orario dentro apertura (l’utente non può scegliere un ritiro impossibile)
    if (_isClosedDay(endReqDateOnly)) {
      return 'Nel giorno di ritiro il locale è chiuso. Scegli un\'altra data.';
    }
    if (!_isTimeWithinOpeningHours(endReqDateOnly, _endTime!)) {
      return 'L\'orario di ritiro è fuori dagli orari di apertura del locale.';
    }

    // Limite durata massimo 7 giorni (basato sul requested)
    final durationHours = endDtRequested.difference(startDt).inMinutes / 60.0;
    if (durationHours > 24.0 * 7) {
      return 'Per ora puoi prenotare al massimo per 7 giorni. Riduci l\'intervallo tra consegna e ritiro.';
    }

    // ✅ NORMALIZZAZIONE FASCIA: calcolo scadenza effettiva (effective end)
    final normalized =
        _normalizedPricingInterval ??
        BagDropPricing.normalizeBookingInterval(
          start: startDt,
          userEnd: endDtRequested,
          getCloseForDay: (day) {
            final dayOnly = DateTime(day.year, day.month, day.day);
            return _closeDateTimeForDay(dayOnly);
          },
        );

    final effEnd = normalized.effectiveEnd;
    final effEndDateOnly = DateTime(effEnd.year, effEnd.month, effEnd.day);
    final effEndTod = TimeOfDay(hour: effEnd.hour, minute: effEnd.minute);

    // ✅ Salviamo in stato (servirà per availability + DB + recap)
    _normalizedPricingInterval = normalized;
    _effectiveEndDate = effEndDateOnly;
    _effectiveEndTime = effEndTod;

    return null;
  }

  /// Normalizza opening_hours in formato settimanale:
  /// - se è null → 08:00-20:00 tutti i giorni
  /// - se è 'weekly_v1' → usa le liste mon..sun così come sono
  /// - se è 'daily_with_break' → converte open_1/close_1, open_2/close_2 per tutti i giorni
  /// - se è legacy (mon/tue/... senza type) → lo usa direttamente
  Map<String, List<Map<String, dynamic>>> _normalizeOpeningWeekly(
    Map<String, dynamic>? raw,
  ) {
    const dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

    final result = <String, List<Map<String, dynamic>>>{
      for (final d in dayKeys) d: <Map<String, dynamic>>[],
    };

    // Nessun dato -> fallback 08:00-20:00 tutti i giorni
    if (raw == null) {
      final def = {"open": "08:00", "close": "20:00"};
      for (final d in dayKeys) {
        result[d] = [Map<String, dynamic>.from(def)];
      }
      return result;
    }

    final type = raw['type'] as String?;

    // Già weekly_v1
    if (type == 'weekly_v1') {
      for (final d in dayKeys) {
        final list = raw[d] as List<dynamic>? ?? [];
        result[d] = list
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
      }
      return result;
    }

    // Vecchio formato daily_with_break → convertito in intervalli per tutti i giorni
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
        result[d] = intervals.map((i) => Map<String, dynamic>.from(i)).toList();
      }
      return result;
    }

    // Caso legacy: trattiamo raw come weekly senza 'type'
    for (final d in dayKeys) {
      final list = raw[d] as List<dynamic>? ?? [];
      result[d] = list
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    }
    return result;
  }

  /// Chiave "YYYY-MM-DD" per confrontare le date nelle eccezioni.
  String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Inizializza _weeklyHours e le eccezioni (chiusure/aperture straordinarie).
  void _initOpeningHours() {
    final opening = widget.partner.openingHours;

    if (opening is Map<String, dynamic>) {
      _weeklyHours = _normalizeOpeningWeekly(opening);

      _closedDateKeys = {};
      _forcedOpenDateKeys = {};

      final ex = opening['exceptions'];
      if (ex is Map<String, dynamic>) {
        final rawClosed = ex['closed_dates'];
        if (rawClosed is List) {
          _closedDateKeys = rawClosed
              .map((e) => e.toString())
              .where((s) => s.length >= 10)
              .map((s) => s.substring(0, 10))
              .toSet();
        }

        final rawForced = ex['forced_open_dates'];
        if (rawForced is List) {
          _forcedOpenDateKeys = rawForced
              .map((e) => e.toString())
              .where((s) => s.length >= 10)
              .map((s) => s.substring(0, 10))
              .toSet();
        }
      }
    } else {
      // Nessun opening_hours sul partner → fallback 08-20 tutti i giorni, nessuna eccezione
      _weeklyHours = _normalizeOpeningWeekly(null);
      _closedDateKeys = {};
      _forcedOpenDateKeys = {};
    }
  }

  Future<void> _nextStep() async {
    if (_step == 0) {
      // Step 0 → 1: validazione form contatto
      if (!(_formContactKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Step 1 → 2: data + orario

      final error = _validateDateTimeSelection();
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        return;
      }

      // Se tutto ok, carichiamo la disponibilità per data + orario scelti.
      await _loadAvailabilityForSelection();
      if (!mounted) return;
      if (_availability == null) {
        // eventuali errori sono già stati gestiti in _loadAvailabilityForSelection
        return;
      }

      setState(() => _step = 2);
    } else if (_step == 2) {
      // Step 2 → 3: bagagli
      if (_bagsS + _bagsM + _bagsL <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno un bagaglio.')),
        );
        return;
      }
      setState(() => _step = 3);
    }
  }

  BagDropPricingInterval? get _pricingIntervalLive {
    final start = _startDateTime;
    final userEnd = _endDateTime;
    if (start == null || userEnd == null) return null;

    return BagDropPricing.normalizeBookingInterval(
      start: start,
      userEnd: userEnd,
      getCloseForDay: (day) {
        final dayOnly = DateTime(day.year, day.month, day.day);
        return _closeDateTimeForDay(dayOnly);
      },
    );
  }

  int get _extraDaysLive => _pricingIntervalLive?.extraDays ?? 0;

  BagDropDuration? get _durationLive => _pricingIntervalLive?.duration;

  double _priceBaseNoExtra() {
    final it = _pricingIntervalLive;
    if (it == null) return 0.0;
    return BagDropPricing.totalFor(
      duration: it.duration,
      extraDays: 0,
      bagsS: _bagsS,
      bagsM: _bagsM,
      bagsL: _bagsL,
    );
  }

  double _priceExtraDaysOnly() {
    final it = _pricingIntervalLive;
    if (it == null) return 0.0;
    final bagCount = _bagsS + _bagsM + _bagsL;
    if (it.duration != BagDropDuration.threeDays || it.extraDays <= 0)
      return 0.0;
    return it.extraDays * 2.0 * bagCount;
  }

  /// Data+ora di consegna effettive, oppure null se manca qualcosa.
  DateTime? get _startDateTime {
    if (_selectedDate == null || _startTime == null) return null;
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
  }

  /// Data+ora di ritiro effettive, oppure null se manca qualcosa.
  /// Se _endDate è null, usiamo _selectedDate (es. modalità 3 ore).
  DateTime? get _endDateTime {
    final endDate = _endDate ?? _selectedDate;
    if (endDate == null || _endTime == null) return null;
    return DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      _endTime!.hour,
      _endTime!.minute,
    );
  }

  /// Applica i preset rapidi:
  /// 0 → +3 ore
  /// 1 → tutto il giorno
  void _applyPreset(int index) {
    final start = _startDateTime;
    if (start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prima seleziona giorno e orario di consegna.'),
        ),
      );
      return;
    }

    DateTime end;

    if (index == 0) {
      // Preset "+3 ore"
      end = start.add(const Duration(hours: 3));
    } else if (index == 1) {
      // Preset "Tutto il giorno"
      final lastClose = _lastCloseTime;

      if (lastClose != null) {
        end = DateTime(
          start.year,
          start.month,
          start.day,
          lastClose.hour,
          lastClose.minute,
        );

        // Safety: se non è dopo l'inizio → fallback +3 ore
        if (!end.isAfter(start)) {
          end = start.add(const Duration(hours: 3));
        }
      } else {
        // Fallback: 19:00
        end = DateTime(start.year, start.month, start.day, 19, 0);
        if (!end.isAfter(start)) {
          end = start.add(const Duration(hours: 3));
        }
      }
    } else {
      // Fallback di sicurezza
      end = start.add(const Duration(hours: 3));
    }

    setState(() {
      _selectedPresetIndex = index;
      _plusDaysPreset =
          0; // ogni volta che cambio preset base azzero i giorni extra
      _endDate = DateTime(end.year, end.month, end.day);
      _endTime = TimeOfDay.fromDateTime(end);
    });
  }

  /// Clicker "+N giorni" → ogni tap aggiunge 1 giorno (max 7)
  void _applyPlusDaysPreset() {
    final start = _startDateTime;
    if (start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prima seleziona giorno e orario di consegna.'),
        ),
      );
      return;
    }

    // limite: massimo 7 giorni totali di permanenza
    if (_plusDaysPreset >= 7) {
      return;
    }

    final newPlus = _plusDaysPreset + 1;
    final end = start.add(Duration(days: newPlus));

    setState(() {
      _selectedPresetIndex = 2; // evidenzia il chip "+N giorni"
      _plusDaysPreset = newPlus; // 1, 2, 3, ... 7
      _endDate = DateTime(end.year, end.month, end.day);
      _endTime = TimeOfDay.fromDateTime(end);
    });
  }

  Future<void> _loadAvailabilityForSelection() async {
    if (_selectedDate == null ||
        _endDate == null ||
        _startTime == null ||
        _endTime == null) {
      return;
    }

    final startStr = _formatTimeForApi(_startTime!);
    final endStr = _formatTimeForApi(_endTime!);

    setState(() {
      _loadingAvailability = true;
      _availability = null;
    });

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    final bookingStartDate = _selectedDate!;

    // ✅ usa l'end effettivo (scadenza fascia) se già calcolato da _validateDateTimeSelection()
    final bookingEndDate = _effectiveEndDate ?? _endDate!;
    final endTimeForApi = _effectiveEndTime ?? _endTime!;

    try {
      final av = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: bookingStartDate,
        startDate: bookingStartDate,
        endDate: bookingEndDate,
        startTime: startStr,
        endTime: _formatTimeForApi(endTimeForApi),
      );

      if (!mounted) return;
      setState(() {
        _availability = av;
        _loadingAvailability = false;
      });
    } catch (e, st) {
      debugPrint('Errore caricando disponibilità per intervallo: $e\n$st');
      if (!mounted) return;
      setState(() {
        _availability = null;
        _loadingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossibile calcolare la disponibilità per l\'orario scelto. Riprova.',
          ),
        ),
      );
    }
  }

  String _formatTimeForApi(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatTimeDisplay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  //helper pickers (iOS bottom sheet)

  Future<DateTime?> _pickDateIOS({
    required String title,
    required DateTime initial,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime temp = DateTime(initial.year, initial.month, initial.day);
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 380,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        child: const Text('Annulla'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(temp),
                        child: const Text('Fatto'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      primaryColor: cs.primary,
                      brightness: Theme.of(context).brightness,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      minimumDate: firstDate,
                      maximumDate: lastDate,
                      initialDateTime: temp,
                      onDateTimeChanged: (dt) {
                        temp = DateTime(dt.year, dt.month, dt.day);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<TimeOfDay?> _pickTimeIOS({
    required String title,
    required TimeOfDay initial,
  }) async {
    TimeOfDay temp = initial;
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        child: const Text('Annulla'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(temp),
                        child: const Text('Fatto'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      primaryColor: cs.primary,
                      brightness: Theme.of(context).brightness,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: true,
                      initialDateTime: DateTime(
                        2000,
                        1,
                        1,
                        initial.hour,
                        initial.minute,
                      ),
                      onDateTimeChanged: (dt) {
                        temp = TimeOfDay(hour: dt.hour, minute: dt.minute);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  void _prevStep() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _recordBasePayment({
    required String bookingId,
    required int amountCents,
  }) async {
    final sb = Supabase.instance.client;

    await sb.from('booking_payments').insert({
      'booking_id': bookingId,
      'kind': 'base',
      'amount_cents': amountCents,
      // lascia paid_at al DEFAULT now() del DB (meno casini timezone)
      'payment_reference': 'mock',
    });
  }

  Future<void> _confirmBooking() async {
    // TODO(PAYMENTS - Stripe):
    // Incasso alla creazione (base) = flusso consigliato:
    //
    // 1) Calcola baseAmountCents (prezzo fascia prenotata).
    // 2) Crea PaymentIntent lato server (Edge Function) con amount=baseAmountCents.
    // 3) Presenta PaymentSheet / Checkout.
    // 4) SOLO se pagamento ok:
    //    - crea booking su DB (o finalizza un draft "pending_payment")
    //    - inserisci riga booking_payments(kind='base', amount_cents=...)
    //    - aggiorna partner_bookings.total_paid_cents (cache) e covered_until.
    // 5) Se pagamento annullato/fallito:
    //    - non creare booking oppure marca draft come cancelled e libera risorse.

    if (_busy) return;
    setState(() => _busy = true);

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final in7Days = today.add(const Duration(days: 7));

      final sel = _selectedDate!;
      final selDateOnly = DateTime(sel.year, sel.month, sel.day);

      // Vietato nel passato
      if (selDateOnly.isBefore(today)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La data selezionata è nel passato.')),
        );
        setState(() => _busy = false);
        return;
      }

      // Vietato oltre 7 giorni
      if (selDateOnly.isAfter(in7Days)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Puoi prenotare al massimo entro 7 giorni.'),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // Vietato prenotare in un giorno chiuso (weekly + eccezioni) per la consegna
      if (_isClosedDay(selDateOnly)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'In questo giorno il locale è chiuso. Scegli un\'altra data.',
            ),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // Partner deve essere prenotabile
      if (!widget.partner.isApproved) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Questo locale non è al momento prenotabile. Riprova più tardi.',
            ),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // Recuperiamo data+ora effettive da quello che ha scelto l'utente
      final startDt = _startDateTime;
      final endDtRequested = _endDateTime;

      if (startDt == null || endDtRequested == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleziona giorno e orario di consegna e di ritiro.'),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // Validazione completa + calcolo scadenza fascia (setta anche _effectiveEndDate/_effectiveEndTime)
      final dtError = _validateDateTimeSelection();
      if (dtError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(dtError)));
        setState(() => _busy = false);
        return;
      }

      // Assicuriamoci che la normalizzazione sia pronta
      final normalized =
          _normalizedPricingInterval ??
          BagDropPricing.normalizeBookingInterval(
            start: startDt,
            userEnd: endDtRequested,
            getCloseForDay: (day) {
              final dayOnly = DateTime(day.year, day.month, day.day);
              return _closeDateTimeForDay(dayOnly);
            },
          );

      final effectiveEnd = normalized.effectiveEnd;

      // Date-only per DB
      final bookingStartDate = DateTime(
        startDt.year,
        startDt.month,
        startDt.day,
      );
      final bookingEndDateEffective = DateTime(
        effectiveEnd.year,
        effectiveEnd.month,
        effectiveEnd.day,
      );

      // Requested date-only per DB
      final bookingEndDateRequested = DateTime(
        endDtRequested.year,
        endDtRequested.month,
        endDtRequested.day,
      );

      // 🔹 Formato "HH:MM" per la logica di disponibilità (effective interval)
      final startStrForAvailability = _formatTimeForApi(
        TimeOfDay(hour: startDt.hour, minute: startDt.minute),
      );
      final endStrForAvailabilityEffective = _formatTimeForApi(
        TimeOfDay(hour: effectiveEnd.hour, minute: effectiveEnd.minute),
      );

      // 🔹 Formato "HH:MM:SS" per il DB
      final startTimeStr = _formatTimeToDb(
        TimeOfDay(hour: startDt.hour, minute: startDt.minute),
      );

      // end effettivo (scadenza fascia)
      final endTimeStrEffective = _formatTimeToDb(
        TimeOfDay(hour: effectiveEnd.hour, minute: effectiveEnd.minute),
      );

      // end richiesto (scelta utente)
      final endTimeStrRequested = _formatTimeToDb(
        TimeOfDay(hour: endDtRequested.hour, minute: endDtRequested.minute),
      );

      // 2) Controllo disponibilità per intervallo EFFETTIVO
      final availability = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: bookingStartDate,
        startDate: bookingStartDate,
        endDate: bookingEndDateEffective,
        startTime: startStrForAvailability,
        endTime: endStrForAvailabilityEffective,
      );

      final totalRequested = _bagsS + _bagsM + _bagsL;
      final requestedUnits2x = _equivalentUnits2x(
        s: _bagsS,
        m: _bagsM,
        l: _bagsL,
      );
      final errors = <String>[];
      if (!availability.acceptS && _bagsS > 0) {
        errors.add('Small (S): il locale non accetta questa taglia.');
      }
      if (!availability.acceptM && _bagsM > 0) {
        errors.add('Medium (M): il locale non accetta questa taglia.');
      }
      if (!availability.acceptL && _bagsL > 0) {
        errors.add('Large (L): il locale non accetta questa taglia.');
      }

      final bool hasPerSizeCapacity =
          (availability.capacityS +
              availability.capacityM +
              availability.capacityL) >
          0;

      if (hasPerSizeCapacity) {
        if (_bagsS > 0 && _bagsS > availability.availableS) {
          errors.add(
            'Small (S): disponibili ${availability.availableS}, richiesti $_bagsS.',
          );
        }
        if (_bagsM > 0 && _bagsM > availability.availableM) {
          errors.add(
            'Medium (M): disponibili ${availability.availableM}, richiesti $_bagsM.',
          );
        }
        if (_bagsL > 0 && _bagsL > availability.availableL) {
          errors.add(
            'Large (L): disponibili ${availability.availableL}, richiesti $_bagsL.',
          );
        }
      }

      if (availability.capacityTotal > 0) {
        if (requestedUnits2x > availability.availableTotal) {
          final availableHuman = availability.availableTotal / 2.0;
          final requestedHuman = requestedUnits2x / 2.0;
          errors.add(
            'Spazio totale: disponibili ${availableHuman.toStringAsFixed(1)} unità, '
            'richieste ${requestedHuman.toStringAsFixed(1)} '
            '(1M = 2S = 0.5L).',
          );
        }
      }

      if (errors.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Disponibilità insufficiente'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Per questa attività non ci sono abbastanza posti disponibili per i bagagli selezionati in questo orario.',
                  ),
                  const SizedBox(height: 8),
                  ...errors.map((e) => Text('• $e')),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Ok'),
                ),
              ],
            );
          },
        );
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }

      final duration = normalized.duration;
      final extraDays = normalized.extraDays;

      final baseTotal = BagDropPricing.totalFor(
        duration: duration,
        extraDays: extraDays,
        bagsS: _bagsS,
        bagsM: _bagsM,
        bagsL: _bagsL,
      );

      final baseAmountCents = (baseTotal * 100).round();

      // 3) Se tutto ok → creiamo la prenotazione
      final bookingId = await repo.createBooking(
        partnerId: widget.partner.id,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        bagsS: _bagsS,
        bagsM: _bagsM,
        bagsL: _bagsL,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),

        bookingDate: bookingStartDate,
        startTime: startTimeStr,

        endDate: bookingEndDateEffective,
        endTime: endTimeStrEffective,

        endDateRequested: bookingEndDateRequested,
        endTimeRequested: endTimeStrRequested,
      );

      // ✅ MOCK “pagato alla creazione”: registra base payment
      await _recordBasePayment(
        bookingId: bookingId,
        amountCents: baseAmountCents,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prenotazione creata!')));

      Navigator.of(context).pop(); // torniamo al dettaglio partner
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore autenticazione: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imprevisto durante la prenotazione: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Converte un TimeOfDay nel formato stringa usato dal DB.
  /// Esempio: 9:5  → "09:05:00"
  String _formatTimeToDb(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00'; // se preferisci solo "HH:MM", usa '$hh:$mm'
  }

  void _prefillContactFromCurrentUser() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};

    _firstNameCtrl.text =
        (meta['first_name'] as String?) ?? _firstNameCtrl.text;
    _lastNameCtrl.text = (meta['last_name'] as String?) ?? _lastNameCtrl.text;
    _phoneCtrl.text = (meta['phone'] as String?) ?? _phoneCtrl.text;

    _emailCtrl.text = user.email ?? _emailCtrl.text;
  }

  /// Determina la durata tariffaria in base allo stato del flow.
  ///
  /// Per ora:
  /// - se l'utente ha scelto "Tutto il giorno" → 1 giorno
  /// - altrimenti → 3 ore
  ///
  /// In futuro qui potremo estendere a:
  /// - 1,5 giorni
  /// - 2 giorni
  /// - 3 giorni
  BagDropDuration _currentDuration() {
    final start = _startDateTime;
    final end = _endDateTime;

    if (start == null || end == null) {
      // Se mancano dati, consideriamo 3h come fallback neutro.
      return BagDropDuration.threeHours;
    }

    // Usa la logica centralizzata nel listino
    return BagDropPricing.inferDuration(start: start, end: end);
  }

  /// Testo leggibile per la durata, usato nel riepilogo.
  String _durationLabel() {
    final it = _pricingIntervalLive;
    if (it == null) return '—';

    switch (it.duration) {
      case BagDropDuration.threeHours:
        return '3 ore';
      case BagDropDuration.oneDay:
        return '1 giorno';
      case BagDropDuration.oneAndHalfDay:
        return '1 giorno e mezzo';
      case BagDropDuration.twoDays:
        return '2 giorni';
      case BagDropDuration.threeDays:
        return it.extraDays > 0 ? '3 giorni + ${it.extraDays}' : '3 giorni';
    }
  }

  /// Calcolo del prezzo totale usando BagDropPricing
  double _currentTotalPrice() {
    final it = _pricingIntervalLive;
    if (it == null) return 0.0;

    return BagDropPricing.totalFor(
      duration: it.duration,
      extraDays: it.extraDays,
      bagsS: _bagsS,
      bagsM: _bagsM,
      bagsL: _bagsL,
    );
  }

  /// Helper per formattare un double in "X,YY €".
  String _formatPrice(double value) {
    return BagDropPricing.formatEuro(value);
  }

  //helper info tariffe
  void _openPricingScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BagDropPricingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Prenota • ${widget.partner.name}'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStepHeader(),
              const SizedBox(height: 16),
              Expanded(child: _buildStepBody()),
              const SizedBox(height: 16),
              _buildBottomButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
    final cs = Theme.of(context).colorScheme;
    final steps = ['Contatto', 'Data e orario', 'Bagagli', 'Riepilogo'];

    return Row(
      children: List.generate(steps.length, (index) {
        final active = index == _step;
        final done = index < _step;

        Color fill;
        if (active) {
          fill = cs.primary;
        } else if (done) {
          fill = cs.primary.withOpacity(0.5);
        } else {
          fill = cs.surfaceVariant;
        }

        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: fill,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active || done ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 12,
                  color: active
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(done ? 0.8 : 0.6),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildContactForm();
      case 1:
        return _buildDateTimeForm();
      case 2:
        return _buildBagsForm();
      case 3:
        return _buildSummary();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContactForm() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    InputDecoration deco(String label, {String? hint, Widget? suffix}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: cs.surface.withOpacity(0.75),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: cs.primary.withOpacity(0.70),
            width: 1.2,
          ),
        ),
      );
    }

    Widget iosSection({required List<Widget> children}) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
    }

    Widget sectionTitle(String title, {String? subtitle}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget thinDivider() => Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.35),
    );

    return Form(
      key: _formContactKey,
      child: ListView(
        children: [
          iosSection(
            children: [
              sectionTitle(
                'Dati di contatto',
                subtitle: 'Inserisci i dati per completare la prenotazione',
              ),
              thinDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    // Nome
                    TextFormField(
                      controller: _firstNameCtrl,
                      decoration: deco('Nome'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return 'Inserisci il nome';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    // Cognome
                    TextFormField(
                      controller: _lastNameCtrl,
                      decoration: deco('Cognome'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return 'Inserisci il cognome';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    // Telefono
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: deco('Telefono', hint: '+39 ...'),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) {
                          return 'Inserisci un numero di telefono';
                        }
                        // Teniamo solo le cifre
                        final digitsOnly = t.replaceAll(RegExp(r'[^0-9]'), '');
                        if (digitsOnly.length != 10) {
                          return 'Il numero deve avere esattamente 10 cifre';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: deco('E-mail'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Inserisci un’e-mail';
                        if (!t.contains('@')) return 'E-mail non valida';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    // Note
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: deco(
                        'Note per il locale (opzionale)',
                        hint: 'Es. Arrivo in treno alle 10:30…',
                      ),
                      maxLines: 3,
                      maxLength: 500,
                      textInputAction: TextInputAction.newline,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeForm() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final cs = theme.colorScheme;

    String _formatDate(DateTime? d, String emptyLabel) {
      if (d == null) return emptyLabel;
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    }

    Widget iosRow({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
      bool showChevron = true,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.75),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurface.withOpacity(0.45),
                ),
              ],
            ],
          ),
        ),
      );
    }

    String startSummary;
    if (_selectedDate == null || _startTime == null) {
      startSummary = 'Non ancora impostato';
    } else {
      startSummary =
          '${_formatDate(_selectedDate, '')} · ${_formatTimeDisplay(_startTime!)}';
    }

    String endSummary;
    if (_endDate == null || _endTime == null) {
      endSummary = 'Non ancora impostato';
    } else {
      endSummary =
          '${_formatDate(_endDate, '')} · ${_formatTimeDisplay(_endTime!)}';
    }

    String durationSummary;
    if (_startDateTime == null || _endDateTime == null) {
      durationSummary =
          'Seleziona orari di consegna e ritiro per vedere la durata stimata.';
    } else {
      durationSummary = 'Durata tariffaria stimata: ${_durationLabel()}';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final in7Days = today.add(const Duration(days: 7));

    final startDate = _selectedDate ?? today;
    final pickupBase = _selectedDate ?? today;
    final pickupLast = pickupBase.add(const Duration(days: 7));

    final startOpen = _firstOpenTime;
    final startClose = _lastCloseTime;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Text(
          'Quando vuoi lasciare e ritirare i bagagli?',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Scegli giorno e ora di consegna e ritiro. L’intervallo deve rientrare negli orari di apertura del locale.',
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.7),
          ),
        ),

        const SizedBox(height: 14),

        // ✅ INFO PREZZI / TARIFFE
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: ListTile(
            onTap: _openPricingScreen,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.payments_outlined, color: cs.primary),
            ),
            title: Text(
              'Prezzi e tariffe',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              durationSummary,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.7),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ✅ CONSEGNA (stile iOS section)
        Text(
          'Consegna',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.25),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              iosRow(
                icon: Icons.calendar_today_outlined,
                title: 'Giorno',
                value: _formatDate(_selectedDate, 'Seleziona'),
                onTap: () async {
                  final picked = await _pickDateIOS(
                    title: 'Scegli il giorno di consegna',
                    initial: startDate,
                    firstDate: today,
                    lastDate: in7Days,
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );

                      // reset preset
                      _selectedPresetIndex = null;
                      _plusDaysPreset = 0;

                      // riallinea ritiro se serve
                      if (_endDate == null ||
                          _endDate!.isBefore(_selectedDate!)) {
                        _endDate = _selectedDate;
                      }
                    });
                  }
                },
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
              iosRow(
                icon: Icons.access_time_rounded,
                title: 'Orario',
                value: _startTime == null
                    ? 'Seleziona'
                    : _formatTimeDisplay(_startTime!),
                onTap: () async {
                  final initial =
                      _startTime ?? TimeOfDay.fromDateTime(DateTime.now());
                  final picked = await _pickTimeIOS(
                    title: 'Scegli l’orario di consegna',
                    initial: initial,
                  );
                  if (picked != null) {
                    setState(() {
                      _startTime = picked;
                      _selectedPresetIndex = null;
                      _plusDaysPreset = 0;
                    });
                  }
                },
              ),
            ],
          ),
        ),

        if (startOpen != null && startClose != null) ...[
          const SizedBox(height: 6),
          Text(
            'Orari del locale: ${_formatTimeDisplay(startOpen)}–${_formatTimeDisplay(startClose)}',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ✅ DURATA RAPIDA (chip più ordinati)
        Text(
          'Durata rapida',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('+ 3 ore'),
              selected: _selectedPresetIndex == 0,
              onSelected: (selected) {
                if (selected) {
                  _applyPreset(0);
                } else {
                  setState(() => _selectedPresetIndex = null);
                }
              },
            ),
            ChoiceChip(
              label: const Text('Tutto il giorno'),
              selected: _selectedPresetIndex == 1,
              onSelected: (selected) {
                if (selected) {
                  _applyPreset(1);
                } else {
                  setState(() => _selectedPresetIndex = null);
                }
              },
            ),
            ChoiceChip(
              label: Text(
                _plusDaysPreset == 0
                    ? '+ 1 giorno'
                    : '+ $_plusDaysPreset giorni',
              ),
              selected: _selectedPresetIndex == 2 && _plusDaysPreset > 0,
              onSelected: (_) => _applyPlusDaysPreset(),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ✅ RITIRO (stile iOS section)
        Text(
          'Ritiro',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.25),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              iosRow(
                icon: Icons.calendar_today_outlined,
                title: 'Giorno',
                value: _formatDate(_endDate, 'Seleziona'),
                onTap: () async {
                  final initial = _endDate ?? pickupBase;
                  final picked = await _pickDateIOS(
                    title: 'Scegli il giorno di ritiro',
                    initial: initial,
                    firstDate: pickupBase,
                    lastDate: pickupLast,
                  );
                  if (picked != null) {
                    setState(() {
                      _endDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    });
                  }
                },
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
              iosRow(
                icon: Icons.access_time_rounded,
                title: 'Orario',
                value: _endTime == null
                    ? 'Seleziona'
                    : _formatTimeDisplay(_endTime!),
                onTap: () async {
                  final initial =
                      _endTime ??
                      _startTime ??
                      const TimeOfDay(hour: 18, minute: 0);
                  final picked = await _pickTimeIOS(
                    title: 'Scegli l’orario di ritiro',
                    initial: initial,
                  );
                  if (picked != null) {
                    setState(() {
                      _endTime = picked;
                    });
                  }
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ✅ RIEPILOGO
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Riepilogo',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.login, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Consegna: $startSummary',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.logout, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ritiro: $endSummary',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      durationSummary,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Puoi prenotare da oggi fino a 7 giorni dopo. La consegna di oggi ha 2 minuti di tolleranza (se mentre compili passano 1–2 minuti, va bene).',
                style: textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAvailabilitySnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Aggiorna i bagagli applicando:
  /// - limiti per taglia (availableS/M/L se presenti)
  /// - limite sullo spazio TOTALE equivalente (availableTotal con 1M = 2S = 0.5L)
  void _updateBags({int? small, int? medium, int? large}) {
    final av = _availability;
    // ✅ blocca taglie non accettate (extra-sicurezza)
    if (av != null) {
      if (!av.acceptS && (small ?? _bagsS) > 0) {
        _showAvailabilitySnack('Il locale non accetta bagagli Small (S).');
        return;
      }
      if (!av.acceptM && (medium ?? _bagsM) > 0) {
        _showAvailabilitySnack('Il locale non accetta bagagli Medium (M).');
        return;
      }
      if (!av.acceptL && (large ?? _bagsL) > 0) {
        _showAvailabilitySnack('Il locale non accetta bagagli Large (L).');
        return;
      }
    }

    final newS = small ?? _bagsS;
    final newM = medium ?? _bagsM;
    final newL = large ?? _bagsL;

    // niente valori negativi
    if (newS < 0 || newM < 0 || newL < 0) return;

    if (av != null) {
      final hasPerSizeCapacity =
          (av.capacityS + av.capacityM + av.capacityL) > 0;

      // 🔹 Limiti per taglia se configurati
      if (hasPerSizeCapacity) {
        if (newS > av.availableS) {
          _showAvailabilitySnack('Small (S) disponibili: ${av.availableS}.');
          return;
        }
        if (newM > av.availableM) {
          _showAvailabilitySnack('Medium (M) disponibili: ${av.availableM}.');
          return;
        }
        if (newL > av.availableL) {
          _showAvailabilitySnack('Large (L) disponibili: ${av.availableL}.');
          return;
        }
      }

      // 🔹 Limite sullo spazio TOTALE equivalente (stessa unità del repo: mezze-M)
      if (av.capacityTotal > 0) {
        final units2x = _equivalentUnits2x(s: newS, m: newM, l: newL);
        if (units2x > av.availableTotal) {
          _showAvailabilitySnack(
            'Non c\'è abbastanza spazio per questa combinazione di bagagli.',
          );
          return;
        }
      }
    }

    setState(() {
      _bagsS = newS;
      _bagsM = newM;
      _bagsL = newL;
    });
  }

  Widget _buildBagsForm() {
    if (_loadingAvailability) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final av = _availability;
    final bool canS = av?.acceptS ?? true;
    final bool canM = av?.acceptM ?? true;
    final bool canL = av?.acceptL ?? true;

    int? maxS;
    int? maxM;
    int? maxL;

    if (av != null) {
      final hasPerSizeCapacity =
          (av.capacityS + av.capacityM + av.capacityL) > 0;
      if (hasPerSizeCapacity) {
        maxS = av.availableS;
        maxM = av.availableM;
        maxL = av.availableL;
      }
      if (!canS) maxS = 0;
      if (!canM) maxM = 0;
      if (!canL) maxL = 0;
    }

    final totalBags = _bagsS + _bagsM + _bagsL;

    // Totale capacity bar
    int capacityUnits = 0;
    int usedUnits = 0;
    int selectionUnits = 0;
    int futureUsedUnits = 0;
    double occupancyRatio = 0.0;
    bool isOverCapacity = false;

    if (av != null && av.capacityTotal > 0) {
      capacityUnits = av.capacityTotal;
      usedUnits = av.usedTotal;
      selectionUnits = _currentRequestedUnits2x();
      futureUsedUnits = usedUnits + selectionUnits;

      isOverCapacity = futureUsedUnits > capacityUnits;

      final clamped = futureUsedUnits.clamp(0, capacityUnits);
      occupancyRatio = capacityUnits > 0 ? clamped / capacityUnits : 0.0;
    }

    final double capacityHuman = capacityUnits / 2.0;
    final double futureUsedHuman = futureUsedUnits / 2.0;

    Widget sectionTitle(String title, {String? subtitle}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ],
      );
    }

    Widget iosSection({required List<Widget> children}) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(children: children),
      );
    }

    Widget divider() =>
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35));

    final it = _pricingIntervalLive; // ✅ interval vero (duration + extraDays)
    final canShowPrice =
        _selectedDate != null &&
        _startTime != null &&
        _endTime != null &&
        totalBags > 0;

    final baseNoExtra = canShowPrice ? _priceBaseNoExtra() : 0.0;
    final extraOnly = canShowPrice ? _priceExtraDaysOnly() : 0.0;
    final totalPrice = canShowPrice ? _currentTotalPrice() : 0.0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        sectionTitle(
          'Bagagli',
          subtitle:
              'Seleziona numero e dimensione. Il prezzo si aggiorna in tempo reale.',
        ),

        const SizedBox(height: 12),

        if (av != null) ...[
          Text(
            'Disponibilità • S: ${av.availableS}  ·  M: ${av.availableM}  ·  L: ${av.availableL}',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 10),
        ],

        iosSection(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(
                'Selezione',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  _BagRow(
                    label: 'Small (S)',
                    description: 'Zainetti o trolley piccoli',
                    count: _bagsS,
                    max: canS ? maxS : 0,
                    onChanged: (v) => _updateBags(small: v),
                  ),
                  const SizedBox(height: 8),
                  _BagRow(
                    label: 'Medium (M)',
                    description: 'Trolley medi',
                    count: _bagsM,
                    max: canM ? maxM : 0,
                    onChanged: (v) => _updateBags(medium: v),
                  ),
                  const SizedBox(height: 8),
                  _BagRow(
                    label: 'Large (L)',
                    description: 'Valigie grandi',
                    count: _bagsL,
                    max: canL ? maxL : 0,
                    onChanged: (v) => _updateBags(large: v),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (av != null && av.capacityTotal > 0) ...[
          const SizedBox(height: 14),
          sectionTitle('Spazio totale per questo intervallo'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: occupancyRatio.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: cs.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOverCapacity ? cs.error : cs.primary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOverCapacity
                          ? 'Stai superando lo spazio disponibile: riduci il numero di bagagli.'
                          : 'Occupato: ${futureUsedHuman.toStringAsFixed(1)} / ${capacityHuman.toStringAsFixed(1)} unità equivalenti',
                      style: tt.bodySmall?.copyWith(
                        color: isOverCapacity
                            ? cs.error
                            : cs.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Equivalenze: 1 S = 1 • 1 M = 2 • 1 L = 4 unità.',
                      style: tt.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 14),

        // ✅ ANTEPRIMA PREZZO (vera anche >3 giorni)
        sectionTitle('Anteprima prezzo'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!canShowPrice) ...[
                    Text(
                      'Seleziona date/orari e almeno un bagaglio per vedere il prezzo.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Totale',
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _formatPrice(totalPrice),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Durata tariffaria: ${_durationLabel()}',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    if (it != null &&
                        it.duration == BagDropDuration.threeDays &&
                        it.extraDays > 0) ...[
                      const SizedBox(height: 10),
                      divider(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Base (fino a 3 giorni)',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),
                          Text(
                            _formatPrice(baseNoExtra),
                            style: tt.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Giorni extra: ${it.extraDays} × 2€ × $totalBags bagagli',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),
                          Text(
                            '+ ${_formatPrice(extraOnly)}',
                            style: tt.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final totalBags = _bagsS + _bagsM + _bagsL;

    String fmtDate(DateTime? d) {
      if (d == null) return '—';
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    }

    final it = _pricingIntervalLive;
    final canShowPrice =
        _selectedDate != null &&
        _startTime != null &&
        _endTime != null &&
        totalBags > 0;

    final baseNoExtra = canShowPrice ? _priceBaseNoExtra() : 0.0;
    final extraOnly = canShowPrice ? _priceExtraDaysOnly() : 0.0;
    final totalPrice = canShowPrice ? _currentTotalPrice() : 0.0;

    Widget sectionTitle(String title) => Text(
      title,
      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );

    Widget iosSection({required List<Widget> children}) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(children: children),
      );
    }

    Widget divider() =>
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35));

    Widget rowKV(String k, String v, {bool bold = false}) {
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
            Text(
              v,
              style: tt.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: cs.onSurface.withOpacity(bold ? 1.0 : 0.75),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Text(
          'Riepilogo prenotazione',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),

        sectionTitle('Attività'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partner.name,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  if ((widget.partner.address ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.partner.address!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        sectionTitle('Data e orario'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            rowKV('Deposito', fmtDate(_selectedDate)),
            divider(),
            rowKV(
              'Ora deposito',
              _startTime == null ? '—' : _formatTimeDisplay(_startTime!),
            ),
            divider(),
            rowKV('Ritiro', fmtDate(_endDate)),
            divider(),
            rowKV(
              'Ora ritiro',
              _endTime == null ? '—' : _formatTimeDisplay(_endTime!),
            ),
            divider(),
            rowKV('Durata tariffaria', _durationLabel(), bold: true),
          ],
        ),

        const SizedBox(height: 14),

        sectionTitle('Contatto'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            rowKV(
              'Nome',
              '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
            ),
            divider(),
            rowKV('Telefono', _phoneCtrl.text.trim()),
            divider(),
            rowKV('E-mail', _emailCtrl.text.trim()),
          ],
        ),

        const SizedBox(height: 14),

        sectionTitle('Bagagli'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            rowKV('Totale', '$totalBags'),
            if (_bagsS > 0) ...[divider(), rowKV('Small (S)', '$_bagsS')],
            if (_bagsM > 0) ...[divider(), rowKV('Medium (M)', '$_bagsM')],
            if (_bagsL > 0) ...[divider(), rowKV('Large (L)', '$_bagsL')],
          ],
        ),

        const SizedBox(height: 14),

        sectionTitle('Prezzo finale'),
        const SizedBox(height: 8),
        iosSection(
          children: [
            if (!canShowPrice)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Text(
                  'Seleziona date/orari e almeno un bagaglio per vedere il prezzo.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              )
            else ...[
              rowKV('Totale', _formatPrice(totalPrice), bold: true),
              if (it != null &&
                  it.duration == BagDropDuration.threeDays &&
                  it.extraDays > 0) ...[
                divider(),
                rowKV('Base (fino a 3 giorni)', _formatPrice(baseNoExtra)),
                divider(),
                rowKV('Giorni extra', '+ ${_formatPrice(extraOnly)}'),
              ],
            ],
          ],
        ),

        const SizedBox(height: 12),

        iosSection(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.75),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Con “Paga e conferma” verrai indirizzato al pagamento. '
                      'La prenotazione risulta confermata solo dopo esito positivo.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (_notesCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          sectionTitle('Note'),
          const SizedBox(height: 8),
          iosSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Text(_notesCtrl.text.trim(), style: tt.bodySmall),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _prevStep,
              child: const Text('Indietro'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () {
                    if (_step < 3) {
                      _nextStep();
                    } else {
                      _confirmBooking();
                    }
                  },
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_step < 3 ? 'Avanti' : 'Paga e conferma'),
          ),
        ),
      ],
    );
  }
}

/// Riga per selezionare il numero di bagagli di una certa taglia.
class _BagRow extends StatelessWidget {
  final String label;
  final String description;
  final int count;
  final int? max;
  final ValueChanged<int> onChanged;

  const _BagRow({
    required this.label,
    required this.description,
    required this.count,
    required this.onChanged,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (max != null)
                    Text(
                      'Disponibili: $max',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: count > 0 ? () => onChanged(count - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$count'),
                IconButton(
                  onPressed: (max != null && count >= max!)
                      ? null
                      : () => onChanged(count + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimePillButton extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateTimePillButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bool isEmpty =
        value == 'Seleziona giorno' ||
        value == 'Seleziona ora' ||
        value.isEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isEmpty
                ? cs.outline.withOpacity(0.6)
                : cs.primary.withOpacity(0.7),
          ),
          color: isEmpty ? cs.surface : cs.primary.withOpacity(0.06),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isEmpty ? cs.outline : cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      letterSpacing: 0.4,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
