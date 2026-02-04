import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/models/partner_booking.dart';

int _clamp0(int v) => v < 0 ? 0 : v;

/// Fallback per derivare una base_u se nel DB non c'è ancora base_capacity_u.
/// 1S = 1u, 1M = 2u, 1L = 4u.
int _legacyToBaseU({
  required int capS,
  required int capM,
  required int capL,
  required int totalM,
}) {
  if (capM > 0) return capM * 2;
  if (capS > 0) return capS;
  if (capL > 0) return capL * 4;
  if (totalM > 0) return totalM * 2;
  return 0;
}

/// Calcola usato/available con regola:
/// - prima consumi extra (per taglia)
/// - poi consumi base_capacity_u in unità (1S=1u,1M=2u,1L=4u)
PartnerAvailability _computeAvailabilityV2({
  required int baseU,
  required int extraS,
  required int extraM,
  required int extraL,
  required bool acceptS,
  required bool acceptM,
  required bool acceptL,
  required int usedS,
  required int usedM,
  required int usedL,
}) {
  // Se una taglia non è accettata, gli extra per quella taglia non contano
  final exS = acceptS ? _clamp0(extraS) : 0;
  final exM = acceptM ? _clamp0(extraM) : 0;
  final exL = acceptL ? _clamp0(extraL) : 0;

  final bU = _clamp0(baseU);

  // Extra consumati per taglia
  final usedExtraS = (acceptS) ? (usedS <= exS ? usedS : exS) : 0;
  final usedExtraM = (acceptM) ? (usedM <= exM ? usedM : exM) : 0;
  final usedExtraL = (acceptL) ? (usedL <= exL ? usedL : exL) : 0;

  // Parte che “sfora” sugli extra -> va in base
  final remS = acceptS ? _clamp0(usedS - usedExtraS) : 0; // in unità S
  final remM = acceptM ? _clamp0(usedM - usedExtraM) : 0; // in bagagli M
  final remL = acceptL ? _clamp0(usedL - usedExtraL) : 0; // in bagagli L

  final baseUsedU = remS * 1 + remM * 2 + remL * 4;
  final baseAvailableU = _clamp0(bU - baseUsedU);

  // Extra rimasti
  final extraRemainingS = _clamp0(exS - usedExtraS);
  final extraRemainingM = _clamp0(exM - usedExtraM);
  final extraRemainingL = _clamp0(exL - usedExtraL);

  // Capacità "massima mostrabile" per taglia (extra + tutto il base residuo convertito)
  final capS = acceptS ? (exS + bU) : 0; // S può usare 1u ciascuno
  final capM = acceptM ? (exM + (bU ~/ 2)) : 0; // M usa 2u
  final capL = acceptL ? (exL + (bU ~/ 4)) : 0; // L usa 4u

  // Disponibili per taglia = extra rimasti + base residuo convertito
  final availableS = acceptS ? (extraRemainingS + baseAvailableU) : 0;
  final availableM = acceptM ? (extraRemainingM + (baseAvailableU ~/ 2)) : 0;
  final availableL = acceptL ? (extraRemainingL + (baseAvailableU ~/ 4)) : 0;

  // Totali in unità (per barra/controllo generale)
  final capacityTotalU = bU + (exS * 1) + (exM * 2) + (exL * 4);
  final usedTotalU =
      baseUsedU + (usedExtraS * 1) + (usedExtraM * 2) + (usedExtraL * 4);
  final availableTotalU = _clamp0(capacityTotalU - usedTotalU);

  return PartnerAvailability(
    capacityS: capS,
    capacityM: capM,
    capacityL: capL,
    capacityTotal: capacityTotalU,
    usedS: usedS,
    usedM: usedM,
    usedL: usedL,
    usedTotal: usedTotalU,
    availableS: availableS,
    availableM: availableM,
    availableL: availableL,
    availableTotal: availableTotalU,
    acceptS: acceptS,
    acceptM: acceptM,
    acceptL: acceptL,
  );
}

