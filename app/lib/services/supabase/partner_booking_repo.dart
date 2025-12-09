import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/services/supabase/client.dart';

/// DTO per la disponibilità di un partner.
class PartnerAvailability {
  final int capacityS;
  final int capacityM;
  final int capacityL;
  final int capacityTotal;

  final int usedS;
  final int usedM;
  final int usedL;
  final int usedTotal;

  final int availableS;
  final int availableM;
  final int availableL;
  final int availableTotal;

  const PartnerAvailability({
    required this.capacityS,
    required this.capacityM,
    required this.capacityL,
    required this.capacityTotal,
    required this.usedS,
    required this.usedM,
    required this.usedL,
    required this.usedTotal,
    required this.availableS,
    required this.availableM,
    required this.availableL,
    required this.availableTotal,
  });
}

/// Repository per gestire le prenotazioni partner_bookings.
class PartnerBookingRepo {
  final SupabaseClient client;

  const PartnerBookingRepo(this.client);

  /// Crea una nuova prenotazione per l'utente loggato.
  ///
  /// [bookingDate] = giorno della prenotazione (obbligatorio nel nuovo flusso).
  /// [startTime], [endTime] = orari nel formato "HH:MM" (es. "10:00").
  Future<void> createBooking({
    required String partnerId,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required int bagsS,
    required int bagsM,
    required int bagsL,
    String? notes,
    required DateTime bookingDate,
    required String startTime,
    required String endTime,
    DateTime? endDate,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException(
        'Devi essere autenticato per creare una prenotazione.',
      );
    }

    // Normalizziamo le date a "solo giorno"
    final startDay = DateTime(
      bookingDate.year,
      bookingDate.month,
      bookingDate.day,
    );

    final endDayRaw = endDate ?? bookingDate;
    final endDay = DateTime(endDayRaw.year, endDayRaw.month, endDayRaw.day);

    await client.from('partner_bookings').insert({
      'partner_id': partnerId,
      'user_id': userId,
      'contact_first_name': firstName,
      'contact_last_name': lastName,
      'contact_phone': phone,
      'contact_email': email,
      'bags_s': bagsS,
      'bags_m': bagsM,
      'bags_l': bagsL,
      'notes': notes,
      // nuovi campi per lo scheduling
      'booking_date': startDay.toIso8601String(),
      'end_date': endDay.toIso8601String(),
      'start_time': startTime,
      'end_time': endTime,
      // status default: 'confirmed' come da migration
    });
  }

