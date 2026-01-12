import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../autenticazione/auth_actions.dart';

class PartnerOnboardingStartScreen extends StatelessWidget {
  const PartnerOnboardingStartScreen({super.key});

  // ✅ link reale
  static const String kPartnerWizardUrl = 'https://bag-drop.it/diventa-partner/';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BagDrop Partner'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Completa la richiesta partner',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hai verificato la tua email, ma non hai ancora inviato la richiesta dell’attività.\n'
                    'Completa tutto dal sito (wizard partner).',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (user?.email != null) ...[
                    Text(
                      'Account: ${user!.email}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWizard(context),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Apri il sito e completa'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => AuthActions.confirmAndLogout(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Esci'),
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

  Future<void> _openWizard(BuildContext context) async {
    final uri = Uri.parse(kPartnerWizardUrl);

    // apre browser esterno
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il link.')),
      );
    }
  }
}
