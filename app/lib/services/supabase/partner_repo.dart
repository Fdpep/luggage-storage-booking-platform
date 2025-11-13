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

    final data = await _db
        .from('partners')
        .select()
        .eq('owner_id', uid)
        .limit(1);

    if ( data.isNotEmpty) {
      return Partner.fromMap(data.first);
    }
    return null;
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
}
