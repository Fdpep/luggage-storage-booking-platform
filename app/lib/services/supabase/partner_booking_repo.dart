import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/models/partner_booking.dart';

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
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException('Devi essere autenticato per creare una prenotazione.');
    }

    // Normalizziamo la data a "YYYY-MM-DD"
    final bookingDateStr = bookingDate.toIso8601String().split('T').first;

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
      'booking_date': bookingDateStr,
      'start_time': startTime,
      'end_time': endTime,
      // status default: 'confirmed' come da migration
    });
  }

  /// Prenotazioni dell'utente corrente (lato app utente).
  Future<List<PartnerBooking>> getMyBookings() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException('Devi essere autenticato per vedere le tue prenotazioni.');
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

  /// Calcola la disponibilità per UN INTERVALLO specifico in un certo giorno.
  ///
  /// [bookingDate] → giorno (solo data)
  /// [startTime], [endTime] → stringhe "HH:MM" (es. "10:00" → "13:00")
  ///
  /// Consideriamo solo le prenotazioni:
  /// - stesso partner
  /// - stesso booking_date
  /// - status != cancelled
  /// - che SI SOVRAPPONGONO all'intervallo (start_time < endTime E end_time > startTime)
  Future<PartnerAvailability> getPartnerAvailabilityForInterval({
    required String partnerId,
    required DateTime bookingDate,
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

    final bookingDateStr = bookingDate.toIso8601String().split('T').first;

    // 2) Prenotazioni che si sovrappongono all'intervallo
    //
    // Condizione di overlap: start_time < endTime AND end_time > startTime
    final bookingsData = await client
        .from('partner_bookings')
        .select('bags_s, bags_m, bags_l, status, booking_date, start_time, end_time')
        .eq('partner_id', partnerId)
        .eq('booking_date', bookingDateStr)
        .neq('status', 'cancelled')
        .lt('start_time', endTime)
        .gt('end_time', startTime);

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

  /// Rimane per eventuali controlli legacy; NON più usato nel nuovo flusso.
  Future<bool> hasBookingForPartnerToday(String partnerId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException('Devi essere autenticato per creare una prenotazione.');
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
    return list.isNotEmpty;
  }


}


