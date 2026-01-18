import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../autenticazione/auth_actions.dart';
import 'admin_partner_requests_screen.dart';

/// ---------------------------------------------------------------------------
///  Helper comuni per l'area admin
/// ---------------------------------------------------------------------------

/// Formatta una data breve in stile gg/mm/aaaa.
/// Accetta sia String (dal DB) che DateTime (già parsato).
String _formatDateShort(dynamic raw) {
  DateTime? dt;
  if (raw is String) {
    dt = DateTime.tryParse(raw);
  } else if (raw is DateTime) {
    dt = raw;
  }

  if (dt == null) return '';

  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  return '$d/$m/$y';
}

/// Colore del chip in base allo stato del partner.
Color _statusChipColor(String status, ColorScheme cs) {
  switch (status) {
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Colors.red;
    default:
      return cs.tertiary;
  }
}

/// ---------------------------------------------------------------------------
///  Shell principale per l’area Admin
/// ---------------------------------------------------------------------------
/// Bottom navigation:
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

/// ---------------------------------------------------------------------------
///  Dashboard Admin
/// ---------------------------------------------------------------------------
class _AdminDashboardPage extends StatelessWidget {
  const _AdminDashboardPage();

  Future<_AdminStats> _loadStats() async {
    final supabase = Supabase.instance.client;

    // Richieste partner in attesa
    final pendingReqData = await supabase
        .from('partner_requests')
        .select('id')
        .inFilter('status', ['submitted']) as List<dynamic>;
    final pendingRequests = pendingReqData.length;

    // Partner: approvati e attivi
    final partnersData = await supabase
        .from('partners')
        .select('id,status,is_active') as List<dynamic>;

    var partnersApproved = 0;
    var partnersActive = 0;

    for (final row in partnersData) {
      final m = row as Map<String, dynamic>;
      final status = m['status'] as String?;
      final isActive = m['is_active'] as bool? ?? false;

      if (status == 'approved') {
        partnersApproved++;
      }
      if (isActive) {
        partnersActive++;
      }
    }

    return _AdminStats(
      pendingRequests: pendingRequests,
      partnersApproved: partnersApproved,
      partnersActive: partnersActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BagDrop Admin'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(
            tooltip: 'Disconnetti',
            icon: const Icon(Icons.logout),
            onPressed: () {
              AuthActions.confirmAndLogout(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // CARD ACCOUNT ADMIN
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: cs.primary.withOpacity(0.12),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.email ?? 'admin@bagdrop.app',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Account amministratore BagDrop',
                              style: textTheme.bodySmall?.copyWith(
                                color: textTheme.bodySmall?.color?.withOpacity(
                                  0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // PANORAMICA STATISTICHE
              Text(
                'Panoramica',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              FutureBuilder<_AdminStats>(
                future: _loadStats(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // Tre stat card in versione "loading"
                    return Column(
                      children: const [
                        _AdminStatCard.loading(
                          label: 'Richieste in attesa',
                          icon: Icons.hourglass_top_outlined,
                        ),
                        SizedBox(height: 8),
                        _AdminStatCard.loading(
                          label: 'Partner approvati',
                          icon: Icons.verified_outlined,
                        ),
                        SizedBox(height: 8),
                        _AdminStatCard.loading(
                          label: 'Partner attivi',
                          icon: Icons.storefront_outlined,
                        ),
                      ],
                    );
                  }

                  if (snapshot.hasError || snapshot.data == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Errore caricando le statistiche admin.\n${snapshot.error}',
                        style: textTheme.bodySmall?.copyWith(color: cs.error),
                      ),
                    );
                  }

                  final stats = snapshot.data!;

                  return Column(
                    children: [
                      _AdminStatCard(
                        label: 'Richieste in attesa',
                        value: stats.pendingRequests.toString(),
                        icon: Icons.hourglass_top_outlined,
                      ),
                      const SizedBox(height: 8),
                      _AdminStatCard(
                        label: 'Partner approvati',
                        value: stats.partnersApproved.toString(),
                        icon: Icons.verified_outlined,
                      ),
                      const SizedBox(height: 8),
                      _AdminStatCard(
                        label: 'Partner attivi',
                        value: stats.partnersActive.toString(),
                        icon: Icons.storefront_outlined,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // AZIONI RAPIDE
              Text(
                'Azioni rapide',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminPartnerRequestsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Gestisci richieste partner'),
              ),
              const SizedBox(height: 8),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _AdminPartnersListPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.business_outlined),
                label: const Text('Vedi tutti i partner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  Lista Partner (per admin)
/// ---------------------------------------------------------------------------
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

  String _searchQuery = '';
  String _statusFilter = 'all'; // all | pending | approved | rejected

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
          .order('created_at') as List<dynamic>;

      setState(() {
        _partners =
            data.map((e) => e as Map<String, dynamic>).toList(growable: false);
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

  List<Map<String, dynamic>> get _filteredPartners {
    final query = _searchQuery.trim().toLowerCase();

    return _partners.where((p) {
      final name = (p['name'] as String? ?? '').toLowerCase();
      final status = (p['status'] as String? ?? 'pending');

      final matchesSearch = query.isEmpty || name.contains(query);
      final matchesFilter = _statusFilter == 'all' || status == _statusFilter;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Widget _buildFilterChip(String label, String value, ColorScheme cs) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _statusFilter = value;
          });
        },
        selectedColor: cs.primary.withOpacity(0.15),
        labelStyle: TextStyle(color: selected ? cs.primary : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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

    final partners = _filteredPartners;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner registrati'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header + ricerca + filtri
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Partner',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Cerca per nome...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Tutti', 'all', cs),
                      _buildFilterChip('Pending', 'pending', cs),
                      _buildFilterChip('Approved', 'approved', cs),
                      _buildFilterChip('Rejected', 'rejected', cs),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Lista partner
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPartners,
              child: partners.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Icon(Icons.inbox_outlined, size: 48, color: cs.outline),
                        const SizedBox(height: 12),
                        Text(
                          'Nessun partner trovato',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Prova a cambiare i filtri o la ricerca per vedere altri risultati.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: textTheme.bodySmall?.color?.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: partners.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final p = partners[index];
                        final status = p['status'] as String? ?? 'pending';
                        final isActive = p['is_active'] as bool? ?? false;
                        final name =
                            p['name'] as String? ?? 'Senza nome';
                        final addr = p['address'] as String? ??
                            'Indirizzo non specificato';
                        final capacity = p['capacity']?.toString() ?? '-';

                        final chipColor = _statusChipColor(status, cs);
                        final createdStr = _formatDateShort(p['created_at']);

                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AdminPartnerDetailScreen(partner: p),
                              ),
                            );
                          },
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: cs.primary.withOpacity(
                                          0.08,
                                        ),
                                        child: Icon(
                                          Icons.business_outlined,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              addr,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: chipColor.withOpacity(
                                                0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                color: chipColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isActive ? 'Attivo' : 'Non attivo',
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                              color: isActive
                                                  ? Colors.green[700]
                                                  : textTheme.bodySmall?.color
                                                      ?.withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Capacità: $capacity',
                                        style: textTheme.bodySmall,
                                      ),
                                      if (createdStr.isNotEmpty)
                                        Text(
                                          'Creato il $createdStr',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: textTheme.bodySmall?.color
                                                ?.withOpacity(0.7),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  Modello per le statistiche in dashboard
/// ---------------------------------------------------------------------------
class _AdminStats {
  final int pendingRequests;
  final int partnersApproved;
  final int partnersActive;

  _AdminStats({
    required this.pendingRequests,
    required this.partnersApproved,
    required this.partnersActive,
  });
}

/// Card per una singola statistica in dashboard.
class _AdminStatCard extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final bool isLoading;

  const _AdminStatCard({
    required this.label,
    required this.value,
    required this.icon,
    // ignore: unused_element_parameter
    this.isLoading = false,
    Key? key,
  }) : super(key: key);

  const _AdminStatCard.loading({
    required this.label,
    required this.icon,
    Key? key,
  })  : value = null,
        isLoading = true,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primary.withOpacity(0.1),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.bodySmall?.copyWith(
                      color: textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isLoading)
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    )
                  else
                    Text(
                      value ?? '-',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
///  Dettaglio singolo partner (vista admin)
/// ---------------------------------------------------------------------------
class AdminPartnerDetailScreen extends StatelessWidget {
  final Map<String, dynamic> partner;

  const AdminPartnerDetailScreen({super.key, required this.partner});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final id = partner['id'] as String? ?? '-';
    final name = partner['name'] as String? ?? 'Senza nome';
    final addr =
        partner['address'] as String? ?? 'Indirizzo non specificato';
    final status = partner['status'] as String? ?? 'pending';
    final isActive = partner['is_active'] as bool? ?? false;
    final capacity = partner['capacity']?.toString() ?? '-';
    final createdStr = _formatDateShort(partner['created_at']);

    final chipColor = _statusChipColor(status, cs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dettaglio partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card principale: nome + stato
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: cs.primary.withOpacity(0.08),
                          child: Icon(
                            Icons.business_outlined,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: $id',
                                style: textTheme.bodySmall?.copyWith(
                                  color: textTheme.bodySmall?.color
                                      ?.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chipColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status,
                                style: textTheme.bodySmall?.copyWith(
                                  color: chipColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isActive ? 'Attivo' : 'Non attivo',
                              style: textTheme.bodySmall?.copyWith(
                                color: isActive
                                    ? Colors.green[700]
                                    : textTheme.bodySmall?.color?.withOpacity(
                                        0.8,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place_outlined, size: 18),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            addr,
                            style: textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Capacità: $capacity',
                          style: textTheme.bodySmall,
                        ),
                        Text(
                          'Creato il: $createdStr',
                          style: textTheme.bodySmall?.copyWith(
                            color: textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
