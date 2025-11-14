import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner.dart';
import '../../services/supabase/partner_repo.dart';
import 'partner_registration_screen.dart';

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
    final client = Supabase.instance.client;
    final repo = PartnerRepo(client);

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

  void _refreshAfterRegistration() {
    _loadPartner();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final partner = _partner;

    // Se NON esiste ancora nessun partner per questo utente:
    // → shell completa con dashboard che invita a compilare la domanda
    if (partner == null) {
      final pages = <Widget>[
        _DashPartnerPage(
          partner: null,
          onPartnerChanged: _refreshAfterRegistration,
        ),
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
            BottomNavigationBarItem(
              icon: _PartnerStatusIcon(),
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

    // Se esiste un partner:
    // - pending  → schermata di attesa bloccata
    // - rejected → schermata rifiutata con tasto "Riprova"
    // - approved → shell completa
    if (partner.isPending || partner.isRejected) {
      return _PartnerRestrictedScreen(
        partner: partner,
        onReapplyCompleted: _refreshAfterRegistration,
      );
    }

    // Partner APPROVATO → shell partner completa
    final pages = <Widget>[
      _DashPartnerPage(
        partner: partner,
        onPartnerChanged: _refreshAfterRegistration,
      ),
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
          BottomNavigationBarItem(
            icon: _PartnerStatusIcon(),
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

/// Vista bloccata quando la richiesta è pending o rejected.
/// NIENTE bottom navigation qui.
class _PartnerRestrictedScreen extends StatelessWidget {
  final Partner partner;
  final VoidCallback onReapplyCompleted;

  const _PartnerRestrictedScreen({
    required this.partner,
    required this.onReapplyCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isPending = partner.isPending;
    final isRejected = partner.isRejected;

    final name = partner.name;
    final address = partner.address;
    final rejectReason = partner.rejectReason;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPending ? Icons.hourglass_empty : Icons.error_outline,
                size: 64,
                color: isPending ? cs.primary : Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                isPending ? 'Richiesta in valutazione' : 'Richiesta rifiutata',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (isPending)
                const Text(
                  'Il nostro team sta visionando la tua richiesta di partnership.\n'
                  'A breve riceverai una e-mail di conferma.',
                  textAlign: TextAlign.center,
                )
              else
                const Text(
                  'Spiacenti, la tua richiesta di diventare partner BagDrop è stata rifiutata.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              if (isRejected && (rejectReason ?? '').isNotEmpty)
                Text(
                  'Motivazione:\n$rejectReason',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              Text(
                'Attività: $name',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if ((address ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  address!,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (isRejected) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) => const PartnerRegistrationScreen(),
                        ),
                      )
                          .then((_) {
                        onReapplyCompleted();
                      });
                    },
                    child: const Text('Riprova a inviare richiesta'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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

/// Dashboard vera e propria (solo quando NON pending/rejected).
class _DashPartnerPage extends StatelessWidget {
  final Partner? partner;
  final VoidCallback onPartnerChanged;

  const _DashPartnerPage({
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(context, user),
      ),
    );
  }

  Widget _buildBody(BuildContext context, User? user) {
    // Nessuna attività associata → CTA per diventare partner
    if (partner == null) {
      return ListView(
        children: [
          const Text(
            'Benvenuto nella dashboard Partner 👋',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            'UID utente: ${user?.id ?? "-"}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          const Text(
            'Non risulta ancora nessuna attività associata al tuo account.\n\n'
            'Prossimo step: compila la domanda per diventare partner BagDrop '
            'con i dati della tua attività (nome, indirizzo, capacità, prezzi).',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context)
                    .push(
                  MaterialPageRoute(
                    builder: (_) => const PartnerRegistrationScreen(),
                  ),
                )
                    .then((_) {
                  onPartnerChanged();
                });
              },
              icon: const Icon(Icons.business_outlined),
              label: const Text('Compila domanda partner'),
            ),
          ),
        ],
      );
    }

    // Partner approvato → dashboard completa
    final p = partner!;
    return ListView(
      children: [
        Text(
          p.name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(p.address ?? 'Indirizzo non specificato'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                label: 'Capacità',
                value: '${p.capacity}',
              ),
            ),
            Expanded(
              child: _InfoTile(
                label: '€ / 2h',
                value: p.price2h?.toStringAsFixed(2) ?? '-',
              ),
            ),
            Expanded(
              child: _InfoTile(
                label: '€/giorno',
                value: p.pricePerDay?.toStringAsFixed(2) ?? '-',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InfoTile(
          label: 'Stato',
          value: p.isActive ? 'Attivo' : 'Sospeso',
        ),
        const SizedBox(height: 24),
        const Text(
          'Prossimi step:\n'
          '• Riepilogo prenotazioni del giorno\n'
          '• Guadagni giornalieri/mensili\n'
          '• Stato posti in tempo reale',
        ),
      ],
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
          'Qui vedrai le prenotazioni (in arrivo / in corso / completate).\n'
          'Fase 2: query Supabase + dettaglio.',
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
          'Qui integreremo lo scanner QR per check-in/out.\n'
          'Fase 3: integrazione camera e validazione.',
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
          'Gestione capacità e stato posti.\n'
          'Fase 4: update capacità + stato real-time.',
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
            const Text(
              'Dati utente',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Email: ${user?.email ?? "-"}'),
            const SizedBox(height: 24),
            const Text(
              'Azioni',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icona della tab Dashboard con badge se pending/rejected.
class _PartnerStatusIcon extends StatelessWidget {
  const _PartnerStatusIcon();

  @override
  Widget build(BuildContext context) {
    final repo = PartnerRepo(Supabase.instance.client);
    const baseIcon = Icon(Icons.dashboard_outlined);

    return FutureBuilder<Partner?>(
      future: repo.getMyPartner(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || snap.hasError) {
          return baseIcon;
        }
        final partner = snap.data;
        if (partner == null) return baseIcon;

        final isPending = partner.isPending;
        final isRejected = partner.isRejected;

        if (!isPending && !isRejected) return baseIcon;

        final color = isRejected
            ? Colors.red
            : Theme.of(context).colorScheme.tertiary;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            baseIcon,
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
