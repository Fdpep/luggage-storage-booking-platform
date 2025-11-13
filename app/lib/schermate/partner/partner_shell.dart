// lib/schermate/partner/partner_shell.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner.dart';
import '../../services/supabase/partner_repo.dart';


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
    final repo = PartnerRepo(Supabase.instance.client);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Partner')),
      body: FutureBuilder<Partner?>(
        future: repo.getMyPartner(),
        builder: (context, snap) {
          // Stato: caricamento
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Stato: errore
          if (snap.hasError) {
            return Center(
              child: Text(
                'Errore nel caricamento: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final partner = snap.data;

          // Stato: nessuna attività associata a questo account
          if (partner == null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Benvenuto nella dashboard Partner 👋', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 12),
                  Text('UID utente: ${user?.id ?? "-"}', style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 24),
                  const Text(
                    'Non risulta ancora nessuna attività associata al tuo account.\n'
                    'Prossimo step: schermata di onboarding Partner per creare/modificare i dati dell’attività.',
                  ),
                ],
              ),
            );
          }

          // Stato: partner presente → mostra dati reali
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text(partner.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(partner.address ?? 'Indirizzo non specificato'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _InfoTile(label: 'Capacità', value: '${partner.capacity}')),
                    Expanded(child: _InfoTile(label: '€ / 2h', value: partner.price2h?.toStringAsFixed(2) ?? '-')),
                    Expanded(child: _InfoTile(label: '€/giorno', value: partner.pricePerDay?.toStringAsFixed(2) ?? '-')),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoTile(label: 'Stato', value: partner.isActive ? 'Attivo' : 'Sospeso'),
                const SizedBox(height: 24),
                const Text(
                  'Prossimi step:\n• Riepilogo prenotazioni del giorno\n• Guadagni giornalieri/mensili\n• Stato posti in tempo reale',
                ),
              ],
            ),
          );
        },
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

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

