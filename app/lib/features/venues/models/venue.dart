class Venue {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double minPrice; // € per giorno (min 5)
  final double distanceM; // metri

  Venue({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.minPrice,
    required this.distanceM,
  });
}
