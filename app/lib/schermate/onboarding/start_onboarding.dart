import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../autenticazione/accesso.dart';
import '../autenticazione/registrazione.dart';
//import 'package:supabase_flutter/supabase_flutter.dart';
//import '../home_shell.dart';

/// Onboarding moderno:
/// - 3 pagine con layout "hero"
/// - parallax dolce sull'immagine
/// - gradient di sfondo + card con angoli grandi
/// - dots animati e CTA "Continua / Inizia ora"



class StartOnboarding extends StatefulWidget {
  const StartOnboarding({super.key});

  @override
  State<StartOnboarding> createState() => _StartOnboardingState();
}

class _StartOnboardingState extends State<StartOnboarding> {
  final _controller = PageController(viewportFraction: 1.0);
  int _index = 0;

  Future<void> _markSeen() async {

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', false );
  }

  void _next() {
    if (_index < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Palette brand (puoi sostituire con i tuoi esatti codici)
  static const _brandPurple = Color(0xFF4B3FE4);
  static const _brandYellow = Color(0xFFF2C335);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // AppBar minimale con "Salta"
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () async {
              await _markSeen();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AccessoScreen()),
              );
            },
            child: const Text('Salta'),
          ),
        ],
      ),

      // --- Sfondo con gradient morbido + "blob" decorativi
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.surface, // si adatta al tema
              scheme.surfaceVariant.withOpacity(0.85),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // Blob decorativi molto tenui (non invadono)
            Positioned(
              top: -120,
              left: -60,
              child: _Blob(color: _brandPurple.withOpacity(0.10), size: 260),
            ),
            Positioned(
              bottom: -100,
              right: -40,
              child: _Blob(color: _brandYellow.withOpacity(0.10), size: 220),
            ),

            // --- Contenuto
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Logo
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Image.asset(
                      'assets/images/brand/logo.png',
                      height: 52,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- PageView con parallax
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        // Page offset per effetto parallax
                        final page =
                            (_controller.hasClients && _controller.page != null)
                            ? _controller.page!
                            : _controller.initialPage.toDouble();

                        return PageView(
                          controller: _controller,
                          onPageChanged: (i) => setState(() => _index = i),
                          children: [
                            _HeroCard(
                              title:
                                  'Deposita i tuoi bagagli\nin sicurezza, ovunque tu sia',
                              subtitle:
                                  'Trova attività verificate vicino a te e libera la giornata.',
                              imagePath: 'assets/images/onboarding/hero1.png',
                              // se l’immagine non c’è, lascia comunque lo spazio (vedi widget)
                              parallax: _parallaxFor(page, 0),
                            ),
                            _HeroCard(
                              title: 'Prenota in pochi tap',
                              subtitle:
                                  'Scegli orario e quantità, paga in-app e ricevi la conferma.',
                              imagePath: 'assets/images/onboarding/hero2.png',
                              parallax: _parallaxFor(page, 1),
                            ),
                            _HeroCard(
                              title: 'Check-in con QR',
                              subtitle:
                                  'Mostra il codice al punto vendita: rapido, tracciato e sicuro.',
                              imagePath: 'assets/images/onboarding/hero3.png',
                              parallax: _parallaxFor(page, 2),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  _Dots(count: 3, index: _index),

                  const SizedBox(height: 16),

                  // CTA: prime due pagine "Continua", ultima "Accedi / Crea account" + "Inizia ora"
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _index < 2
                        ? SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _next,
                              child: const Text('Continua'),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // "Inizia ora" → flusso consigliato: Accedi
                              FilledButton(
                                onPressed: () async {
                                  await _markSeen();
                                  if (!mounted) return;
                                  // Torna alla root: RootGate → AuthGate
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const AccessoScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Inizia ora'),
                              ),
                              const SizedBox(height: 8),
                              // Link alternativo: vai direttamente a Signup
                              OutlinedButton(
                                onPressed: () async {
                                  await _markSeen();
                                  if (!mounted) return;
                                  // Evita dipendenze incrociate → torna a '/'
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const RegistrazioneScreen(),
                                    ),
                                  );
                                },
                                child: const Text('Crea un account'),
                              ),
                              
                              // SBAGLIATO, DA RIVEDERE L'ACCEDI COME OSPITE, è l'authgate che deve decidere dove reindirizzare, altrimenti salta tutto.
                              /*OutlinedButton.icon(
                                onPressed: () async {
                                  await _markSeen(); // segna l’onboarding come visto
                                  // 1) forza logout: nessuna sessione, nessuna email
                                  try {
                                    await Supabase.instance.client.auth.signOut();
                                  } catch (e) {
                                    debugPrint('[Guest] signOut error: $e');
                                  }
                                  // 2) doppia verifica (debug)
                                   final u = Supabase.instance.client.auth.currentUser;
                                   debugPrint('[Guest] after signOut → currentUser=${u?.id}');
                                   if (!mounted) return;
                                   // 3) resetta lo stack e apre HomeShell come GUEST
                                   Navigator.of(context).pushAndRemoveUntil(
                                     MaterialPageRoute(builder: (_) => const HomeShell()),
                                     (_) => false,
                                   );
                                 },
                                icon: const Icon(Icons.explore_outlined),
                                label: const Text('Esplora come ospite'),
                              ),  */
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Calcola offset parallax in base alla pagina corrente
  double _parallaxFor(double page, int index) {
    final diff = (page - index);
    // clamp morbido per evitare grandi spostamenti su scroll rapido
    return (diff * 24).clamp(-28, 28); // px
  }
}

/// Card "hero" con spazio dedicato all'immagine (anche se mancante),
/// titoli grandi e look moderno coerente con Material 3.
class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imagePath;
  final double parallax;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    this.imagePath,
    required this.parallax,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: scheme.outlineVariant.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (_, c) {
            final isWide = c.maxWidth > 680;

            final textBlock = Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 32 : 20,
                20,
                isWide ? 12 : 20,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );

            final imageWidget = _ImageStage(
              imagePath: imagePath,
              parallax: parallax,
            );

            return isWide
                ? Row(
                    children: [
                      Expanded(flex: 6, child: textBlock),
                      Expanded(flex: 4, child: imageWidget),
                    ],
                  )
                : Column(
                    children: [
                      // Immagine in alto su schermi piccoli
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: imageWidget,
                      ),
                      textBlock,
                    ],
                  );
          },
        ),
      ),
    );
  }
}

/// Stage immagine:
/// - se imagePath è nullo o non trovato, mostra un placeholder elegante (spazio riservato)
/// - Applicato un leggero parallax (translate).
class _ImageStage extends StatelessWidget {
  final String? imagePath;
  final double parallax;

  const _ImageStage({required this.imagePath, required this.parallax});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget child;
    if (imagePath == null || imagePath!.isEmpty) {
      // Placeholder elegante: bordo tratteggiato leggero + icona
      child = Container(
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withOpacity(0.6),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Icon(Icons.image_outlined, size: 56, color: scheme.outline),
      );
    } else {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 1.3, // spazio gradevole per illustrazioni
          child: Image.asset(imagePath!, fit: BoxFit.contain),
        ),
      );
    }

    return Transform.translate(
      offset: Offset(parallax, 0), // parallax orizzontale dolce
      child: child,
    );
  }
}

/// Dots indicator animato (senza dipendenze)
class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

/// Blob decorativo con gradiente radiale molto attenuato
class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
