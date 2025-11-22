import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../models/partner.dart';
import '../../../autenticazione/auth_actions.dart';
import '../../dashboard/edit/partner_edit_screen.dart';
import '../../dashboard/edit/partner_photos_screen.dart';

class ProfiloPage extends StatelessWidget {
  final Partner? partner;
  final VoidCallback onPartnerChanged;

  const ProfiloPage({
    super.key,
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profilo Partner"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Dati account", style: tt.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(user?.email ?? "-"),
                subtitle: const Text("Account partner BagDrop"),
              ),
            ),
            const SizedBox(height: 24),

            Text("Scheda locale", style: tt.titleMedium),
            const SizedBox(height: 8),

            if (partner == null)
              const Text(
                "Nessuna attività registrata.",
                textAlign: TextAlign.center,
              )
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(partner!.name),
                  subtitle: Text(partner!.address ?? ""),
                  trailing: Text(partner!.isActive ? "Attivo" : "Sospeso"),
                ),
              ),

            const SizedBox(height: 24),
            Text("Azioni", style: tt.titleMedium),
            const SizedBox(height: 12),

            if (partner != null) ...[
              FilledButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text("Gestisci foto locale"),
                onPressed: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(
                        builder: (_) => PartnerPhotosScreen(partner: partner!),
                      ));
                },
              ),
              const SizedBox(height: 12),
            ],

            FilledButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text("Modifica scheda locale"),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const PartnerEditScreen()),
                );
                if (ok == true) onPartnerChanged();
              },
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              onPressed: () => AuthActions.confirmAndLogout(context),
            ),
          ],
        ),
      ),
    );
  }
}
