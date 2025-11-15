/// Modello dati per la tabella `public.partner_photos`.
///
/// Ogni record rappresenta una singola foto di un partner,
/// salvata su Supabase Storage. In questo model teniamo solo
/// i metadati (URL, cover, ordine, ecc.).
class PartnerPhoto {
  final String id;
  final String partnerId;   // FK verso partners.id
  final String url;         // URL pubblico/firmato dell'immagine
  final bool isCover;       // true se è la foto di copertina
  final int sortOrder;      // per ordinare le foto nella galleria

  final DateTime? createdAt;

  const PartnerPhoto({
    required this.id,
    required this.partnerId,
    required this.url,
    this.isCover = false,
    this.sortOrder = 0,
    this.createdAt,
  });

  /// Costruttore da mappa (una riga del DB Supabase).
  factory PartnerPhoto.fromMap(Map<String, dynamic> map) {
    return PartnerPhoto(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String,
      url: map['url'] as String,
      isCover: (map['is_cover'] as bool?) ?? false,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
    );
  }

  /// Conversione a mappa per insert/update su Supabase.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partner_id': partnerId,
      'url': url,
      'is_cover': isCover,
      'sort_order': sortOrder,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
