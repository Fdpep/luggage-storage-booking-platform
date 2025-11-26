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
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException('Devi essere autenticato per creare una prenotazione.');
    }

    // NB: controllo capacità fatto a livello app (BookingFlowScreen)
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

  /// Calcola la disponibilità attuale di un partner.
  ///
  /// Legge:
  /// - capacità S/M/L + totale dalla tabella `partners`
  /// - somma i bagagli S/M/L delle prenotazioni ATTIVE (`status != 'cancelled'`)
  ///
  /// Ritorna:
  /// - capacità per taglia + totale
  /// - usato per taglia + totale
  /// - disponibile per taglia + totale
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
    // Se la somma delle taglie è > 0, la usiamo come capacità totale;
    // altrimenti ripieghiamo sul campo capacity (compat vecchi dati).
    final int capacityTotal = sumSizes > 0 ? sumSizes : capTotalDb;

    // 2) Sommiamo i bagagli delle prenotazioni attive
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

  /// Ritorna true se l'utente corrente ha già una prenotazione
  /// per QUESTO partner OGGI (status diverso da 'cancelled').
  Future<bool> hasBookingForPartnerToday(String partnerId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw AuthException('Devi essere autenticato per creare una prenotazione.');
    }

    // Usiamo il giorno "oggi" in UTC per coerenza con created_at
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
}
