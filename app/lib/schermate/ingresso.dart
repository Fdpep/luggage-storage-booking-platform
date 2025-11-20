import 'package:flutter/material.dart';

/// Schermata d’ingresso (splash) con il logo fornito.
/// Mostrata solo per ~2.5s all’avvio dall’AuthGate.
class SchermataIngresso extends StatelessWidget {
  const SchermataIngresso({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.primary, // viola brand
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 16),

                // Piccolo branding in alto
                Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    'BagDrop',
                    style: TextStyle(
                      color: scheme.onPrimary.withOpacity(0.9),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Centro: card con logo + testo
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 22,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // LOGO: puoi cambiare il path se vuoi usare quello di flutter_native_splash
                            Image.asset(
                              'assets/immagini/bagdrop_splash.png',
                              // se l’immagine è “in un cerchio” dentro il file,
                              // qui non la ricopriamo con altri cerchi → risulta più pulita
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Deposita. Esplora. Rilassati.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Trova un partner vicino a te e lascia lo zaino in pochi tap.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface.withOpacity(0.7),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Parte bassa: loader + microtesto
                Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.secondary, // giallo brand
                      ),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stiamo preparando i tuoi BagDrop...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onPrimary.withOpacity(0.85),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
