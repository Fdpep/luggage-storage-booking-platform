import 'package:flutter/material.dart';

/// Schermata d’ingresso (splash) con il logo fornito.
/// Mostrata solo per ~2.5s all’avvio dall’AuthGate.
class SchermataIngresso extends StatelessWidget {
  const SchermataIngresso({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F2E5), // beige chiaro dello sfondo
      body: Center(
        // Carica l’immagine dagli assets
        child: Image.asset(
          'assets/immagini/bagdrop_splash.png',
          fit: BoxFit.contain,
          width: 260,
        ),
      ),
    );
  }
}
