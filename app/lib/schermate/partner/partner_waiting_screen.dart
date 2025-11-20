import 'package:flutter/material.dart';
import '../autenticazione/auth_actions.dart';

/// Schermata mostrata SUBITO dopo l'invio della domanda partner.
/// Qui l'attività può SOLO leggere il messaggio e fare logout.
/// La prossima volta che apre l'app, l'AuthGate + PartnerShell
/// useranno lo stato reale dal database (pending/approved/rejected).
class PartnerWaitingScreen extends StatelessWidget {
  const PartnerWaitingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BagDrop Partner'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          //  niente freccia “indietro” nell’AppBar
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_empty, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'Richiesta in valutazione',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Il nostro team sta visionando la tua richiesta di partnership.\n'
                  'A breve riceverai una e-mail di conferma.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AuthActions.confirmAndLogout(context);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Esci'),
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
