import 'package:flutter/material.dart';
import '../../autenticazione/auth_actions.dart';

class PartnerRejectedScreen extends StatelessWidget {
  final String? reason;
  const PartnerRejectedScreen({super.key, this.reason});

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
                  if (reason != null && reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Motivazione:\n${reason!}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),

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
}
