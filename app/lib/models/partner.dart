// lib/models/partner.dart
/// Modello dati dell'attività Partner.
class Partner {
  final String id;
  final String ownerId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final Map<String, dynamic>? openingHours;
  final int capacity;
  final num? price2h;
  final num? pricePerDay;
  final bool isActive;

  const Partner({
    required this.id,
    required this.ownerId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.openingHours,
    this.capacity = 0,
    this.price2h,
    this.pricePerDay,
    this.isActive = true,
  });

  factory Partner.fromMap(Map<String, dynamic> m) {
    return Partner(
      id: m['id'] as String,
      ownerId: m['owner_id'] as String,
      name: m['name'] as String,
      address: m['address'] as String?,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      openingHours: m['opening_hours'] as Map<String, dynamic>?,
      capacity: (m['capacity'] as int?) ?? 0,
      price2h: m['price_2h'] as num?,
      pricePerDay: m['price_per_day'] as num?,
      isActive: (m['is_active'] as bool?) ?? true,
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
      'price_2h': price2h,
      'price_per_day': pricePerDay,
      'is_active': isActive,
    };
  }
}
