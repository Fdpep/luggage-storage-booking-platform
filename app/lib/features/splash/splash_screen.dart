// Qui si ha lo splash iniziale del login con animazione e logo iniziale.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../onboarding/start_onboarding.dart';
import '../auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _fadeLogo;
  late final Animation<double> _fadeText;
  late final Animation<double> _scaleLogo;

  // In DEV, l'onboarding si vede sempre quando non loggato.
  static const bool kShowOnboardingEveryLaunch = true;

  @override
  void initState() {
    super.initState();

    // Status bar chiara su sfondo viola
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeLogo = CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);
    _scaleLogo = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutBack));
    _fadeText = CurvedAnimation(
      parent: _ac,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    _ac.forward();

    // Dopo una piccola pausa, vai al flusso della app
    Timer(const Duration(milliseconds: 1600), _goNext);
  }

  void _goNext() {
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Utente già loggato → mappa via routes standard
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/map');
      return;
    }

    // Utente NON loggato → onboarding (in dev sempre), oppure login
    if (!mounted) return;
    if (kShowOnboardingEveryLaunch) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StartOnboarding()),
      );
    } else {
      // se hai il flag 'onboarding_seen', qui potresti controllarlo e decidere
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StartOnboarding()),
      );
    }
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandViolet = Color(0xFF4B3FE4);

    return Scaffold(
      backgroundColor: brandViolet,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedBuilder(
                animation: _ac,
                builder: (context, _) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo con leggero "pop" (scale) + fade
                      Opacity(
                        opacity: _fadeLogo.value,
                        child: Transform.scale(
                          scale: _scaleLogo.value,
                          child: Image.asset(
                            'assets/images/brand/logo.png',
                            height: 96,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Testo "BagDrop" che appare dolcemente
                      Opacity(
                        opacity: _fadeText.value,
                        child: Text(
                          'BagDrop',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
