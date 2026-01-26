// lib/services/supabase/partner_repo.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner.dart';
import 'client.dart';
import 'dart:math' as math;

/// Repository minimale per gestire i dati Partner su Supabase.
class PartnerRepo {
  final SupabaseClient _db;
  const PartnerRepo(this._db);

  /// Accesso comodo al client Supabase globale,
  /// esposto tramite SupabaseService.
  SupabaseClient get _client => SupabaseService.client;

  /// Ritorna l'attività associata all'utente loggato (se esiste).
  Future<Partner?> getMyPartner() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;

    // Versione leggermente più pulita con maybeSingle
    final data = await _db
        .from('partners')
        .select()
        .eq('owner_id', uid)
        .maybeSingle();

    if (data == null) return null;
    return Partner.fromMap(data);
  }

  /// Carica un partner a partire dal suo id.
  /// Usato nella sezione "Le mie prenotazioni" lato utente.
  Future<Partner?> getPartnerById(String partnerId) async {
    final data = await _db
        .from('partners')
        .select()
        .eq('id', partnerId)
        .maybeSingle();

    if (data == null) return null;
    return Partner.fromMap(data);
  }

  /// Aggiorna alcuni campi base (esempio).
  Future<void> updateBasics({
    required String partnerId,
    String? name,
    String? address,

    // ===== V2 =====
    int? baseCapacityU,
    int? extraCapacityS,
    int? extraCapacityM,
    int? extraCapacityL,
    bool? acceptS,
    bool? acceptM,
    bool? acceptL,

    bool? isActive,
    bool? acceptingBookings,
    String? description,
    String? phone,
    String? rules,
    Map<String, dynamic>? openingHours,
  }) async {

    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (address != null) patch['address'] = address;
    // ===== V2 writes =====
    if (baseCapacityU != null) patch['base_capacity_u'] = baseCapacityU;
    if (extraCapacityS != null) patch['extra_capacity_s'] = extraCapacityS;
    if (extraCapacityM != null) patch['extra_capacity_m'] = extraCapacityM;
    if (extraCapacityL != null) patch['extra_capacity_l'] = extraCapacityL;
    if (acceptS != null) patch['accept_s'] = acceptS;
    if (acceptM != null) patch['accept_m'] = acceptM;
    if (acceptL != null) patch['accept_l'] = acceptL;

    if (isActive != null) patch['is_active'] = isActive;
    if (acceptingBookings != null) patch['accepting_bookings'] = acceptingBookings;

    if (description != null) patch['description'] = description;
    if (phone != null) patch['phone'] = phone;
    if (rules != null) patch['rules'] = rules;
    if (openingHours != null) patch['opening_hours'] = openingHours;

    if (patch.isEmpty) return;

    await _db.from('partners').update(patch).eq('id', partnerId);
  }

  /// Crea o aggiorna l’attività dell’utente corrente e inserisce una riga
  /// in partner_requests con stato "pending".
  ///
  /// Usato dalla schermata di registrazione partner:
  /// - se non esiste partner → INSERT in public.partners
  /// - se esiste partner → UPDATE dei campi base + reset stato a 'pending'
  /// In entrambi i casi viene creata una riga in public.partner_requests.
  /// Crea o aggiorna una richiesta partner:
  /// - se esiste già un partner per questo user → update
  /// - altrimenti → insert
  ///
  /// Ora supporta capacità per taglia (S/M/L) + capacità totale (fallback).
  /// Crea o aggiorna l’attività dell’utente corrente e inserisce una riga
  /// in partner_requests con stato "pending".
  ///
  /// NOTA: i prezzi NON sono più configurabili per partner.
  /// Le tariffe sono definite globalmente da BagDrop.
  Future<void> submitPartnerApplication({
    required String userId,
    required String name,
    required String address,

    // V2 inputs (come wizard web)
    required int baseM,
    int extraS = 0,
    int extraM = 0,
    int extraL = 0,
    bool acceptS = true,
    bool acceptM = true,
    bool acceptL = true,

    String? message,
    double? lat,
    double? lng,
    Map<String, dynamic>? openingHours,
  }) async {

    // ======================
    // CAPACITÀ V2
    // base in unità S (u): 1M=2u, 1L=4u
    // ======================
    int nnInt(int v) => v < 0 ? 0 : v;

    final baseCapacityU = nnInt(baseM) * 2;
    final exS = nnInt(extraS);
    final exM = nnInt(extraM);
    final exL = nnInt(extraL);

    if (baseCapacityU <= 0) {
      throw Exception('Capacità base non valida (minimo 1 bagaglio M).');
    }
    if (!acceptS && !acceptM && !acceptL) {
      throw const AuthException('Devi accettare almeno una taglia (S/M/L).');
    }


    // 1) Verifico se esiste già un partner per questo user
    final existing = await _client
        .from('partners')
        .select()
        .eq('owner_id', userId)
        .maybeSingle();

    Map<String, dynamic> partnerData = {
      'owner_id': userId,
      'name': name,
      'address': address,
      'base_capacity_u': baseCapacityU,
      'extra_capacity_s': exS,
      'extra_capacity_m': exM,
      'extra_capacity_l': exL,
      'accept_s': acceptS,
      'accept_m': acceptM,
      'accept_l': acceptL,
      // 'price_3h' e 'price_per_day' non vengono più impostati.
      'lat': lat,
      'lng': lng,
      'status': 'pending',
      'reject_reason': null,
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
      if (openingHours != null) 'opening_hours': openingHours, // 👈 NUOVO
    };

    if (existing == null) {
      // Nuovo partner
      partnerData['created_at'] = DateTime.now().toIso8601String();
      final inserted = await _client
          .from('partners')
          .insert(partnerData)
          .select()
          .single();

      final partnerId = inserted['id'] as String;

      await _client.from('partner_requests').insert({
        'partner_id': partnerId,
        'user_id': userId,
        'status': 'submitted',
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      // Aggiornamento partner esistente
      final partnerId = existing['id'] as String;

      await _client.from('partners').update(partnerData).eq('id', partnerId);

      await _client.from('partner_requests').insert({
        'partner_id': partnerId,
        'user_id': userId,
        'status': 'submitted',
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> setAcceptingBookings({
    required String partnerId,
    required bool accepting,
  }) async {
    await _client
        .from('partners')
        .update({'accepting_bookings': accepting})
        .eq('id', partnerId);
  }

  /// Carica la lista di partner APPROVATI e ATTIVI nelle vicinanze di un punto.
  ///
  /// [centerLat], [centerLng] → centro della ricerca (es. posizione utente).
  /// [radiusKm] → raggio di ricerca in chilometri (di default 3 km).
  ///
  /// Implementazione:
  /// - calcoliamo una "bounding box" approssimata attorno al centro
  /// - eseguiamo una query su Supabase filtrando:
  ///   - status = 'approved'
  ///   - is_active = true
  ///   - lat/lng dentro l'intervallo calcolato
  ///
  /// NOTA: questa è una semplificazione; per ricerche molto precise
  /// si potrebbe usare PostGIS, ma per una prima versione va più che bene.
  Future<List<Partner>> fetchNearbyPartners({
    required double centerLat,
    required double centerLng,
    double radiusKm = 3.0,
  }) async {
    // 1) Convertiamo il raggio in "gradi" di latitudine/longitudine.
    //
    //    Circa:
    //    - 1 grado di latitudine ≈ 111 km
    //    - 1 grado di longitudine ≈ 111 km * cos(latitudine)
    const double kmPerDegreeLat = 111.0;
    final double latDelta = radiusKm / kmPerDegreeLat;

    // Per la longitudine teniamo conto della latitudine (in radianti).
    final double latRad = centerLat * (3.1415926535 / 180.0);
    final double kmPerDegreeLng = 111.0 * math.cos(latRad);
    final double lngDelta = radiusKm / kmPerDegreeLng;

    final double minLat = centerLat - latDelta;
    final double maxLat = centerLat + latDelta;
    final double minLng = centerLng - lngDelta;
    final double maxLng = centerLng + lngDelta;

    // 2) Eseguiamo la query su Supabase.
    //
    // Filtri:
    // - status = 'approved'
    // - is_active = true
    // - lat tra [minLat, maxLat]
    // - lng tra [minLng, maxLng]
    //
    // IMPORTANTE: Assumiamo che i partner APPROVATI abbiano sempre lat/lng non null.
    final response = await _client
        .from('partners')
        .select()
        .eq('status', 'approved')
        .eq('is_active', true)
        .gte('lat', minLat)
        .lte('lat', maxLat)
        .gte('lng', minLng)
        .lte('lng', maxLng);

    // 3) Convertiamo il risultato (List<dynamic>) in List<Partner>.
    //
    // Se la tabella è vuota in quell'area, torniamo una lista vuota.
    final data = response as List<dynamic>;
    return data
        .map((raw) => Partner.fromMap(raw as Map<String, dynamic>))
        .toList();
  }
}
