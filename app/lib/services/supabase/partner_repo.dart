// lib/services/supabase/partner_repo.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner.dart';

/// Repository minimale per gestire i dati Partner su Supabase.
class PartnerRepo {
  final SupabaseClient _db;
  const PartnerRepo(this._db);

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
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (address != null) patch['address'] = address;
    if (capacity != null) patch['capacity'] = capacity;
    if (price2h != null) patch['price_2h'] = price2h;
    if (pricePerDay != null) patch['price_per_day'] = pricePerDay;
    if (isActive != null) patch['is_active'] = isActive;

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
    required String name,
    required String address,
    required int capacity,
    double? price2h,
    double? pricePerDay,
    String? message,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Utente non autenticato');
    }

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
            'capacity': capacity,
            'price_2h': price2h,
            'price_per_day': pricePerDay,
            'status': 'pending',      // in attesa di approvazione admin
            'is_active': false,       // verrà messa attiva solo se approvata
            'reject_reason': null,    // nessun rifiuto al primo invio
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
            'capacity': capacity,
            'price_2h': price2h,
            'price_per_day': pricePerDay,
            'status': 'pending',      // reset a pending
            'reject_reason': null,    // reset motivazione rifiuto
          })
          .eq('owner_id', uid)
          .select()
          .single() ;
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
}
