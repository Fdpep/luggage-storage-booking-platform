/// Modello dati per la tabella public.partners
class Partner {
  final String id;
  final String ownerId; // FK verso auth.users.id
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final Map<String, dynamic>? openingHours;

  /// Capacità totale (ridondante: somma di S+M+L, ma utile per compat e query veloci)
  final int capacity;

  /// Nuove capacità per taglia
  final int capacityS; // capacità bagagli SMALL
  final int capacityM; // capacità bagagli MEDIUM
  final int capacityL; // capacità bagagli LARGE

  final double? price2h;
  final double? pricePerDay;
  final bool isActive;

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
    this.capacity = 0,
    this.capacityS = 0,
    this.capacityM = 0,
    this.capacityL = 0,
    this.price2h,
    this.pricePerDay,
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

      capacity: (map['capacity'] as int?) ?? 0,
      capacityS: (map['capacity_s'] as int?) ?? 0,
      capacityM: (map['capacity_m'] as int?) ?? 0,
      capacityL: (map['capacity_l'] as int?) ?? 0,

      price2h: (map['price_2h'] as num?)?.toDouble(),
      pricePerDay: (map['price_per_day'] as num?)?.toDouble(),
      isActive: (map['is_active'] as bool?) ?? true,
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
      'capacity': capacity,
      'capacity_s': capacityS,
      'capacity_m': capacityM,
      'capacity_l': capacityL,
      'price_2h': price2h,
      'price_per_day': pricePerDay,
      'is_active': isActive,
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
}
