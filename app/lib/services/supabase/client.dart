//Chiaro. client.dart è un façade sottile che fa 3 cose:
// 1: Inizializza una sola volta
//    Chiama Supabase.initialize(...) all’avvio (in main()), usando le chiavi lette da config.dart.
//    Va atteso prima di runApp, così il client è pronto.
// 2: Espone un client unico e riusabile
//    SupabaseService.client restituisce il SupabaseClient globale di Supabase.
//    Si usa ovunque senza passare chiavi o contesti.
// 3: Punto centrale per la configurazione
//    In un solo file si potrà aggiungere opzioni
//    (es. storage locale, headers, auth flow), fare logging, o sostituire il client nei test—senza toccare il resto dell’app.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class SupabaseService {
  static Future<void> init() async {
    if (!SupabaseConfig.ok) {
      throw Exception(
        'SUPABASE_URL o SUPABASE_ANON_KEY mancanti nel file .env',
      );
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  /// Accesso comodo al client globale
  static SupabaseClient get client => Supabase.instance.client;
}
