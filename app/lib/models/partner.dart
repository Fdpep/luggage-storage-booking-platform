/// Modello dati per la tabella public.partners
class Partner {
  final String id;
  final String ownerId; // FK verso auth.users.id
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final Map<String, dynamic>? openingHours;

  // ======================
  // CAPACITÀ V2 (DB)
  // base in "unità S" (u): 1S = 1u, 1M = 2u, 1L = 4u
  // ======================
  final int baseCapacityU;      // DB: base_capacity_u
  final int extraCapacityS;     // DB: extra_capacity_s
  final int extraCapacityM;     // DB: extra_capacity_m
  final int extraCapacityL;     // DB: extra_capacity_l

  final bool acceptS;           // DB: accept_s
  final bool acceptM;           // DB: accept_m
  final bool acceptL;           // DB: accept_l

  // ======================
  // LEGACY (tenuti per compatibilità, ma NON più usati come truth)
  // ======================
  @Deprecated('Legacy: non usare come source of truth. Usa V2.')
  final int capacity;

  @Deprecated('Legacy: non usare come source of truth. Usa V2.')
  final int capacityS;

  @Deprecated('Legacy: non usare come source of truth. Usa V2.')
  final int capacityM;

  @Deprecated('Legacy: non usare come source of truth. Usa V2.')
  final int capacityL;


  /// [LEGACY] Prezzo per 2h specifico del partner.
  /// Non viene più usato nella logica dell’app:
  /// le tariffe sono globali e definite in [BagDropPricing].
  @Deprecated('Prezzo per-partner non più supportato. Usa BagDropPricing.')
  final double? price2h;

  /// [LEGACY] Prezzo per giorno specifico del partner.
  /// Non viene più usato nella logica dell’app:
  /// le tariffe sono globali e definite in [BagDropPricing].
  @Deprecated('Prezzo per-partner non più supportato. Usa BagDropPricing.')
  final double? pricePerDay;

  final bool isActive;
  final bool acceptingBookings;

  /// Nuovi campi descrittivi per la scheda locale
  final String? description; // descrizione breve attività
  final String? phone; // contatto telefonico
  final String? rules; // regole (peso massimo, oggetti vietati, ecc.)

  /// Stato della richiesta: 'pending' | 'approved' | 'rejected'
  final String status;

  /// Motivo del rifiuto (compilato dall'admin, opzionale)
  final String? rejectReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Partner({
    required this.id,
    required this.ownerId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.openingHours,
    // V2
    this.baseCapacityU = 0,
    this.extraCapacityS = 0,
    this.extraCapacityM = 0,
    this.extraCapacityL = 0,
    this.acceptS = true,
    this.acceptM = true,
    this.acceptL = true,

    // legacy (fallback)
    this.capacity = 0,
    this.capacityS = 0,
    this.capacityM = 0,
    this.capacityL = 0,
   // Campi prezzo legacy (non più usati dalla UI).
    this.price2h,
    this.pricePerDay,
    required this.acceptingBookings,
    this.isActive = true,
    this.status = 'pending',
    this.description,
    this.phone,
    this.rules,
    this.rejectReason,
    this.createdAt,
    this.updatedAt,
  });

