import 'package:flutter/material.dart';
import '../../user_view/partner_drawer.dart';

class SpaziPage extends StatelessWidget {
  const SpaziPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        title: const Text("Spazi"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: const Center(
        child: Text(
          "Gestione capacità in arrivo.\n(Fase 4)",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