/// DTO per la disponibilità di un partner.
///
/// NOTA:
/// - capacityTotal / usedTotal / availableTotal sono espressi in "unità equivalenti"
///   dove 1S = 1, 1M = 2, 1L = 4 (cioè "mezze M").
///
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

  // ✅ V2: taglie accettate
  final bool acceptS;
  final bool acceptM;
  final bool acceptL;

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
    required this.acceptS,
    required this.acceptM,
    required this.acceptL,
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

  Future<String> createBooking({
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
    required DateTime endDate,
    required String endTime,
    required DateTime endDateRequested,
    required String endTimeRequested,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Utente non autenticato');
    }

    final row = await client
        .from('partner_bookings')
        .insert({
          'partner_id': partnerId,
          'user_id': uid,
          'status': 'confirmed', // o quello che usi tu come stato iniziale
          'contact_first_name': firstName,
          'contact_last_name': lastName,
          'contact_phone': phone,
          'contact_email': email,
          'bags_s': bagsS,
          'bags_m': bagsM,
          'bags_l': bagsL,
          'notes': notes,
          'booking_date': bookingDate.toIso8601String(),
          'start_time': startTime, // "HH:MM:SS"
          'end_date': endDate.toIso8601String(),
          'end_time': endTime, // "HH:MM:SS"
          'end_date_requested': endDateRequested.toIso8601String(),
          'end_time_requested': endTimeRequested, // "HH:MM:SS"
        })
        .select('id')
        .single();

    return row['id'] as String;
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

  Future<PartnerAvailability> getPartnerAvailability(String partnerId) async {
    final partnerRow = await client
        .from('partners')
        .select(
          'base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l, '
          'accept_s, accept_m, accept_l, '
          'capacity_s, capacity_m, capacity_l, capacity',
        )
        .eq('id', partnerId)
        .maybeSingle();

    if (partnerRow == null) {
      throw Exception('Partner non trovato per id=$partnerId');
    }

    final int baseU =
        (partnerRow['base_capacity_u'] as int?) ??
        _legacyToBaseU(
          capS: (partnerRow['capacity_s'] as int?) ?? 0,
          capM: (partnerRow['capacity_m'] as int?) ?? 0,
          capL: (partnerRow['capacity_l'] as int?) ?? 0,
          totalM: (partnerRow['capacity'] as int?) ?? 0,
        );

    final int extraS = (partnerRow['extra_capacity_s'] as int?) ?? 0;
    final int extraM = (partnerRow['extra_capacity_m'] as int?) ?? 0;
    final int extraL = (partnerRow['extra_capacity_l'] as int?) ?? 0;

    final bool acceptS = (partnerRow['accept_s'] as bool?) ?? true;
    final bool acceptM = (partnerRow['accept_m'] as bool?) ?? true;
    final bool acceptL = (partnerRow['accept_l'] as bool?) ?? true;

    final bookingsData = await client
        .from('partner_bookings')
        .select('bags_s, bags_m, bags_l, status')
        .eq('partner_id', partnerId)
        .inFilter('status', ['pending', 'confirmed', 'in_store']);

    int usedS = 0;
    int usedM = 0;
    int usedL = 0;

    for (final row in bookingsData as List) {
      usedS += (row['bags_s'] as int?) ?? 0;
      usedM += (row['bags_m'] as int?) ?? 0;
      usedL += (row['bags_l'] as int?) ?? 0;
    }

    return _computeAvailabilityV2(
      baseU: baseU,
      extraS: extraS,
      extraM: extraM,
      extraL: extraL,
      acceptS: acceptS,
      acceptM: acceptM,
      acceptL: acceptL,
      usedS: usedS,
      usedM: usedM,
      usedL: usedL,
    );
  }

  Future<void> rejectBooking({
    required String bookingId,
    required String reason,
  }) async {
    final r = reason.trim();
    if (r.isEmpty) {
      throw Exception('Motivazione obbligatoria.');
    }

    await client.rpc(
      'reject_partner_booking',
      params: {'p_booking_id': bookingId, 'p_reason': r},
    );

    // TODO(REFUND): qui in futuro avvierai rimborso Stripe del pagamento base (se già incassato)
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
    required DateTime bookingDate, // compat: ignorato
    required DateTime startDate,
    required DateTime endDate,
    required String startTime,
    required String endTime,
  }) async {
    final partnerRow = await client
        .from('partners')
        .select(
          'base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l, '
          'accept_s, accept_m, accept_l, '
          'capacity_s, capacity_m, capacity_l, capacity',
        )
        .eq('id', partnerId)
        .maybeSingle();

    if (partnerRow == null) {
      throw Exception('Partner non trovato per id=$partnerId');
    }

    final int baseU =
        (partnerRow['base_capacity_u'] as int?) ??
        _legacyToBaseU(
          capS: (partnerRow['capacity_s'] as int?) ?? 0,
          capM: (partnerRow['capacity_m'] as int?) ?? 0,
          capL: (partnerRow['capacity_l'] as int?) ?? 0,
          totalM: (partnerRow['capacity'] as int?) ?? 0,
        );

    final int extraS = (partnerRow['extra_capacity_s'] as int?) ?? 0;
    final int extraM = (partnerRow['extra_capacity_m'] as int?) ?? 0;
    final int extraL = (partnerRow['extra_capacity_l'] as int?) ?? 0;

    final bool acceptS = (partnerRow['accept_s'] as bool?) ?? true;
    final bool acceptM = (partnerRow['accept_m'] as bool?) ?? true;
    final bool acceptL = (partnerRow['accept_l'] as bool?) ?? true;

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

    final rows = await client
        .from('partner_bookings')
        .select(
          'booking_date,end_date,start_time,end_time,bags_s,bags_m,bags_l,status',
        )
        .eq('partner_id', partnerId)
        .or('status.eq.pending,status.eq.confirmed,status.eq.in_store');

    for (final raw in rows as List) {
      final map = raw as Map<String, dynamic>;

      final DateTime bookingStartDay = DateTime.parse(
        map['booking_date'] as String,
      );
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

      if (!_intervalsOverlap(
        bookingStart,
        bookingEnd,
        requestStart,
        requestEnd,
      )) {
        continue;
      }

      usedS += (map['bags_s'] as int?) ?? 0;
      usedM += (map['bags_m'] as int?) ?? 0;
      usedL += (map['bags_l'] as int?) ?? 0;
    }

    return _computeAvailabilityV2(
      baseU: baseU,
      extraS: extraS,
      extraM: extraM,
      extraL: extraL,
      acceptS: acceptS,
      acceptM: acceptM,
      acceptL: acceptL,
      usedS: usedS,
      usedM: usedM,
      usedL: usedL,
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
        .inFilter('status', ['pending', 'confirmed', 'in_store'])
        .gte('created_at', startOfDayUtc.toIso8601String())
        .lt('created_at', endOfDayUtc.toIso8601String());

    final list = data as List;
    return list.isNotEmpty;
  }

  /// Ritorna true se il partner ha prenotazioni che BLOCCANO la modifica orari/capacità:
  /// - in_store (o dropoff_effective_at valorizzato) finché non c'è pickup_effective_at
  /// - confirmed/pending solo se il pickup previsto è >= adesso
  ///
  /// Non consideriamo: cancelled / rejected / expired / completed ecc.
  Future<bool> hasActiveFutureBookingsForPartner(String partnerId) async {
    DateTime? parseDateTime(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v.toLocal();
      if (v is String) return DateTime.parse(v).toLocal();
      return null;
    }

    DateTime parseDate(dynamic v) {
      if (v is DateTime) return DateTime(v.year, v.month, v.day);
      if (v is String) {
        final dt = DateTime.parse(v);
        return DateTime(dt.year, dt.month, dt.day);
      }
      throw ArgumentError('Invalid Date value: $v');
    }

    int parseHour(String hhmm) {
      final parts = hhmm.split(':');
      return parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    }

    int parseMinute(String hhmm) {
      final parts = hhmm.split(':');
      return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    }

    DateTime combineDateAndTime(DateTime date, String timeStr) {
      final t = (timeStr.isEmpty) ? '00:00:00' : timeStr;
      return DateTime(
        date.year,
        date.month,
        date.day,
        parseHour(t),
        parseMinute(t),
      );
    }

    final now = DateTime.now();

    // Prendiamo SOLO gli stati che possono bloccare (gli altri non ci interessano proprio).
    final rows = await client
        .from('partner_bookings')
        .select(
          'status, booking_date, end_date, end_time, pickup_planned_at, '
          'dropoff_effective_at, pickup_effective_at',
        )
        .eq('partner_id', partnerId)
        .inFilter('status', ['pending', 'confirmed', 'in_store']);

    for (final raw in (rows as List)) {
      final map = raw as Map<String, dynamic>;
      final status = (map['status'] as String? ?? '').toLowerCase();

      final dropoffEff = parseDateTime(map['dropoff_effective_at']);
      final pickupEff = parseDateTime(map['pickup_effective_at']);

      // ✅ Se è in deposito (o risulta check-in effettivo) e non c'è ancora check-out → blocca SEMPRE.
      if (pickupEff == null && (status == 'in_store' || dropoffEff != null)) {
        return true;
      }

      // ✅ Per confirmed/pending: blocca solo se il pickup previsto è nel futuro (>= adesso).
      if (status == 'confirmed' || status == 'pending') {
        DateTime? plannedPickup = parseDateTime(map['pickup_planned_at']);

        // Fallback per record vecchi (se pickup_planned_at non c'è)
        if (plannedPickup == null) {
          final startDay = parseDate(map['booking_date']);
          final endDay = map['end_date'] == null
              ? startDay
              : parseDate(map['end_date']);
          final endTime = (map['end_time'] as String?) ?? '23:59:00';
          plannedPickup = combineDateAndTime(endDay, endTime);
        }

        if (!plannedPickup.isBefore(now)) {
          return true;
        }
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

  Future<Map<String, dynamic>> processBookingCode({
    required String code,
    bool force = false,
  }) async {
    final res = await client.rpc(
      'process_booking_code',
      params: {'p_code': code, 'p_force': force},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<PartnerBooking?> getBookingById(String bookingId) async {
    final row = await client
        .from('partner_bookings')
        .select()
        .eq('id', bookingId)
        .maybeSingle();

    if (row == null) return null;
    return PartnerBooking.fromMap(row as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> cancelBookingByUser({
    required String bookingId,
    String? reason,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Utente non autenticato');

    final res = await client.rpc(
      'cancel_my_booking',
      params: {
        'p_booking_id': bookingId,
        'p_reason': reason, // puoi lasciare null per ora
      },
    );

    final map = Map<String, dynamic>.from(res as Map);
    final ok = map['ok'] == true;

    if (!ok) {
      // per sicurezza, ma la funzione di solito fa RAISE EXCEPTION
      throw Exception(map['message'] ?? 'Annullamento non riuscito.');
    }

    return map;
  }
}
