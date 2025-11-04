import 'package:supabase_flutter/supabase_flutter.dart';
import '../../venues/models/venue.dart';

class VenueService {
  final _db = Supabase.instance.client;

  Future<List<Venue>> fetchVenues() async {
    final data = await _db
        .from('venues')
        .select('id, name, address, lat, lng, min_price')
        .order('name');

    return (data as List).map((row) {
      return Venue(
        id: row['id'] as String,
        name: row['name'] as String,
        address: row['address'] as String,
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
        minPrice: (row['min_price'] as num).toDouble(),
        distanceM: 0,
      );
    }).toList();
  }
}
