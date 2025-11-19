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

  /// Aggiorna alcuni campi base (esempio).
  Future<void> updateBasics({
    required String partnerId,
    String? name,
    String? address,
    int? capacity,
    num? price2h,
    num? pricePerDay,
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
    if (price2h != null) patch['price_2h'] = price2h;
    if (pricePerDay != null) patch['price_per_day'] = pricePerDay;
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
  Future<Partner> submitPartnerApplication({
    required String userId,
    required String name,
    required String address,
    required int capacity,
    double? price2h,
    double? pricePerDay,
    String? message,
    double? lat,
    double? lng,
  }) async {
    final uid = userId;

    // 1) Verifica se esiste già un partner associato a questo utente
    final existing = await _db
        .from('partners')
        .select()
        .eq('owner_id', uid)
        .maybeSingle();

    Map<String, dynamic> row;

    if (existing == null) {
      // INSERT: nuova attività
      row = await _db
          .from('partners')
          .insert({
            'owner_id': uid,
            'name': name,
            'address': address,
            'lat': lat,
            'lng': lng,
            'capacity': capacity,
            'price_2h': price2h,
            'price_per_day': pricePerDay,
            'status': 'pending', // in attesa di approvazione admin
            'is_active': false, // verrà messa attiva solo se approvata
            'reject_reason': null, // nessun rifiuto al primo invio
          })
          .select()
          .single();
    } else {
      // UPDATE: l'utente sta aggiornando i dati e "re-inviando" la richiesta
      row = await _db
          .from('partners')
          .update({
            'name': name,
            'address': address,
            'lat': lat,
            'lng': lng,
            'capacity': capacity,
            'price_2h': price2h,
            'price_per_day': pricePerDay,
            'status': 'pending', // reset a pending
            'is_active': false,
            'reject_reason': null, // reset motivazione rifiuto
          })
          .eq('owner_id', uid)
          .select()
          .single();
    }

    final partner = Partner.fromMap(row);

    // 2) Inserisci una nuova partner_request (storico richieste)
    await _db.from('partner_requests').insert({
      'user_id': uid,
      'partner_id': partner.id,
      'status': 'pending',
      'message': message,
    });

    return partner;
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
