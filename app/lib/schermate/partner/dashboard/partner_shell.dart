import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/partner.dart';
import '../../../services/supabase/partner_repo.dart';

// Nuove pagine modularizzate
import 'pages/dashboard_page.dart';
import 'pages/prenotazioni_page.dart';
import 'pages/scanner_page.dart';
import 'pages/spazi_page.dart';
import 'pages/profilo_page.dart';

// Schermate esterne
import '../auth_partner/partner_registration_screen.dart';
// ignore: unused_import
import '../auth_partner/partner_waiting_screen.dart';
// ignore: unused_import
import '../../autenticazione/auth_actions.dart';

class PartnerShell extends StatefulWidget {
  const PartnerShell({super.key});

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  Partner? _partner;
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  Future<void> _loadPartner() async {
    setState(() => _loading = true);
    final repo = PartnerRepo(Supabase.instance.client);

    try {
      final p = await repo.getMyPartner();
      if (!mounted) return;

      setState(() {
        _partner = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _reload() => _loadPartner();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final p = _partner;

    // Nessun partner → deve ancora registrare l’attività
    if (p == null) {
      return _buildShell(
        pages: [
          DashboardPage(partner: null, onPartnerChanged: _reload),
          const PrenotazioniPage(),
          const ScannerPage(),
          const SpaziPage(),
          ProfiloPage(partner: null, onPartnerChanged: _reload),
        ],
      );
    }

    // Pending / Rejected
    if (p.isPending || p.isRejected) {
      return PartnerRestrictedScreen(partner: p, onReapplyCompleted: _reload);
    }

    // Partner approvato → tutte le pagine abilitate
    return _buildShell(
      pages: [
        DashboardPage(partner: p, onPartnerChanged: _reload),
        const PrenotazioniPage(),
        const ScannerPage(),
        const SpaziPage(),
        ProfiloPage(partner: p, onPartnerChanged: _reload),
      ],
    );
  }

  Widget _buildShell({required List<Widget> pages}) {
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Prenotazioni',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business_outlined),
            label: 'Spazi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profilo',
          ),
        ],
      ),
    );
  }
}

/// Schermata che blocca l’utente se pending / rejected
class PartnerRestrictedScreen extends StatelessWidget {
  final Partner partner;
  final VoidCallback onReapplyCompleted;

  const PartnerRestrictedScreen({
    super.key,
    required this.partner,
    required this.onReapplyCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pending = partner.isPending;
    final rejected = partner.isRejected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BagDrop Partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pending ? Icons.hourglass_empty : Icons.error_outline,
                size: 64,
                color: pending ? cs.primary : Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                pending ? 'Richiesta in valutazione' : 'Richiesta rifiutata',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (pending)
                const Text(
                  'Il nostro team sta valutando la tua richiesta.',
                  textAlign: TextAlign.center,
                )
              else
                const Text(
                  'La tua richiesta è stata rifiutata.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),

              if (rejected)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) =>
                                  const PartnerRegistrationScreen()))
                          .then((_) => onReapplyCompleted());
                    },
                    child: const Text('Riprova'),
                  ),
                ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Esci'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