  factory Partner.fromMap(Map<String, dynamic> map) {
    return Partner(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      openingHours: map['opening_hours'] as Map<String, dynamic>?,

      // ====== V2 (preferiti) ======
      baseCapacityU: (map['base_capacity_u'] as int?)
          ?? _legacyToBaseU(
            capS: (map['capacity_s'] as int?) ?? 0,
            capM: (map['capacity_m'] as int?) ?? 0,
            capL: (map['capacity_l'] as int?) ?? 0,
            total: (map['capacity'] as int?) ?? 0,
          ),

      extraCapacityS: (map['extra_capacity_s'] as int?) ?? 0,
      extraCapacityM: (map['extra_capacity_m'] as int?) ?? 0,
      extraCapacityL: (map['extra_capacity_l'] as int?) ?? 0,

      acceptS: (map['accept_s'] as bool?) ?? true,
      acceptM: (map['accept_m'] as bool?) ?? true,
      acceptL: (map['accept_l'] as bool?) ?? true,

      // ====== LEGACY (solo per compat) ======
      capacity: (map['capacity'] as int?) ?? 0,
      capacityS: (map['capacity_s'] as int?) ?? 0,
      capacityM: (map['capacity_m'] as int?) ?? 0,
      capacityL: (map['capacity_l'] as int?) ?? 0,

      // Prezzi legacy per-partner: non più usati a livello di logica,
      // ma ancora letti per compatibilità con il DB esistente.
      price2h: (map['price_3h'] as num?)?.toDouble(),
      pricePerDay: (map['price_per_day'] as num?)?.toDouble(),
      isActive: (map['is_active'] as bool?) ?? true,
      acceptingBookings: (map['accepting_bookings'] as bool?) ?? true,
      description: map['description'] as String?,
      phone: map['phone'] as String?,
      rules: map['rules'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      rejectReason: map['reject_reason'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.tryParse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'opening_hours': openingHours,
      // ===== V2 =====
      'base_capacity_u': baseCapacityU,
      'extra_capacity_s': extraCapacityS,
      'extra_capacity_m': extraCapacityM,
      'extra_capacity_l': extraCapacityL,
      'accept_s': acceptS,
      'accept_m': acceptM,
      'accept_l': acceptL,

      // ===== Legacy (solo se ti serve ancora, altrimenti puoi rimuoverli) =====
      'capacity': capacity,
      'capacity_s': capacityS,
      'capacity_m': capacityM,
      'capacity_l': capacityL,

         // Campi prezzo legacy: non più aggiornati dall'app,
      // ma ancora presenti nel modello finché le colonne esistono nel DB.
      'price_3h': price2h,
      'price_per_day': pricePerDay,
      'is_active': isActive,
      'accepting_bookings': acceptingBookings,
      'description': description,
      'phone': phone,
      'rules': rules,
      'status': status,
      'reject_reason': rejectReason,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Helper comodi per la UI
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' && isActive;
  bool get isRejected => status == 'rejected';


    // -----------------------
  // CAPACITÀ V2: computed
  // -----------------------

  /// Base in M (solo display/UI)
  int get baseM => baseCapacityU ~/ 2;

  /// Equivalenze base (solo UI)
  int get baseS => baseCapacityU;          // 1S = 1u
  int get baseL => baseCapacityU ~/ 4;     // 1L = 4u

  /// Capacità effettive per taglia (quelle "vere" che devi mostrare)
  int get capS => acceptS ? (baseCapacityU + extraCapacityS) : 0;
  int get capM => acceptM ? ((baseCapacityU ~/ 2) + extraCapacityM) : 0;
  int get capL => acceptL ? ((baseCapacityU ~/ 4) + extraCapacityL) : 0;

  /// Totale "reale" in unità S (u): S*1 + M*2 + L*4
  int get totalU => (capS * 1) + (capM * 2) + (capL * 4);

  /// Per UI: almeno una taglia attiva
  bool get hasAnySizeEnabled => acceptS || acceptM || acceptL;

  // fallback: se DB non ha v2, proviamo a derivare una base decente dai legacy.
  static int _legacyToBaseU({
    required int capS,
    required int capM,
    required int capL,
    required int total,
  }) {
    // Se ho capM legacy, lo uso come base M "approssimata" (1M=2u)
    if (capM > 0) return capM * 2;

    // Se ho capS, lo uso come base_u diretta
    if (capS > 0) return capS;

    // Se ho capL, lo converto
    if (capL > 0) return capL * 4;

    // Ultimo fallback
    if (total > 0) return total * 2; // approssimazione "alla buona"
    return 0;
  }

}
