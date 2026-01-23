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
    int? capacity,
    int? capacityS,
    int? capacityM,
    int? capacityL,
    bool? isActive,
    String? description,
    String? phone,
    String? rules,
    Map<String, dynamic>? openingHours,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (address != null) patch['address'] = address;
    if (capacity != null) patch['capacity'] = capacity;
    if (capacityS != null) patch['capacity_s'] = capacityS;
    if (capacityM != null) patch['capacity_m'] = capacityM;
    if (capacityL != null) patch['capacity_l'] = capacityL;
    if (isActive != null) patch['is_active'] = isActive;
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
    int? capacity, // totale (fallback / compatibilità)
    int? capacityS,
    int? capacityM,
    int? capacityL,
    String? message,
    double? lat,
    double? lng,
    Map<String, dynamic>? openingHours,
  }) async {
    // Normalizziamo le capacità per taglia
    final capS = capacityS ?? 0;
    final capM = capacityM ?? 0;
    final capL = capacityL ?? 0;

    // Se non viene passato "capacity", usiamo la somma
    final totalCapacity = capacity ?? (capS + capM + capL);

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
      'capacity': totalCapacity,
      'capacity_s': capS,
      'capacity_m': capM,
      'capacity_l': capL,
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
        'status': 'pending',
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
        'status': 'pending',
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
