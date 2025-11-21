import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // kIsWeb + debugPrint

/// Suggerimento di luogo (per l’autocomplete).
class PlaceSuggestion {
  final String description;
  final String placeId;

  const PlaceSuggestion({required this.description, required this.placeId});
}

/// Service per chiamare la Google Places Autocomplete API.
class PlacesAutocompleteService {
  final String apiKey;

  const PlacesAutocompleteService({required this.apiKey});

  Future<List<PlaceSuggestion>> fetchSuggestions(String input) async {
    final query = input.trim();
    if (query.length < 3) return [];

    if (apiKey.isEmpty) {
      debugPrint('[PlacesAutocomplete] API key mancante, nessun suggerimento.');
      return [];
    }

    Uri uri;
    if (kIsWeb) {
      // Su WEB → passiamo dal proxy /api/... (gestito da Netlify)
      final encoded = Uri.encodeQueryComponent(query);
      uri = Uri.parse(
        '/api/maps/api/place/autocomplete/json?input=$encoded&key=$apiKey&language=it',
      );
    } else {
      // Su ANDROID / iOS → chiamiamo Google diretto
      uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': query,
          'key': apiKey,
          'language': 'it',
        },
      );
    }

    try {
      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        debugPrint(
          '[PlacesAutocomplete] HTTP ${resp.statusCode}: ${resp.body}',
        );
        return [];
      }

      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) {
        debugPrint('[PlacesAutocomplete] Risposta non valida: $data');
        return [];
      }

      final status = data['status'] as String? ?? 'UNKNOWN';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        debugPrint(
          '[PlacesAutocomplete] API error: $status - ${data['error_message']}',
        );
        return [];
      }

      final predictions = data['predictions'] as List<dynamic>? ?? [];
      return predictions
          .map((p) {
            final m = p as Map<String, dynamic>;
            final desc = m['description'] as String? ?? '';
            final pid = m['place_id'] as String? ?? '';
            return PlaceSuggestion(description: desc, placeId: pid);
          })
          .where((s) => s.description.isNotEmpty && s.placeId.isNotEmpty)
          .toList();
    } catch (e, st) {
      debugPrint('[PlacesAutocomplete] Eccezione: $e');
      debugPrint('$st');
      return [];
    }
  }
}
