import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../autenticazione/auth_actions.dart';

class PartnerPaymentRequiredScreen extends StatefulWidget {
  const PartnerPaymentRequiredScreen({super.key});

  @override
  State<PartnerPaymentRequiredScreen> createState() => _PartnerPaymentRequiredScreenState();
}

class _PartnerPaymentRequiredScreenState extends State<PartnerPaymentRequiredScreen> {
  bool _loading = false;
  String? _msg;

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
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      // ✅ QUI chiameremo la RPC “security definer” che:
      // - verifica auth.uid()
      // - verifica status docs_approved
      // - aggiorna stato a paid + setta role='partner'
      //
      // Per ora la mettiamo come “placeholder”:
      //
      // await Supabase.instance.client.rpc('mark_partner_paid_and_activate');
      //
      // Se la RPC non esiste ancora, non rompe l’app: mostra errore leggibile.

      final client = Supabase.instance.client;

      final res = await client.rpc('mark_partner_paid_and_activate');
      // se la tua rpc ritorna qualcosa, puoi loggare res

      setState(() {
        _msg = 'OK: pagamento simulato completato. Ora puoi rientrare come partner.';
      });

      // forziamo refresh sessione + ricarico gate
      await client.auth.refreshSession();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() {
        _msg = 'ERRORE: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
