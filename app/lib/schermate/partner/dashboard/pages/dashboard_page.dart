import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/schermate/partner/dashboard/pages/bagdrop_pricing_screen.dart';
import '../../../../models/partner.dart';
import '../../auth_partner/partner_registration_screen.dart';

class DashboardPage extends StatelessWidget {
  final Partner? partner;
  final VoidCallback onPartnerChanged;

  const DashboardPage({
    super.key,
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("BagDrop Partner"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(context, user),
      ),
    );
  }

  Widget _buildBody(BuildContext context, User? user) {
    if (partner == null) {
      return ListView(
        children: [
          const Text(
            'Benvenuto nella dashboard Partner 👋',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text('UID: ${user?.id ?? "-"}'),
          const SizedBox(height: 24),
          const Text(
            'Non risulta una attività associata al tuo account.\n\n'
            'Compila la domanda di partnership per iniziare.',
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const PartnerRegistrationScreen(),
                    ),
                  )
                  .then((_) => onPartnerChanged());
            },
            icon: const Icon(Icons.business),
            label: const Text('Compila domanda partner'),
          ),
        ],
      );
    }

    final p = partner!;
    return ListView(
      children: [
        Text(
          p.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(p.address ?? 'Indirizzo non specificato'),
        const SizedBox(height: 16),

        // Info
        Row(
          children: [
            Expanded(child: _infoTile(context, "Capacità", "${p.capacity}")),
            Expanded(
              child: _infoTile(
                context,
                "Tariffe",
                "Listino BagDrop",
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BagDropPricingScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _infoTile(context, "Stato", p.isActive ? "Attivo" : "Sospeso"),
        const SizedBox(height: 24),

        const Text(
          "Prossimi step:\n"
          "• Prenotazioni giornaliere\n"
          "• Guadagni\n"
          "• Stato posti in tempo reale",
        ),
      ],
    );
  }

  Widget _infoTile(
    BuildContext context,
    String title,
    String value, {
    VoidCallback? onTap,
  }) {
    final tt = Theme.of(context).textTheme;

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: tt.bodyMedium),
        ],
      ),
    );

    return Card(
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}


