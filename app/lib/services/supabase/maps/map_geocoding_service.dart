import 'dart:convert';

import 'package:http/http.dart' as http;

/// Risultato di una richiesta di geocoding:
/// contiene coordinate e indirizzo formattato.
class GeocodingResult {
  final double lat;
  final double lng;
  final String formattedAddress;

  const GeocodingResult({
    required this.lat,
    required this.lng,
    required this.formattedAddress,
  });
}

/// Servizio per convertire un indirizzo testuale (es. "Via Roma 10, Milano")
/// in coordinate geografiche (latitudine/longitudine) usando la
/// Google Geocoding API.
///
/// NON legge la API key da solo: gliela passiamo dall'esterno
/// così sei libero di decidere da dove arriva (es. dotenv).
class MapGeocodingService {
  final String apiKey;

  const MapGeocodingService({required this.apiKey});

  /// Effettua una richiesta di geocoding.
  ///
  /// Restituisce:
  /// - GeocodingResult se la chiamata va a buon fine
  /// - null se:
  ///   - indirizzo vuoto
  ///   - richiesta fallita
  ///   - la API non trova risultati
  Future<GeocodingResult?> geocodeAddress(String address) async {
    if (address.trim().isEmpty) return null;

    // 1) Costruiamo la URI per la Google Geocoding API.
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address,
      'key': apiKey,
    });

    // 2) Eseguiamo la richiesta HTTP.
    final resp = await http.get(uri);

    if (resp.statusCode != 200) {
      // Errore di rete o server.
      return null;
    }

    // 3) Decodifichiamo il JSON.
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;

    final status = json['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') {
      // 👇 LOG DI DEBUG: lo vedi nel terminale di Flutter
      // (ti dirà se è REQUEST_DENIED, API_KEY_INVALID, ZERO_RESULTS, ecc.)
      // ignore: avoid_print
      print(
        'Geocoding fallito. status=$status, error=${json['error_message']}',
      );
      return null;
    }

    final results = json['results'] as List<dynamic>;
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final geometry = first['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;

    final double lat = (location['lat'] as num).toDouble();
    final double lng = (location['lng'] as num).toDouble();
    final String formattedAddress = first['formatted_address'] as String;

    return GeocodingResult(
      lat: lat,
      lng: lng,
      formattedAddress: formattedAddress,
    );
  }
}
