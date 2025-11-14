import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_partner_requests_screen.dart';

/// Shell principale per l’area Admin.
/// Semplice bottom navigation:
/// - Tab 0: Dashboard
/// - Tab 1: Richieste partner
/// - Tab 2: Partner (lista)
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _AdminDashboardPage(),
      const AdminPartnerRequestsScreen(),
      const _AdminPartnersListPage(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Richieste',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business_outlined),
            label: 'Partner',
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardPage extends StatelessWidget {
  const _AdminDashboardPage();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Admin'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(
            tooltip: 'Disconnetti',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Benvenuto nell’area admin BagDrop 👑',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Email admin: ${user?.email ?? '-'}'),
            const SizedBox(height: 24),
            const Text(
              'Da qui puoi:\n'
              '• Approvare o rifiutare richieste partner\n'
              '• Vedere lo stato dei partner\n'
              '• In futuro: gestire utenti, report, ecc.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista semplice di tutti i partner, per vedere stato e attivazione.
class _AdminPartnersListPage extends StatefulWidget {
  const _AdminPartnersListPage();

  @override
  State<_AdminPartnersListPage> createState() => _AdminPartnersListPageState();
}

class _AdminPartnersListPageState extends State<_AdminPartnersListPage> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _partners = [];

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _supabase
          .from('partners')
          .select('id,name,address,status,is_active,capacity,created_at')
          .order('created_at');

      setState(() {
        _partners = (data as List)
            .map((m) => m as Map<String, dynamic>)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Errore caricando partner: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Partner'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner registrati'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _loadPartners,
        child: ListView.builder(
          itemCount: _partners.length,
          itemBuilder: (context, index) {
            final p = _partners[index];
            final status = p['status'] as String? ?? 'pending';
            final isActive = p['is_active'] as bool? ?? false;
            final name = p['name'] as String? ?? 'Senza nome';
            final addr =
                p['address'] as String? ?? 'Indirizzo non specificato';

            Color chipColor;
            switch (status) {
              case 'approved':
                chipColor = Colors.green;
                break;
              case 'rejected':
                chipColor = Colors.red;
                break;
              default:
                chipColor = cs.tertiary;
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text(name),
                subtitle: Text('$addr\nstatus: $status • attivo: $isActive'),
                isThreeLine: true,
                trailing: Chip(
                  label: Text(status),
                  backgroundColor: chipColor.withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: chipColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
