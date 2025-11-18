import 'package:geolocator/geolocator.dart';

/// Servizio per ottenere la posizione corrente dell'utente.
///
/// Incapsula la logica di:
/// - richiesta permessi di localizzazione
/// - verifica se il GPS è abilitato
/// - ritorno della Position (latitudine/longitudine) oppure null se qualcosa va storto.
class LocationService {
  final GeolocatorPlatform _geo;

  LocationService({GeolocatorPlatform? geo})
      : _geo = geo ?? GeolocatorPlatform.instance;

  /// Restituisce la posizione corrente oppure null se:
  /// - i servizi di localizzazione sono disabilitati
  /// - l'utente nega i permessi
  Future<Position?> getCurrentPosition() async {
    // 1) Controllo se i servizi di localizzazione sono attivi
    final serviceEnabled = await _geo.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // In un'app reale potresti mostrare un messaggio all'utente
      return null;
    }

    // 2) Gestione permessi
    LocationPermission permission = await _geo.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await _geo.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permesso negato → niente posizione
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permesso negato in modo permanente → va in impostazioni
      return null;
    }

    // 3) Se siamo qui, abbiamo i permessi → ottieni posizione
   return _geo.getCurrentPosition(
     locationSettings: const LocationSettings(
       accuracy: LocationAccuracy.high,
     ),
   );
  }
}
