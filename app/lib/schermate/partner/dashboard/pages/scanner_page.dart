import 'package:flutter/material.dart';
import '../../user_view/partner_drawer.dart';

class ScannerPage extends StatelessWidget {
  const ScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        title: const Text("Scanner QR"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: const Center(
        child: Text(
          "Scanner QR in arrivo.\n(Fase 3)",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
