import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Schermata mostrata SUBITO dopo l'invio della domanda partner.
/// Qui l'attività può SOLO leggere il messaggio e fare logout.
/// La prossima volta che apre l'app, l'AuthGate + PartnerShell
/// useranno lo stato reale dal database (pending/approved/rejected).
class PartnerWaitingScreen extends StatelessWidget {
  const PartnerWaitingScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final client = Supabase.instance.client;

    // 1) logout supabase
    await client.auth.signOut();

    if (!context.mounted) return;

    // 2) NON andare direttamente su /accesso,
    //    torniamo alla root dello stack (dove c'è RootGate/AuthGate)
    Navigator.of(context).popUntil((route) => route.isFirst);
    // AuthGate vedrà session == null e mostrerà signedOutBuilder (AccessoScreen)
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_empty,
                size: 64,
                color: cs.primary,
              ),
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
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Esci'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
