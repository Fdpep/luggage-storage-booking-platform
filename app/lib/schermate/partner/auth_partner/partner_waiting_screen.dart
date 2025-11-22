import 'package:flutter/material.dart';
import 'package:BagDrop/models/partner.dart';
import '../../autenticazione/auth_actions.dart';
import 'partner_registration_screen.dart';

/// Schermata mostrata SUBITO dopo l'invio della domanda partner
/// oppure quando lo stato è pending/rejected.
///
/// - Se pending: solo messaggio di attesa + logout
/// - Se rejected: messaggio di rifiuto + eventuale motivazione +
///   bottone "Riprova a inviare richiesta".
class PartnerWaitingScreen extends StatelessWidget {
  final Partner? partner;
  final VoidCallback? onReapplyCompleted;

  const PartnerWaitingScreen({
    super.key,
    this.partner,
    this.onReapplyCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isRejected = partner?.isRejected ?? false;
    final rejectReason = partner?.rejectReason;
    final name = partner?.name;
    final address = partner?.address;

    return PopScope(
      canPop: false, // blocca il tasto "indietro"
      onPopInvoked: (didPop) {
        // non facciamo nulla: vogliamo che non possa tornare indietro
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BagDrop Partner'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          automaticallyImplyLeading:
              false, // niente freccia “indietro” nell’AppBar
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRejected ? Icons.error_outline : Icons.hourglass_empty,
                  size: 64,
                  color: isRejected ? Colors.red : cs.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  isRejected
                      ? 'Richiesta rifiutata'
                      : 'Richiesta in valutazione',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  isRejected
                      ? 'Spiacenti, la tua richiesta di diventare partner BagDrop è stata rifiutata.'
                      : 'Il nostro team sta visionando la tua richiesta di partnership.\n'
                          'A breve riceverai una e-mail di conferma.',
                  textAlign: TextAlign.center,
                ),

                // Motivazione se rifiutata
                if (isRejected && (rejectReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Motivazione:\n$rejectReason',
                    textAlign: TextAlign.center,
                  ),
                ],

                // Nome attività + indirizzo (se li abbiamo)
                if (name != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Attività: $name',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if ((address ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(address!, textAlign: TextAlign.center),
                  ],
                ],

                const SizedBox(height: 24),

                // Se rifiutato → bottone per rifare la domanda
                if (isRejected) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PartnerRegistrationScreen(),
                              ),
                            )
                            .then((_) {
                              // quando torna dalla registrazione,
                              // chiediamo al chiamante di ricaricare i dati
                              if (onReapplyCompleted != null) {
                                onReapplyCompleted!();
                              }
                            });
                      },
                      child: const Text('Riprova a inviare richiesta'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Logout (sempre disponibile)
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
