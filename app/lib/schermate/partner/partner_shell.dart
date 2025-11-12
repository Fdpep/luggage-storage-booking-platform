// lib/schermate/partner/partner_shell.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shell principale per i Partner: bottom navigation + 5 tab.
/// In questa fase sono placeholder concreti (niente mock): mostriamo info minime reali (es. UID).
class PartnerShell extends StatefulWidget {
  const PartnerShell({super.key});

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _DashPartnerPage(),
      const _PrenotazioniPartnerPage(),
      const _ScannerQRPartnerPage(),
      const _SpaziPartnerPage(),
      const _ProfiloPartnerPage(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Prenotazioni'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.business_outlined), label: 'Spazi'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profilo'),
        ],
      ),
    );
  }
}

/// -------------------- PAGINE --------------------

/// Dashboard: mostra info essenziali (utente loggato).
class _DashPartnerPage extends StatelessWidget {
  const _DashPartnerPage();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Partner')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Benvenuto nella dashboard Partner 👋', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            if (user != null) ...[
              Text('UID utente: ${user.id}', style: const TextStyle(fontSize: 14)),
              Text('Email: ${user.email ?? "-"}', style: const TextStyle(fontSize: 14)),
            ] else
              const Text('Nessun utente loggato', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 24),
            const Text(
              'Prossimi step:\n• Riepilogo prenotazioni del giorno\n• Guadagni giornalieri/mensili\n• Stato degli spazi in tempo reale',
            ),
          ],
        ),
      ),
    );
  }
}

class _PrenotazioniPartnerPage extends StatelessWidget {
  const _PrenotazioniPartnerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prenotazioni')),
      body: const Center(
        child: Text(
          'Qui vedrai le prenotazioni (in arrivo / in corso / completate).\nFase 2: query Supabase + dettaglio.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ScannerQRPartnerPage extends StatelessWidget {
  const _ScannerQRPartnerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner QR')),
      body: const Center(
        child: Text(
          'Qui integreremo lo scanner QR per check-in/out.\nFase 3: integrazione camera e validazione.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SpaziPartnerPage extends StatelessWidget {
  const _SpaziPartnerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spazi')),
      body: const Center(
        child: Text(
          'Gestione capacità e stato posti.\nFase 4: update capacità + stato real-time.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ProfiloPartnerPage extends StatelessWidget {
  const _ProfiloPartnerPage();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profilo Partner')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dati utente', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Email: ${user?.email ?? "-"}'),
            const SizedBox(height: 24),
            const Text('Azioni', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
