import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verify_otp.dart';

/// Schermata di accesso:
/// - l’utente inserisce l’e-mail
/// - inviamo l’OTP via Supabase (magic link/OTP)
class SchermataSignIn extends StatefulWidget {
  const SchermataSignIn({super.key});

  @override
  State<SchermataSignIn> createState() => _SchermataSignInState();
}

class _SchermataSignInState extends State<SchermataSignIn> {
  // Controller per leggere il testo dell’e-mail dalla TextField
  final TextEditingController _ctrlEmail = TextEditingController();

  // Flag per mostrare stato di caricamento (disabilita pulsanti/UI)
  bool _caricamento = false;

  // Chiave del form per validare input (e.g. e-mail non vuota, contiene @)
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Funzione per inviare OTP via Supabase

  //Future<T>: è il tipo “promessa” di un risultato che arriverà in futuro (operazione asincrona: rete, I/O, timer…).
  //Future<void>: promessa senza valore di ritorno (fa un lavoro e basta).
  //async: abilita l’uso di await dentro la funzione, così il codice “aspetta” le chiamate asincrone senza bloccare l’app (UI reattiva).
  //Perché asincrona? Perché inviare l’OTP chiama servizi remoti (rete). Le operazioni di rete non devono bloccare il thread UI.

  Future<void> _inviaOtp() async {
    // Se il form non è valido, non procediamo
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _caricamento = true);
    final supabase = Supabase.instance.client;

    try {

      //_ctrlEmail.text: prende il testo attuale della TextEditingController collegata al TextFormField.
      //.trim(): rimuove spazi vuoti a inizio/fine (evita errori se l’utente mette uno spazio).
      //final: variabile immutabile dopo l’assegnazione (per chiarezza: non verrà cambiata).

      final email = _ctrlEmail.text.trim();

      // NB: emailRedirectTo serve soprattutto per magic link su mobile/web.
      // Se non usi deeplink, puoi ometterlo.
      
      //final redirect = kIsWeb ? null : 'io.supabase.flutter://login-callback';

      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,      // crea utente se non esiste
        // emailRedirectTo: redirect,   
      );

      if (mounted) {
        // Mostra feedback e vai alla schermata di verifica OTP
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Codice inviato. Controlla la tua email.')),
        );
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SchermataVerifyOtp(email: email),
        ));
      }
    } on AuthException catch (e) {
      // Errori specifici Supabase Auth (es. email invalida lato server)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore autenticazione: ${e.message}')),
      );
    } catch (e) {
      // Errori generici di rete/altro
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imprevisto: $e')),
      );
    } finally {
      if (mounted) setState(() => _caricamento = false);
    }
  }

  @override
  void dispose() {
    _ctrlEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accedi con e-mail'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey, // abilita validazione
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Testo introduttivo
                Text(
                  'Inserisci la tua e-mail. Ti invieremo un codice (OTP) per entrare.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),

                // Campo e-mail con validazione semplice
                TextFormField(
                  controller: _ctrlEmail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'nome@esempio.com',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Inserisci un’e-mail';
                    if (!v.contains('@')) return 'E-mail non valida';
                    return null;
                  },
                  enabled: !_caricamento,
                ),

                const SizedBox(height: 24),

                // Pulsante per inviare OTP
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _caricamento ? null : _inviaOtp,
                    child: _caricamento
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Invia codice'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