  /// Prenotazioni dell'utente corrente (lato app utente).
  Future<List<PartnerBooking>> getMyBookings() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException(
        'Devi essere autenticato per vedere le tue prenotazioni.',
      );
    }

    final data = await client
        .from('partner_bookings')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final list = (data as List)
        .map((row) => PartnerBooking.fromMap(row as Map<String, dynamic>))
        .toList();

    return list;
  }

  /// Prenotazioni per un dato partner (quando serve qualcosa di specifico).
  Future<List<PartnerBooking>> getBookingsForPartner(String partnerId) async {
    final data = await client
        .from('partner_bookings')
        .select()
        .eq('partner_id', partnerId)
        .order('created_at', ascending: false);

    final list = (data as List)
        .map((row) => PartnerBooking.fromMap(row as Map<String, dynamic>))
        .toList();

    return list;
  }

  /// Calcola la disponibilità "grezza" su TUTTE le prenotazioni attive del partner,
  /// ignorando data/orario (usato solo per viste generiche / retrocompat).
  Future<PartnerAvailability> getPartnerAvailability(String partnerId) async {
    // 1) Leggiamo la capacità dal partner
    final partnerRow = await client
        .from('partners')
        .select('capacity_s, capacity_m, capacity_l, capacity')
        .eq('id', partnerId)
        .maybeSingle();

    if (partnerRow == null) {
      throw Exception('Partner non trovato per id=$partnerId');
    }

    final int capS = (partnerRow['capacity_s'] as int?) ?? 0;
    final int capM = (partnerRow['capacity_m'] as int?) ?? 0;
    final int capL = (partnerRow['capacity_l'] as int?) ?? 0;
    final int capTotalDb = (partnerRow['capacity'] as int?) ?? 0;

    final int sumSizes = capS + capM + capL;
    final int capacityTotal = sumSizes > 0 ? sumSizes : capTotalDb;

    // 2) Sommiamo i bagagli delle prenotazioni attive (status != cancelled)
    final bookingsData = await client
        .from('partner_bookings')
        .select('bags_s, bags_m, bags_l, status')
        .eq('partner_id', partnerId)
        .neq('status', 'cancelled');

    int usedS = 0;
    int usedM = 0;
    int usedL = 0;

    for (final row in bookingsData as List) {
      usedS += (row['bags_s'] as int?) ?? 0;
      usedM += (row['bags_m'] as int?) ?? 0;
      usedL += (row['bags_l'] as int?) ?? 0;
    }

    final int usedTotal = usedS + usedM + usedL;

    int availableS = capS - usedS;
    int availableM = capM - usedM;
    int availableL = capL - usedL;
    int availableTotal = capacityTotal - usedTotal;

    if (availableS < 0) availableS = 0;
    if (availableM < 0) availableM = 0;
    if (availableL < 0) availableL = 0;
    if (availableTotal < 0) availableTotal = 0;

    return PartnerAvailability(
      capacityS: capS,
      capacityM: capM,
      capacityL: capL,
      capacityTotal: capacityTotal,
      usedS: usedS,
      usedM: usedM,
      usedL: usedL,
      usedTotal: usedTotal,
      availableS: availableS,
      availableM: availableM,
      availableL: availableL,
      availableTotal: availableTotal,
    );
  }

  /// Calcola la disponibilità per UN INTERVALLO specifico.
  ///
  /// L’intervallo è definito da:
  /// - [startDate] + [startTime]
  /// - [endDate]   + [endTime]
  ///
  /// Consideriamo solo le prenotazioni del partner:
  /// - status IN ('pending','confirmed') → cioè ancora “attive”
  /// - che si SOVRAPPONGONO all’intervallo richiesto
  ///
  /// [bookingDate] rimane nel metodo solo per compatibilità, ma non è usato.
  Future<PartnerAvailability> getPartnerAvailabilityForInterval({
    required String partnerId,
    required DateTime bookingDate, // rimane per compatibilità, non lo usiamo più
    required DateTime startDate,
    required DateTime endDate,
    required String startTime,
    required String endTime,
  }) async {
    // 1) Capacità dal partner
    final partnerRow = await client
        .from('partners')
        .select('capacity_s, capacity_m, capacity_l, capacity')
        .eq('id', partnerId)
        .maybeSingle();

    if (partnerRow == null) {
      throw Exception('Partner non trovato per id=$partnerId');
    }

    final int capS = (partnerRow['capacity_s'] as int?) ?? 0;
    final int capM = (partnerRow['capacity_m'] as int?) ?? 0;
    final int capL = (partnerRow['capacity_l'] as int?) ?? 0;
    final int capTotalDb = (partnerRow['capacity'] as int?) ?? 0;

    final int sumSizes = capS + capM + capL;
    final int capacityTotal = sumSizes > 0 ? sumSizes : capTotalDb;

    // 2) Intervallo richiesto dal NUOVO booking
    final DateTime requestStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      _parseHour(startTime),
      _parseMinute(startTime),
    );

    final DateTime requestEnd = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      _parseHour(endTime),
      _parseMinute(endTime),
    );

    int usedS = 0;
    int usedM = 0;
    int usedL = 0;

    // 3) Prenotazioni attive (pending / confirmed) di quel partner
    final rows = await client
        .from('partner_bookings')
        .select(
          'booking_date,end_date,start_time,end_time,bags_s,bags_m,bags_l,status',
        )
        .eq('partner_id', partnerId)
        .or('status.eq.pending,status.eq.confirmed');

    for (final raw in rows as List) {
      final map = raw as Map<String, dynamic>;

      // Giorni di inizio/fine della prenotazione salvata
      final DateTime bookingStartDay =
          DateTime.parse(map['booking_date'] as String);
      final DateTime bookingEndDay = map['end_date'] == null
          ? bookingStartDay
          : DateTime.parse(map['end_date'] as String);

      final String bStart = map['start_time'] as String;
      final String bEnd = map['end_time'] as String;

      final bookingStart = DateTime(
        bookingStartDay.year,
        bookingStartDay.month,
        bookingStartDay.day,
        _parseHour(bStart),
        _parseMinute(bStart),
      );
      final bookingEnd = DateTime(
        bookingEndDay.year,
        bookingEndDay.month,
        bookingEndDay.day,
        _parseHour(bEnd),
        _parseMinute(bEnd),
      );

      // Se non si sovrappone all'intervallo richiesto, non occupa capacità.
      if (!_intervalsOverlap(bookingStart, bookingEnd, requestStart, requestEnd)) {
        continue;
      }

      usedS += (map['bags_s'] as int? ?? 0);
      usedM += (map['bags_m'] as int? ?? 0);
      usedL += (map['bags_l'] as int? ?? 0);
    }

    final int usedTotal = usedS + usedM + usedL;

    int availableS = capS - usedS;
    int availableM = capM - usedM;
    int availableL = capL - usedL;
    int availableTotal = capacityTotal - usedTotal;

    if (availableS < 0) availableS = 0;
    if (availableM < 0) availableM = 0;
    if (availableL < 0) availableL = 0;
    if (availableTotal < 0) availableTotal = 0;

    return PartnerAvailability(
      capacityS: capS,
      capacityM: capM,
      capacityL: capL,
      capacityTotal: capacityTotal,
      usedS: usedS,
      usedM: usedM,
      usedL: usedL,
      usedTotal: usedTotal,
      availableS: availableS,
      availableM: availableM,
      availableL: availableL,
      availableTotal: availableTotal,
    );
  }

  /// Rimane per eventuali controlli legacy; NON più usato nel nuovo flusso.
  Future<bool> hasBookingForPartnerToday(String partnerId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException(
        'Devi essere autenticato per creare una prenotazione.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final startOfDayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

    final data = await client
        .from('partner_bookings')
        .select('id')
        .eq('user_id', userId)
        .eq('partner_id', partnerId)
        .neq('status', 'cancelled')
        .gte('created_at', startOfDayUtc.toIso8601String())
        .lt('created_at', endOfDayUtc.toIso8601String());

    final list = data as List;
    return list.isNotEmpty;
  }

  /// Ritorna true se il partner ha prenotazioni future (>= oggi)
  /// con status diverso da 'cancelled'.
  Future<bool> hasActiveFutureBookingsForPartner(String partnerId) async {
    final todayUtc = DateTime.now().toUtc();
    final yyyy = todayUtc.year.toString().padLeft(4, '0');
    final mm = todayUtc.month.toString().padLeft(2, '0');
    final dd = todayUtc.day.toString().padLeft(2, '0');
    final todayStr = '$yyyy-$mm-$dd';
    final data = await client
        .from('partner_bookings')
        .select('id')
        .eq('partner_id', partnerId)
        .neq('status', 'cancelled')
        .gte('booking_date', todayStr)
        .limit(1);

    final list = data as List;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = await client
        .from('partner_bookings')
        .select('booking_date, end_date, status')
        .eq('partner_id', partnerId)
        .neq('status', 'cancelled');

    for (final raw in rows) {
      final map = raw as Map<String, dynamic>;

      final DateTime startDay = DateTime.parse(map['booking_date'] as String);
      final DateTime endDay = map['end_date'] == null
          ? startDay
          : DateTime.parse(map['end_date'] as String);

      // Se l'intervallo [startDay, endDay] ha almeno un giorno >= oggi,
      // la consideriamo "futura/attiva".
      if (!endDay.isBefore(today)) {
        return true;
      }
    }

    return false;

  }


    int _parseHour(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.isEmpty) return 0;
    return int.tryParse(parts[0]) ?? 0;
  }

  int _parseMinute(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  bool _intervalsOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    // [aStart, aEnd) e [bStart, bEnd) si sovrappongono se:
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

}
