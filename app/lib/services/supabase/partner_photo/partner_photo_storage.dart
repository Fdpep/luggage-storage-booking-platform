import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../client.dart';

/// Servizio per gestire il caricamento delle foto dei partner
/// su Supabase Storage.
///
/// Questo livello si occupa SOLO di:
/// - scegliere il bucket
/// - generare un path ordinato (es. partnerId/nomefile)
/// - caricare i bytes
/// - restituire l'URL pubblico (o firmato)
class PartnerPhotoStorage {
  const PartnerPhotoStorage();

  /// Bucket di Supabase Storage dove salviamo le foto dei partner.
  ///
  /// Assicurati di aver creato questo bucket nel pannello Supabase,
  /// con policy adeguate (es. lettura pubblica delle immagini).
  static const String _bucketName = 'partner-photos';

  /// Accesso comodo al client globale tramite SupabaseService.
  SupabaseClient get _client => SupabaseService.client;

  /// Carica una foto nel bucket `partner-photos` sotto la cartella
  /// del partner (es. "partnerId/nomefile.jpg").
  ///
  /// Parametri:
  /// - [partnerId] → id del partner, usato come "cartella" logica
  /// - [fileName] → nome del file (es. "cover.jpg", "1.jpg", ecc.)
  /// - [bytes] → contenuto dell'immagine in memoria
  /// - [contentType] → tipo MIME (es. "image/jpeg", "image/png")
  ///
  /// Restituisce:
  /// - l'URL pubblico (o firmato) dell'immagine, da salvare poi
  ///   nella tabella `partner_photos`.
  Future<String> uploadPartnerPhoto({
    required String partnerId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    // 1) Costruiamo il path logico nel bucket:
    //    es. "af3e...-uuid/cover.jpg"
    final String path = '$partnerId/$fileName';

    // 2) Carichiamo i bytes nel bucket.
    //
    // Se il file esiste già, puoi decidere se sovrascriverlo.
    await _client.storage.from(_bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true, // true → sovrascrive se esiste
          ),
        );

    // 3) Otteniamo l'URL pubblico del file.
    //
    // Se il bucket è pubblico, getPublicUrl restituisce un URL
    // direttamente utilizzabile nella UI (Image.network).
    final String publicUrl =
        _client.storage.from(_bucketName).getPublicUrl(path);

    return publicUrl;
  }
}
