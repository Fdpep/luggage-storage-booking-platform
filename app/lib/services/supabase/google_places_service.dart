import 'dart:convert';
import 'package:flutter/foundation.dart'; // per kIsWeb
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

//Questa funzione:
//
//legge la chiave da .env (GOOGLE_MAPS_API_KEY);
//
//se è Web → chiama /api/maps/api/place/autocomplete/json?...
//
//che su Netlify viene girato a https://maps.googleapis.com/...;
//
//se è Android/iOS → chiama direttamente https://maps.googleapis.com/... come facevi prima;
//
//ritorna una lista di stringhe con le descrizioni degli indirizzi


class GooglePlacesService {
  GooglePlacesService._();

  static final GooglePlacesService instance = GooglePlacesService._();

  String get _apiKey {
    final k = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (k == null || k.isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY mancante nel .env');
    }
    return k;
  }

  Future<List<String>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];

    final encodedInput = Uri.encodeQueryComponent(input.trim());

    // Su Web → passiamo dal proxy /api/… (Netlify)
    // Su Android/iOS → chiamiamo Google diretto
    final baseUrl = kIsWeb
        ? '/api/maps/api/place/autocomplete/json'
        : 'https://maps.googleapis.com/maps/api/place/autocomplete/json';

    final uri = Uri.parse(
      '$baseUrl?input=$encodedInput&key=$_apiKey&language=it',
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
        'Errore Google Places (${res.statusCode}): ${res.body}',
      );
    }

    final data = json.decode(res.body) as Map<String, dynamic>;
    final status = data['status'] as String? ?? 'UNKNOWN';

    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('Google Places status: $status');
    }

    final predictions = data['predictions'] as List<dynamic>? ?? [];
    return predictions
        .map((p) => p['description'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
