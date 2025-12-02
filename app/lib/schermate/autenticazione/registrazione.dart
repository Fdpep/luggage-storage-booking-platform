import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // <-- per il link cliccabile
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/validators.dart';
import '../../utils/last_email_store.dart';
import 'verify_otp.dart';
import '../partner/auth_partner/partner_signup_screen.dart';

/// Registrazione con e-mail + password **confermata via OTP**
/// Ora raccogliamo anche:
/// - Nome
/// - Cognome
/// - Telefono
/// e li salviamo nei metadata dell'utente.
class RegistrazioneScreen extends StatefulWidget {
  const RegistrazioneScreen({super.key});

  @override
  State<RegistrazioneScreen> createState() => _RegistrazioneScreenState();
}

class _RegistrazioneScreenState extends State<RegistrazioneScreen> {
  final _formKey = GlobalKey<FormState>();

  // Nuovi campi anagrafica
  final _ctrlNome = TextEditingController();
  final _ctrlCognome = TextEditingController();
  final _ctrlTelefono = TextEditingController();

  // Già presenti
  final _ctrlEmail = TextEditingController();
  final _ctrlPassword = TextEditingController();
  final _ctrlConferma = TextEditingController();

  bool _accetto = false;
  bool _showPwd = false;
  bool _showPwd2 = false;
  bool _busy = false;

  // Per il link cliccabile Termini & Condizioni
  late TapGestureRecognizer _termsRecognizer;

