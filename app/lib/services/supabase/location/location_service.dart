//Questo servizio si occupa SOLO di:
//
//chiedere i permessi di geolocalizzazione,
//
//verificare che il GPS sia attivo,
//
//restituire LatLng (di latlong2, che hai già in pubspec).


import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Servizio di comodo per gestire:
/// - permessi di geolocalizzazione
/// - stato del GPS
/// - recupero della posizione attuale dell'utente.
///
/// Espone metodi semplici che la UI può chiamare senza conoscere
/// i dettagli del plugin Geolocator.
class LocationService {
  const LocationService();

  /// Controlla se abbiamo il permesso di accedere alla posizione
  /// e, se necessario, chiede il permesso all'utente.
  ///
  /// Restituisce:
  /// - true  → se alla fine abbiamo il permesso
  /// - false → se l'utente ha negato il permesso (o è "per sempre negato")
  Future<bool> ensurePermission() async {
    // 1) Controlliamo lo stato corrente del permesso.
    LocationPermission permission = await Geolocator.checkPermission();

    // 2) Se è "denied", chiediamo esplicitamente il permesso.
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 3) Se è "deniedForever" o ancora "denied" dopo la richiesta,
    //    non possiamo usare la posizione.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // 4) Se arriviamo qui, il permesso è "whileInUse" o "always".
    return true;
  }

  /// Restituisce la posizione ATTUALE dell'utente come LatLng,
  /// oppure null se:
  /// - il permesso non è stato concesso
  /// - i servizi di localizzazione sono disattivati
  /// - si verifica un errore durante il recupero della posizione
  ///
  /// La UI può usare il valore null per mostrare un fallback
  /// (es. mappa centrata su una città di default).
  Future<LatLng?> getCurrentPosition() async {
    try {
      // 1) Verifichiamo se i servizi di localizzazione (GPS) sono attivi.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // GPS disattivato: non possiamo ottenere la posizione.
        return null;
      }

      // 2) Ci assicuriamo di avere il permesso.
      final hasPermission = await ensurePermission();
      if (!hasPermission) {
        // Permesso negato: la UI dovrà gestire il fallback.
        return null;
      }

      // 3) A questo punto possiamo chiedere la posizione attuale.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 4) Convertiamo la Position del plugin in LatLng (latlong2),
      //    che useremo nella mappa.
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      // In caso di eccezioni (timeout, errori di plugin, ecc.),
      // restituiamo null e lasciamo alla UI la gestione del fallback.
      return null;
    }
  }
}
