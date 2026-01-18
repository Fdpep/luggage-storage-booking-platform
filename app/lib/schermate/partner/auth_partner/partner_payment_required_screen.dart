// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../autenticazione/auth_actions.dart';
import 'package:url_launcher/url_launcher.dart';

class PartnerPaymentRequiredScreen extends StatefulWidget {
  const PartnerPaymentRequiredScreen({super.key});

  @override
  State<PartnerPaymentRequiredScreen> createState() => _PartnerPaymentRequiredScreenState();
}

class _PartnerPaymentRequiredScreenState extends State<PartnerPaymentRequiredScreen> {
  bool _loading = false;
  String? _msg;
  static const String kPaymentUrl = 'https://bag-drop.it/pagamento-partner/';

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
                  Icon(Icons.credit_card, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Documenti approvati ✅',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Per attivare il tuo profilo partner serve completare il pagamento.\n'
                    'Per ora puoi simulare il pagamento (poi lo collegheremo a Stripe).',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  if (_msg != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _msg!.startsWith('OK') ? Colors.green.shade50 : Colors.red.shade50,
                        border: Border.all(
                          color: _msg!.startsWith('OK') ? Colors.green.shade200 : Colors.red.shade200,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_msg!),
                    ),
                    const SizedBox(height: 12),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () async {
                        final uri = Uri.parse(kPaymentUrl);
                        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Impossibile aprire il link di pagamento.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Vai alla pagina pagamento'),
                    ),
                  ),
                  const SizedBox(height: 12),


                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _simulatePayment,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Simula pagamento'),
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

Future<void> _simulatePayment() async {
  final uri = Uri.parse(kPaymentUrl);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossibile aprire il link di pagamento.')),
    );
  }
}

}