  // Qui puoi incollare il testo completo dei T&C
  static const String _termsText = '''

TERMINI E CONDIZIONI UTENTE – SERVIZIO DI DEPOSITO BAGDROP

Ultimo aggiornamento: novembre 2025

I presenti Termini e Condizioni (di seguito “T&C Utente”) disciplinano l’utilizzo del servizio di deposito bagagli e oggetti personali offerto tramite la piattaforma digitale “BagDrop” (di seguito “Piattaforma” o “App”).
Prima di concludere una prenotazione e procedere al pagamento, l’utente (di seguito “Utente”) è tenuto a leggere e accettare integralmente questi T&C Utente.

1. Soggetti del servizio e natura del rapporto

1.1. BagDrop è una piattaforma tecnologica che mette in contatto Utenti e attività commerciali convenzionate (di seguito “Partner”) che offrono un servizio di custodia temporanea (di seguito “Deposito”).

1.2. Il contratto di deposito si conclude direttamente tra Utente e Partner, che agisce come depositario ai sensi degli artt. 1766 ss. c.c. BagDrop non è depositario dei beni dell’Utente.

1.3. BagDrop incassa i pagamenti per conto del Partner e gestisce la prenotazione tramite App come intermediario tecnico.

2. Definizioni

Prenotazione: acquisto tramite App del Deposito presso un Partner in data/orario scelti.
Collo: singolo bagaglio/oggetto consegnato (zaino, valigia, borsa, borsone ecc.).
Check-in: consegna del Collo al Partner con verifica QR-code/codice prenotazione.
Check-out: ritiro del Collo con verifica QR-code/codice prenotazione.
Orario di Deposito: fascia temporale prenotata dall’Utente.
No-show: mancata consegna o mancato ritiro nei tempi previsti.
3. Requisiti per utilizzare il servizio

3.1. L’Utente deve essere maggiorenne o avere autorizzazione del genitore/tutore.

3.2. L’Utente garantisce che i dati forniti in App sono veritieri e aggiornati.

3.3. BagDrop può rifiutare prenotazioni o sospendere account in caso di uso improprio, frode o violazione dei presenti T&C Utente.

4. Funzionamento del servizio

4.1. L’Utente seleziona in App un Partner disponibile, indica data/orario e numero di Colli, visualizza prezzo e condizioni specifiche, e procede al pagamento.

4.2. A pagamento concluso, l’Utente riceve una conferma di Prenotazione con QR-code/codice univoco.

4.3. L’Utente deve presentarsi al Partner entro la fascia oraria prenotata per check-in e check-out.

4.4. Il Partner verifica il QR-code/codice prenotazione e può richiedere un documento per ragioni di sicurezza (senza obbligo di consegna a BagDrop).

5. Oggetti ammessi, limiti e dichiarazioni dell’Utente

5.1. L’Utente dichiara che ogni Collo:

non contiene Oggetti Vietati (art. 6);
ha valore complessivo non superiore a €150 per Collo, salvo diversa dichiarazione accettata dal Partner;
rispetta i limiti dimensionali/peso indicati dal Partner in App (indicativamente: ≤ 12 kg, max 85×52×45 cm).
5.2. Obbligo di dichiarazione: se un Collo contiene beni fragili o con caratteristiche particolari, l’Utente deve informare il Partner al momento del check-in.

5.3. L’Utente accetta che il Partner possa rifiutare il Collo se:

eccede peso/dimensioni dichiarati in App;
presenta contenuto non dichiarato e potenzialmente vietato;
appare pericoloso, danneggiato o non idoneo alla custodia sicura.
6. Oggetti vietati

6.1. È vietato depositare:

denaro contante, gioielli, metalli preziosi, opere d’arte, titoli di credito;
documenti di identità, passaporti o documenti insostituibili;
merci deperibili o alimenti non sigillati;
sostanze infiammabili, esplosive, tossiche, corrosive, radioattive, inquinanti;
armi, munizioni, coltelli o oggetti offensivi;
sostanze illegali o vietate dalla legge;
animali vivi o morti, parti biologiche, rifiuti.
6.2. In caso di sospetto di Oggetti Vietati, il Partner può:

rifiutare il Deposito;
interrompere la custodia;
informare BagDrop;
contattare le autorità competenti se necessario.
6.3. L’Utente è l’unico responsabile di eventuali conseguenze legali derivanti da violazioni dell’art. 6 e manleva BagDrop e il Partner da ogni danno o sanzione.

7. Prezzi, pagamenti e ricevute

7.1. Il prezzo del Deposito è quello mostrato in App al momento della Prenotazione.

7.2. Il pagamento avviene tramite App con i metodi disponibili. La Prenotazione è valida solo dopo conferma del pagamento.

7.3. BagDrop invia ricevuta/quietanza digitale. Eventuali fatture potranno essere richieste secondo le modalità disponibili in App.

8. Cancellazioni, modifiche e rimborsi

8.1. Cancellazione da parte dell’Utente:

se effettuata prima dell’orario di inizio prenotato, rimborso 100%;
se effettuata dopo l’inizio, o in caso di No-show di check-in (art. 9), nessun rimborso.
8.2. Modifiche della Prenotazione (orario, durata, numero colli) sono possibili solo se il Partner ha disponibilità. Potrebbe essere richiesto un pagamento integrativo.

8.3. I rimborsi sono gestiti da BagDrop e possono avvenire sullo stesso metodo di pagamento entro i tempi tecnici necessari.

8.4. BagDrop può trattenere o compensare rimborsi già riconosciuti dall’Utente sugli importi dovuti al Partner.

9. No-show, ritardi e mancato ritiro

9.1. No-show check-in (mancata consegna): se l’Utente non si presenta entro la fascia prenotata, la Prenotazione è considerata utilizzata e non rimborsabile.

9.2. Ritardo nel check-out (ritiro oltre l’orario):

Se l’Utente non ritira il Collo entro l’orario di check-out indicato nella Prenotazione:

il QR code/codice di ritiro verrà automaticamente disattivato e non sarà più utilizzabile per il ritiro;
per riattivare il ritiro, l’Utente dovrà effettuare il pagamento dell’integrazione pari al costo del tempo aggiuntivo di deposito, come determinato dal Partner e/o come indicato in App al momento della richiesta;
il ritiro sarà possibile solo dopo il pagamento dell’integrazione e la successiva riattivazione del QR code/codice da parte del Partner;
in caso di mancato pagamento dell’integrazione, il Collo sarà trattato come giacenza secondo le procedure dell’art. 9.3 e seguenti.
9.3. Mancato ritiro oltre 48 ore dalla scadenza:

il Partner tenterà di contattare l’Utente tramite i recapiti forniti;
trascorsi 7 giorni, il Partner applicherà la procedura di giacenza con costo di €5/giorno (o diverso importo indicato in App).
9.4. Mancato ritiro oltre 30 giorni: i beni saranno considerati non reclamati. Il Partner potrà procedere a smaltimento secondo legge. L’Utente rinuncia a qualsiasi pretesa su tali beni.

10. Responsabilità su beni depositati

10.1. Il Partner è responsabile della custodia del Collo con diligenza professionale.

10.2. Limite massimo di responsabilità: in caso di furto, smarrimento o danno imputabile al Partner, il risarcimento non potrà superare €150 per Collo, salvo dolo o colpa grave del Partner.

10.3. Sono esclusi:

beni vietati o non dichiarati;
danni indiretti o consequenziali (es. perdita di profitto, viaggio perso, ecc.);
danni causati da caso fortuito o forza maggiore (art. 15);
normale usura, difetti preesistenti, imballaggi inadeguati.
10.4. BagDrop non risponde in proprio per danni ai beni, essendo estranea al rapporto di deposito tra Utente e Partner, salvo responsabilità diretta per malfunzionamenti tecnici della Piattaforma nei limiti di legge.

11. Procedura reclami e richieste risarcimento

11.1. In caso di danno o smarrimento, l’Utente deve:
a) segnalare immediatamente al Partner al check-out;
b) chiedere che venga compilato il modulo/verbale danni previsto dal Partner;
c) inviare segnalazione anche via App/assistenza BagDrop entro 24 ore dal ritiro previsto.

11.2. L’Utente deve fornire prove ragionevoli (foto, descrizione, valore stimato). In mancanza, la richiesta può essere rigettata.

11.3. BagDrop potrà facilitare la comunicazione tra Utente e Partner, ma la decisione sul risarcimento spetta al Partner nei limiti dell’art. 10.

12. Comportamento dell’Utente presso il Partner

12.1. L’Utente deve rispettare regole del locale, personale e procedure operative.

12.2. Il Partner può rifiutare il servizio all’Utente in caso di:

comportamento aggressivo o molesto;
violazione di legge;
tentativo di depositare Oggetti Vietati.
13. Disponibilità del servizio e limiti tecnici

13.1. Il servizio è offerto “come disponibile”. BagDrop non garantisce disponibilità continua o assenza di errori.

13.2. BagDrop può sospendere temporaneamente la Piattaforma per manutenzione o aggiornamenti.

13.3. Se per cause tecniche BagDrop annulla una Prenotazione già pagata, l’Utente ha diritto al rimborso integrale della quota versata.

14. Privacy

14.1. BagDrop tratta i dati personali dell’Utente come Titolare secondo Informativa Privacy disponibile in App.

14.2. Il Partner tratta autonomamente eventuali dati raccolti in loco (es. registro depositi, videosorveglianza). L’Utente prende atto che tali trattamenti sono sotto responsabilità del Partner.

15. Forza maggiore

15.1. Nessuna Parte è responsabile per inadempimenti dovuti a forza maggiore (es. blackout, incendi, alluvioni, ordini autorità, guasti rete).

15.2. In tali casi BagDrop potrà annullare la Prenotazione con rimborso totale o parziale a seconda del servizio effettivamente erogato.

16. Sospensione o chiusura account Utente

16.1. BagDrop può sospendere o chiudere l’account in caso di:

violazione dei presenti T&C Utente;
frode o tentativi di chargeback non giustificati;
deposito di oggetti vietati;
uso che danneggi Partner, BagDrop o altri utenti.
16.2. La sospensione non dà diritto ad alcun indennizzo.

17. Legge applicabile e foro

17.1. I presenti T&C Utente sono regolati dalla legge italiana.

17.2. In caso di controversia, l’Utente può ricorrere ai rimedi previsti dal Codice del Consumo. Se necessario, il foro competente è quello di Roma.

18. Modifiche ai T&C Utente

18.1. BagDrop può aggiornare i presenti T&C Utente. La versione aggiornata sarà pubblicata in App e si applicherà alle Prenotazioni successive alla data di efficacia indicata.

19. Accettazione

Confermando la Prenotazione, l’Utente dichiara di:

aver letto e accettato i presenti T&C Utente;
non depositare oggetti vietati;
accettare limiti di responsabilità e procedure di reclamo;
rispettare orari e regole del Partner.

''';

