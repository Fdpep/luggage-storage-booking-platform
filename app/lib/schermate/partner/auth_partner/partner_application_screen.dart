// schermate/partner/partner_application_screen.dart
import 'package:flutter/material.dart';

class PartnerApplicationScreen extends StatelessWidget {
  const PartnerApplicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diventa partner BagDrop'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Registra la tua attività su BagDrop, imposta capacità e prezzi, '
              'e inizia a ricevere depositi bagagli.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Per inviare la richiesta devi avere un account.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/accesso'),
                    child: const Text('Ho già un account'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/registrazione'),
                    child: const Text('Registrati come utente'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Dopo il primo accesso potrai compilare la domanda partner '
              'direttamente dall’app.',
            ),
          ],
        ),
      ),
    );
  }
}
