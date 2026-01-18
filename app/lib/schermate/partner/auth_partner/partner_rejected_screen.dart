import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../autenticazione/auth_actions.dart';

class PartnerRejectedScreen extends StatefulWidget {
  final String? reason;
  const PartnerRejectedScreen({super.key, this.reason});

  @override
  State<PartnerRejectedScreen> createState() => _PartnerRejectedScreenState();
}

class _PartnerRejectedScreenState extends State<PartnerRejectedScreen> {
  bool _loading = false;

  static const String kPartnerWizardUrl = 'https://bag-drop.it/diventa-partner/';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Richiesta rifiutata',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La tua richiesta partner è stata rifiutata.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.reason != null && widget.reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Motivazione:\n${widget.reason!}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _retryFromWebsite,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Riprova dal sito (nuova richiesta)'),
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

  Future<void> _retryFromWebsite() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma'),
        content: const Text(
          'Per inviare una nuova richiesta dobbiamo eliminare questo account.\n'
          'Vuoi procedere? (Dopo potrai registrarti di nuovo dal sito)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Elimina e continua')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;

      // usa la tua funzione già esistente
      await client.rpc('delete_my_account');

      // dopo delete l’utente non esiste più: apri il sito per rifare signup
      final uri = Uri.parse(kPartnerWizardUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
      setState(() => _loading = false);
    }
  }
}
