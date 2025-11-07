import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';

class StartOnboarding extends StatefulWidget {
  const StartOnboarding({super.key});

  @override
  State<StartOnboarding> createState() => _StartOnboardingState();
}

class _StartOnboardingState extends State<StartOnboarding> {
  final _controller = PageController();
  int _index = 0;

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);  // FLAG PER NASCONDERE PAGINA
  }

  void _next() {
    if (_index < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () async {
              await _markSeen();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Salta'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              // Logo in alto
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/brand/logo.png', height: 48),
                ],
              ),
              const SizedBox(height: 8),

              // Pagine
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [
                    _HeroPage(
                      imagePath: 'assets/images/onboarding/hero1.png',
                      title: 'Store your bags\nsecurely, wherever you are',
                      subtitle:
                          'Trova attività verificate vicino a te e libera la giornata.',
                    ),
                    _HeroPage(
                      imagePath: 'assets/images/onboarding/hero2.png',
                      title: 'Prenota in pochi tap',
                      subtitle:
                          'Scegli orario e quantità, paga in-app e ricevi la conferma.',
                    ),
                    _HeroPage(
                      imagePath: 'assets/images/onboarding/hero3.png',
                      title: 'Check-in con QR',
                      subtitle:
                          'Mostra il codice in negozio: rapido, tracciato e sicuro.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              _Dots(count: 3, index: _index),

              const SizedBox(height: 16),

              // CTA: nelle prime 2 pagine "Continua", nell’ultima due bottoni
              if (_index < 2)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: const Text('Continua'),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        await _markSeen();
                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      child: const Text('Accedi'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await _markSeen();
                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const SignupScreen()),
                        );
                      },
                      child: const Text('Crea un account'),
                    ),
                  ],
                ),

              const SizedBox(height: 12),
              Text(
                'BagDrop — deposito bagagli semplice e sicuro',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.outline),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPage extends StatelessWidget {
  final String imagePath;
  final String title;
  final String subtitle;
  const _HeroPage({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (_, c) {
        final isWide = c.maxWidth > 600;

        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        final imageBlock = Image.asset(
          imagePath,
          fit: BoxFit.contain,
          height: isWide ? 280 : 240,
        );

        return isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12, left: 4),
                      child: textBlock,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: imageBlock,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: imageBlock,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: textBlock,
                    ),
                  ),
                ],
              );
      },
    );
  }
}

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
          duration: const Duration(milliseconds: 200),
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
