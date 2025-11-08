//A cosa serve user_repo.dart?

//È un Repository: un livello intermedio tra UI e DB/HTTP.

//Vantaggi:

//centralizza le query Supabase (UI più pulita)

//tipi e mapping consistenti (meno errori)

//facile fare test/mocking in futuro

//Esempio: getMe() e upsertMe() nascondono i dettagli di Supabase alla UI.


import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_profile.dart';

/// Repository per l’accesso tipizzato a user_profiles.
/// Contiene funzioni per leggere/aggiornare i dati del profilo dell’utente loggato.
class UserRepo {
  // Riferimento al client Supabase inizializzato dall’app
  final SupabaseClient _client = Supabase.instance.client;

  /// Restituisce il profilo dell’utente corrente.
  /// Lancia se non c’è una sessione attiva.
  Future<UserProfile?> getMe() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Nessun utente loggato (sessione assente).');
    }

    final data = await _client
        .from('user_profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();   // ritorna Map<String, dynamic>? o null

    if (data == null) return null;
     // Cast “sicuro” a Map<String, dynamic> prima di passarlo al model

    //fromMap costruisce un oggetto tipizzato (UserProfile) a partire dalla mappa.
    //Così nel resto dell’app si lavora con un model forte invece di mappe “libere”. 

    return UserProfile.fromMap(data);
  }

  /// Upsert del profilo dell’utente corrente.
  /// - Se la riga esiste, aggiorna i campi passati (full_name, avatar_url).
  /// - Se non esiste (es. trigger non ancora scattato), la crea.
  Future<void> upsertMe({
    String? nomeCompleto,     // full_name
    String? urlAvatar,        // avatar_url
    String? statoKyc,         // kyc_status ('none'/'basic'/'verified')
    String? ruolo,            // role ('user'/'partner'/'admin')
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Nessun utente loggato (sessione assente).');
    }

    // Costruisco il payload dinamicamente con solo i campi forniti
    final payload = <String, dynamic>{
      'id': uid,
      if (nomeCompleto != null) 'full_name': nomeCompleto,
      if (urlAvatar != null) 'avatar_url': urlAvatar,
      if (statoKyc != null) 'kyc_status': statoKyc,
      if (ruolo != null) 'role': ruolo,
    };

    // onConflict: 'id' per garantire l’upsert sulla PK
    await _client.from('user_profiles').upsert(payload, onConflict: 'id');
  }
}