  @override
  void initState() {
    super.initState();

    LastEmailStore.load().then((v) {
      if (!mounted) return;
      if (v != null) _ctrlEmail.text = v;
    });

    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () {
        if (_busy) return;
        _showTermsBottomSheet();
      };
  }

  @override
  void dispose() {
    _ctrlNome.dispose();
    _ctrlCognome.dispose();
    _ctrlTelefono.dispose();
    _ctrlEmail.dispose();
    _ctrlPassword.dispose();
    _ctrlConferma.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  /// Mostra i Termini & Condizioni in un bottom sheet scrollabile.
  void _showTermsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Termini e Condizioni utente',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _termsText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_accetto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi accettare i termini per continuare'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    final firstName = _ctrlNome.text.trim();
    final lastName = _ctrlCognome.text.trim();
    final phone = _ctrlTelefono.text.trim();
    final email = _ctrlEmail.text.trim();
    final password = _ctrlPassword.text;

    try {
      // 1) Creazione account con password
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'source': 'bagdrop-app',
          'otp_verified': false, // flag custom
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
        },
      );

      // 2) Invio OTP per verifica e-mail (non ricreare l'utente)
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );

      await LastEmailStore.save(email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Codice inviato. Controlla la tua e-mail.'),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SchermataVerifyOtp(email: email, postSignup: true),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      var msg = e.message;
      if (msg.toLowerCase().contains('user already registered')) {
        msg = 'Esiste già un account con questa e-mail.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrati'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crea il tuo account BagDrop',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),

                  // NOME
                  TextFormField(
                    controller: _ctrlNome,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'Inserisci il nome';
                      }
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  // COGNOME
                  TextFormField(
                    controller: _ctrlCognome,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Cognome',
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'Inserisci il cognome';
                      }
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  // TELEFONO
                  TextFormField(
                    controller: _ctrlTelefono,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefono',
                      hintText: '+39 ...',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) {
                        return 'Inserisci un numero di telefono';
                      }
                      final digitsOnly =
                          t.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digitsOnly.length < 9 || digitsOnly.length > 15) {
                        return 'Inserisci un numero di telefono valido';
                      }
                      return null;
                    },
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 16),

                  // E-mail
                  TextFormField(
                    controller: _ctrlEmail,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      hintText: 'nome@esempio.com',
                    ),
                    validator: Validators.email,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  // Password
                  TextFormField(
                    controller: _ctrlPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    obscureText: !_showPwd,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                setState(() => _showPwd = !_showPwd),
                        icon: Icon(
                          _showPwd ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: Validators.password,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  // Conferma password
                  TextFormField(
                    controller: _ctrlConferma,
                    autofillHints: const [AutofillHints.newPassword],
                    obscureText: !_showPwd2,
                    decoration: InputDecoration(
                      labelText: 'Conferma password',
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                setState(() => _showPwd2 = !_showPwd2),
                        icon: Icon(
                          _showPwd2
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        Validators.confermaPassword(v, _ctrlPassword),
                    enabled: !_busy,
                    onFieldSubmitted: (_) => _register(),
                  ),

                  const SizedBox(height: 12),

                  // Consenso + link T&C
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _accetto,
                        onChanged: _busy
                            ? null
                            : (v) =>
                                setState(() => _accetto = v ?? false),
                      ),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium,
                            children: [
                              const TextSpan(
                                text: 'Ho letto e accetto i ',
                              ),
                              TextSpan(
                                text:
                                    'Termini e Condizioni utente e Privacy.',
                                style: TextStyle(
                                  color: cs.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: _termsRecognizer,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _register,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Registrati'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Hai già un account?'),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(
                                  context,
                                ).pushReplacementNamed('/accesso'),
                        child: const Text('Accedi'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'Sei un’attività e vuoi diventare partner BagDrop?',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PartnerSignUpScreen(),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.business_outlined),
                          label:
                              const Text('Registrati come partner'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
