import 'package:supabase_flutter/supabase_flutter.dart';

import '../client.dart';
import '../../../models/partner_photo.dart';

/// Repository per accedere ai metadati delle foto dei partner
/// (tabella `public.partner_photos`).
///
/// Qui NON gestiamo i bytes delle immagini, solo:
/// - insert/update/delete dei record
/// - query per recuperare le foto di un partner.
class PartnerPhotoRepo {
  const PartnerPhotoRepo();

  /// Client Supabase globale.
  SupabaseClient get _client => SupabaseService.client;

  /// Restituisce tutte le foto di un partner, ordinate per sort_order.
  Future<List<PartnerPhoto>> fetchPhotosForPartner(String partnerId) async {
    final response = await _client
        .from('partner_photos')
        .select()
        .eq('partner_id', partnerId)
        .order('sort_order', ascending: true);

    final data = response as List<dynamic>;
    return data
        .map((raw) => PartnerPhoto.fromMap(raw as Map<String, dynamic>))
        .toList();
  }

  /// Restituisce la foto di copertina di un partner, se presente.
  Future<PartnerPhoto?> fetchCoverPhoto(String partnerId) async {
    final response = await _client
        .from('partner_photos')
        .select()
        .eq('partner_id', partnerId)
        .eq('is_cover', true)
        .order('sort_order', ascending: true)
        .limit(1);

    final data = response as List<dynamic>;
    if (data.isEmpty) return null;
    return PartnerPhoto.fromMap(data.first as Map<String, dynamic>);
  }

  /// Inserisce un nuovo record nella tabella `partner_photos`.
  ///
  /// Di solito verrà chiamato dopo aver caricato l'immagine
  /// su Storage e ottenuto il relativo URL.
  Future<PartnerPhoto> insertPhoto({
    required String partnerId,
    required String url,
    bool isCover = false,
    int sortOrder = 0,
  }) async {
    final payload = {
      'partner_id': partnerId,
      'url': url,
      'is_cover': isCover,
      'sort_order': sortOrder,
    };

    final response = await _client
        .from('partner_photos')
        .insert(payload)
        .select()
        .single();

    return PartnerPhoto.fromMap(response);
  }

  /// Aggiorna i metadati di una foto (es. per impostare la cover
  /// o cambiare l'ordine).
  Future<PartnerPhoto> updatePhoto({
    required String photoId,
    bool? isCover,
    int? sortOrder,
  }) async {
    final Map<String, dynamic> patch = {};
    if (isCover != null) patch['is_cover'] = isCover;
    if (sortOrder != null) patch['sort_order'] = sortOrder;

    final response = await _client
        .from('partner_photos')
        .update(patch)
        .eq('id', photoId)
        .select()
        .single();

    return PartnerPhoto.fromMap(response);
  }

  /// Elimina una foto (solo metadati nel DB).
  /// Se vuoi, in futuro puoi anche eliminare il file dallo Storage.
  Future<void> deletePhoto(String photoId) async {
    await _client
        .from('partner_photos')
        .delete()
        .eq('id', photoId);
  }
}
