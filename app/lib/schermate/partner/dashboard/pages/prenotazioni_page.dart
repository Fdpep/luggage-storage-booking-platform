import 'package:flutter/material.dart';

class PrenotazioniPage extends StatelessWidget {
  const PrenotazioniPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prenotazioni"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: const Center(
        child: Text(
          "Qui verranno mostrate le prenotazioni.\n(Fase 2)",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
