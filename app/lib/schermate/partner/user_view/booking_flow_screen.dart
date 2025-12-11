// è la pagina che vede l'utente cliccando il tasto prenota ora dalla scheda dell'attività

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';

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
    final endDt = _endDateTime;

    if (startDt == null || endDt == null) {
      return 'Seleziona giorno e orario di consegna e di ritiro.';
    }

    // Date solo "calendar" (senza orario)
    final startDateOnly = DateTime(startDt.year, startDt.month, startDt.day);
    final endDateOnly = DateTime(endDt.year, endDt.month, endDt.day);

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
    if (startDateOnly.isAtSameMomentAs(today) && startDt.isBefore(now)) {
      return 'L\'orario di consegna non può essere nel passato.';
    }

    // ❌ Orario ritiro dopo orario consegna
    if (!startDt.isBefore(endDt)) {
      return 'L\'orario di ritiro deve essere successivo a quello di consegna.';
    }

    // ❌ Giorni chiusi (weekly + eccezioni)
    if (_isClosedDay(startDateOnly)) {
      return 'Nel giorno di consegna il locale è chiuso. Scegli un\'altra data.';
    }
    if (_isClosedDay(endDateOnly)) {
      return 'Nel giorno di ritiro il locale è chiuso. Scegli un\'altra data.';
    }

    // ❌ Orario fuori dagli orari di apertura (consegna)
    if (!_isTimeWithinOpeningHours(startDateOnly, _startTime!)) {
      return 'L\'orario di consegna è fuori dagli orari di apertura del locale.';
    }

    // ❌ Orario fuori dagli orari di apertura (ritiro)
    if (!_isTimeWithinOpeningHours(endDateOnly, _endTime!)) {
      return 'L\'orario di ritiro è fuori dagli orari di apertura del locale.';
    }

    // Limite di durata "sanità mentale" lato business (per ora 3 giorni max)
    final durationHours = endDt.difference(startDt).inMinutes / 60.0;
    if (durationHours > 72.0) {
      return 'Per ora puoi prenotare al massimo per 3 giorni. Riduci l\'intervallo tra consegna e ritiro.';
    }

    return null; // ✅ tutto ok
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
    final bookingEndDate = _endDate!;

    try {
      final av = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: bookingStartDate,
        startDate: bookingStartDate,
        endDate: bookingEndDate,
        startTime: startStr,
        endTime: endStr,
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

  Future<void> _confirmBooking() async {
    if (_busy) return;
    setState(() => _busy = true);

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final in7Days = today.add(const Duration(days: 7));
      // Validazione unica data/orario (stessi controlli dello step 1)
      final dtError = _validateDateTimeSelection();
      if (dtError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(dtError)));
        setState(() => _busy = false);
        return;
      }

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
      final endDt = _endDateTime;

      if (startDt == null || endDt == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleziona giorno e orario di consegna e di ritiro.'),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      if (!startDt.isBefore(endDt)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'L\'orario di ritiro deve essere dopo quello di consegna.',
            ),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      final bookingStartDate = DateTime(
        startDt.year,
        startDt.month,
        startDt.day,
      );
      final bookingEndDate = DateTime(endDt.year, endDt.month, endDt.day);

      // 🔹 Formato "HH:MM" per la logica di disponibilità
      final startStrForAvailability = _formatTimeForApi(
        TimeOfDay(hour: startDt.hour, minute: startDt.minute),
      );
      final endStrForAvailability = _formatTimeForApi(
        TimeOfDay(hour: endDt.hour, minute: endDt.minute),
      );

      // 🔹 Formato "HH:MM:SS" per il DB
      final startTimeStr = _formatTimeToDb(
        TimeOfDay(hour: startDt.hour, minute: startDt.minute),
      );
      final endTimeStr = _formatTimeToDb(
        TimeOfDay(hour: endDt.hour, minute: endDt.minute),
      );

      // 2) Controllo disponibilità per questo intervallo
      final availability = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: bookingStartDate,
        startDate: bookingStartDate,
        endDate: bookingEndDate,
        startTime: startStrForAvailability,
        endTime: endStrForAvailability,
      );

      final totalRequested = _bagsS + _bagsM + _bagsL;
      final errors = <String>[];

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

      if (availability.capacityTotal > 0 &&
          totalRequested > availability.availableTotal) {
        errors.add(
          'Totale bagagli: disponibili ${availability.availableTotal}, richiesti $totalRequested.',
        );
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

      // 3) Se tutto ok → creiamo la prenotazione
      await repo.createBooking(
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
        endTime: endTimeStr,
        endDate: bookingEndDate,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prenotazione creata! (Pagamento/QR in arrivo 😉)'),
        ),
      );

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
    switch (_currentDuration()) {
      case BagDropDuration.threeHours:
        return '3 ore';
      case BagDropDuration.oneDay:
        return '1 giorno';
      case BagDropDuration.oneAndHalfDay:
        return '1 giorno e mezzo';
      case BagDropDuration.twoDays:
        return '2 giorni';
      case BagDropDuration.threeDays:
        return '3 giorni';
    }
  }

  /// Calcolo del prezzo totale usando BagDropPricing
  double _currentTotalPrice() {
    final duration = _currentDuration();
    return BagDropPricing.totalFor(
      duration: duration,
      bagsS: _bagsS,
      bagsM: _bagsM,
      bagsL: _bagsL,
    );
  }

  /// Helper per formattare un double in "X,YY €".
  String _formatPrice(double value) {
    return BagDropPricing.formatEuro(value);
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
    return Form(
      key: _formContactKey,
      child: ListView(
        children: [
          Text(
            'Dati di contatto',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          // Nome
          TextFormField(
            controller: _firstNameCtrl,
            decoration: const InputDecoration(labelText: 'Nome'),
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
            decoration: const InputDecoration(labelText: 'Cognome'),
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
            decoration: const InputDecoration(
              labelText: 'Telefono',
              hintText: '+39 ...',
            ),
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
            decoration: const InputDecoration(labelText: 'E-mail'),
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
            decoration: const InputDecoration(
              labelText: 'Note per il locale (opzionale)',
              hintText: 'Es. Arrivo in treno alle 10:30…',
            ),
            maxLines: 3,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeForm() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    String _formatDate(DateTime? d, String emptyLabel) {
      if (d == null) return emptyLabel;
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Text(
          'Quando vuoi lasciare e ritirare i bagagli?',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),

        // =========================
        // 1. CONSEGNA
        // =========================
        Text(
          '1. Consegna dei bagagli',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        // Giorno di consegna
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Giorno di consegna'),
          subtitle: Text(
            _formatDate(_selectedDate, 'Seleziona il giorno di consegna'),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final in7Days = today.add(const Duration(days: 7));

            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate ?? today,
              firstDate: today,
              lastDate: in7Days,
            );
            if (picked != null) {
              setState(() {
                _selectedDate = DateTime(picked.year, picked.month, picked.day);

                // Se non hai ancora una data di ritiro, inizializzala uguale alla consegna
                if (_endDate == null || _endDate!.isBefore(_selectedDate!)) {
                  _endDate = _selectedDate;
                }
              });
            }
          },
        ),
        const SizedBox(height: 8),

        // Orario di consegna
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Orario di consegna'),
          subtitle: Text(
            _startTime == null
                ? 'Seleziona l\'orario di consegna'
                : _formatTimeDisplay(_startTime!),
          ),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final initial = _startTime ?? const TimeOfDay(hour: 10, minute: 0);
            final picked = await showTimePicker(
              context: context,
              initialTime: initial,
            );
            if (picked != null) {
              setState(() {
                _startTime = picked;
              });
            }
          },
        ),

        const SizedBox(height: 24),

        // =========================
        // 2. RITIRO
        // =========================
        Text(
          '2. Ritiro dei bagagli',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        // Giorno di ritiro
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Giorno di ritiro'),
          subtitle: Text(
            _formatDate(_endDate, 'Seleziona il giorno di ritiro'),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            final baseStartDate = _selectedDate ?? today;
            final firstDate = baseStartDate;
            final lastDate = baseStartDate.add(const Duration(days: 7));
            final initial = _endDate ?? baseStartDate;

            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (picked != null) {
              setState(() {
                _endDate = DateTime(picked.year, picked.month, picked.day);
              });
            }
          },
        ),
        const SizedBox(height: 8),

        // Orario di ritiro
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Orario di ritiro'),
          subtitle: Text(
            _endTime == null
                ? 'Seleziona l\'orario di ritiro'
                : _formatTimeDisplay(_endTime!),
          ),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final initialTime =
                _endTime ?? _startTime ?? const TimeOfDay(hour: 18, minute: 0);
            final picked = await showTimePicker(
              context: context,
              initialTime: initialTime,
            );
            if (picked != null) {
              setState(() {
                _endTime = picked;
              });
            }
          },
        ),

        const SizedBox(height: 20),

        // =========================
        // RIEPILOGO ORARI
        // =========================
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Riepilogo orari',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Consegna: $startSummary'),
                Text('Ritiro:   $endSummary'),
                const SizedBox(height: 8),
                Text(
                  durationSummary,
                  style: textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Gli orari effettivi di deposito devono rientrare negli orari di apertura del locale. '
          'Controlla sempre la scheda del partner per verificare gli orari.',
          style: textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Puoi prenotare da oggi fino a 7 giorni dopo. Le prenotazioni nel passato non sono consentite.',
          style: textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }


  Widget _buildBagsForm() {
    if (_loadingAvailability) {
      return const Center(child: CircularProgressIndicator());
    }

    final av = _availability;

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
      // se non c'è capacità per taglia, lasciamo i max null
      // e lasciamo il controllo "di sicurezza" solo a _confirmBooking
    }

    final totalBags = _bagsS + _bagsM + _bagsL; // 👈 NEW

    return ListView(
      children: [
        Text(
          'Seleziona numero e dimensione dei bagagli',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (av != null) ...[
          const SizedBox(height: 4),
          Text(
            'Disponibili - S: ${av.availableS} • M: ${av.availableM} • L: ${av.availableL}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        _BagRow(
          label: 'Small (S)',
          description: 'Zainetti o trolley piccoli',
          count: _bagsS,
          max: maxS,
          onChanged: (v) => setState(() => _bagsS = v),
        ),
        const SizedBox(height: 8),
        _BagRow(
          label: 'Medium (M)',
          description: 'Trolley medi',
          count: _bagsM,
          max: maxM,
          onChanged: (v) => setState(() => _bagsM = v),
        ),
        const SizedBox(height: 8),
        _BagRow(
          label: 'Large (L)',
          description: 'Valigie grandi',
          count: _bagsL,
          max: maxL,
          onChanged: (v) => setState(() => _bagsL = v),
        ),

        const SizedBox(height: 16),

        // 👇 Box prezzo dinamico in Step 3
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prezzo stimato',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (_selectedDate == null ||
                    _startTime == null ||
                    _endTime == null ||
                    totalBags == 0)
                  const Text(
                    'Seleziona data, orario e almeno un bagaglio per vedere il prezzo.',
                  )
                else
                  Text(
                    _formatPrice(_currentTotalPrice()),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final totalBags = _bagsS + _bagsM + _bagsL;

    final start = _startTime;
    final end = _endTime;

    String timeText;
    if (start == null || end == null) {
      timeText = 'Orario non selezionato';
    } else {
      timeText =
          '${_formatTimeDisplay(start)} - ${_formatTimeDisplay(end)} (${_durationLabel()})';
    }

    return ListView(
      children: [
        Text(
          'Riepilogo prenotazione',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.partner.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if ((widget.partner.address ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(widget.partner.address!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Data e orario
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data e orario',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),

                // Deposito
                Text(
                  _selectedDate == null
                      ? 'Data di deposito non selezionata'
                      : '${_selectedDate!.day.toString().padLeft(2, '0')}/'
                            '${_selectedDate!.month.toString().padLeft(2, '0')}/'
                            '${_selectedDate!.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(timeText),

                const SizedBox(height: 8),

                // Ritiro
                const Text(
                  'Ritiro bagagli',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _endDate == null
                      ? 'Data di ritiro non selezionata'
                      : '${_endDate!.day.toString().padLeft(2, '0')}/'
                            '${_endDate!.month.toString().padLeft(2, '0')}/'
                            '${_endDate!.year}',
                ),
                if (_endTime != null)
                  Text('Ore ${_formatTimeDisplay(_endTime!)}'),

                const SizedBox(height: 8),

                // Durata tariffaria
                Text(
                  'Durata tariffaria: ${_durationLabel()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contatto',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
                ),
                Text(_phoneCtrl.text.trim()),
                Text(_emailCtrl.text.trim()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bagagli',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('Totale: $totalBags'),
                if (_bagsS > 0) Text('• $_bagsS × Small (S)'),
                if (_bagsM > 0) Text('• $_bagsM × Medium (M)'),
                if (_bagsL > 0) Text('• $_bagsL × Large (L)'),
              ],
            ),
          ),
        ),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prezzo stimato',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (_selectedDate == null || totalBags == 0)
                  const Text(
                    'Seleziona data, orario e almeno un bagaglio per vedere il prezzo.',
                  )
                else
                  Text(
                    _formatPrice(_currentTotalPrice()),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),

        if (_notesCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Note',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(_notesCtrl.text.trim()),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Pagamento e QR code per il check-in saranno integrati in una fase successiva.',
          style: TextStyle(fontSize: 12),
        ),
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
                : Text(_step < 3 ? 'Avanti' : 'Conferma prenotazione'),
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
