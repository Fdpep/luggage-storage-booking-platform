import 'dart:convert';
import 'package:http/http.dart' as http;

/// Suggerimento di luogo (per l’autocomplete).
class PlaceSuggestion {
  final String description;
  final String placeId;

  const PlaceSuggestion({
    required this.description,
    required this.placeId,
  });
}

/// Service per chiamare la Google Places Autocomplete API.
class PlacesAutocompleteService {
  final String apiKey;

  const PlacesAutocompleteService({required this.apiKey});

  Future<List<PlaceSuggestion>> fetchSuggestions(String input) async {
    final query = input.trim();
    if (query.length < 3) return [];

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': apiKey,
        'language': 'it',
      },
    );

    final resp = await http.get(uri);
    if (resp.statusCode != 200) return [];

    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final status = json['status'] as String? ?? 'UNKNOWN';

    if (status != 'OK' && status != 'ZERO_RESULTS') {
      // ignore: avoid_print
      print('Places autocomplete fallito. status=$status');
      return [];
    }

    final List<dynamic> predictions = json['predictions'] as List<dynamic>;
    return predictions.map((p) {
      final map = p as Map<String, dynamic>;
      return PlaceSuggestion(
        description: map['description'] as String,
        placeId: map['place_id'] as String,
      );
    }).toList();
  }
}
