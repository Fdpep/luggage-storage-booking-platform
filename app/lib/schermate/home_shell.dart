import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// HomeShell = contenitore della home:
/// - AppBar: hamburger (Drawer), titolo "BagDrop", icona filtro
/// - Drawer: voci diverse se non loggato/loggato
/// - BottomNavigation: Mappa / Prenotazioni / Profilo
/// - Body: _pages[_currentIndex] con gating sulle tab 2-3
///
/// Nota: in questa iterazione le pagine sono placeholder/scheletri.
/// La logica di login/password verrà nel prossimo step.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  int _currentIndex = 0;

  bool get _isLoggedIn => _supabase.auth.currentSession != null;
  User? get _user => _supabase.auth.currentUser;

  // Navigazione tab bottom
  void _onBottomTap(int idx) {
    setState(() => _currentIndex = idx);
  }

  // Tap generico per voci “non ancora implementate”
  void _tap(BuildContext ctx, String label) {
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text('$label — in arrivo')));
    Navigator.of(ctx).maybePop(); // chiude eventuale Drawer
  }

  @override
  void initState() {
    super.initState();
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      // Refresh UI (icone/menu)
      setState(() {});
      // Se rientra da link di reset password → chiedi nuova password
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _showPasswordResetSheet();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isGuest = Supabase.instance.client.auth.currentUser == null;
    if (isGuest) {
    debugPrint('[HomeShell] guest mode attiva (no session)');
  }

    // Pagine con gating (tab 1 sempre visibile; 2-3 richiedono login)
    final pages = <Widget>[
      const _MappaPage(),
      _isLoggedIn
          ? const _PrenotazioniPage()
          : const _RequireAuthCard(tabTitle: 'Prenotazioni'),
      _isLoggedIn
          ? _ProfiloPage(user: _user)
          : const _RequireAuthCard(tabTitle: 'Profilo'),
    ];

    return Scaffold(
      // AppBar superiore con hamburger + titolo + filtro
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Apri menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: _LogoTitle(),
        actions: [
          IconButton(
            tooltip: 'Filtri mappa',
            onPressed: () => _tap(context, 'Filtri mappa'),
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),

      // Drawer laterale (menu a panino)
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              // Header: cambia se loggato / non loggato
              _DrawerHeader(isLoggedIn: _isLoggedIn, user: _user),

              // Voci specifiche per NON loggato
              if (!_isLoggedIn) ...[
                const SizedBox(height: 8),
                _ItemTile(
                  icon: Icons.login,
                  label: 'Accedi',
                  onTap: (ctx) => Navigator.of(ctx).pushNamed('/accesso'),
                ),
                _ItemTile(
                  icon: Icons.person_add_outlined,
                  label: 'Registrati',
                  onTap: (ctx) => Navigator.of(ctx).pushNamed('/registrazione'),
                ),
                const Divider(height: 24),

                // Sezioni extra (come da tua richiesta)
                _ItemTile(
                  icon: Icons.help_outline,
                  label: 'Assistenza e Domande frequenti',
                  onTap: (ctx) => _tap(ctx, 'Assistenza e FAQ'),
                ),
                _ItemTile(
                  icon: Icons.luggage_outlined,
                  label: 'Lascia a BagDrop',
                  onTap: (ctx) => _tap(ctx, 'Lascia a BagDrop'),
                ),
                _ItemTile(
                  icon: Icons.menu_book_outlined,
                  label: 'Istruzioni',
                  onTap: (ctx) => _tap(ctx, 'Istruzioni'),
                ),
                _ItemTile(
                  icon: Icons.payments_outlined,
                  label: 'Tariffe BagDrop',
                  onTap: (ctx) => _tap(ctx, 'Tariffe BagDrop'),
                ),
                _ItemTile(
                  icon: Icons.description_outlined,
                  label: 'Documenti contrattuali & Privacy',
                  onTap: (ctx) => _tap(ctx, 'Documenti contrattuali & Privacy'),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8,
                  ),
                  child: Text(
                    'v0.1 • Pilot Milano – Santa Sofia',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ],

              // Voci per LOGGATO
              if (_isLoggedIn) ...[
                const SizedBox(height: 8),
                _ItemTile(
                  icon: Icons.list_alt_outlined,
                  label: 'Le mie prenotazioni',
                  onTap: (ctx) {
                    setState(() => _currentIndex = 1);
                    Navigator.of(ctx).pop();
                  },
                ),
                _ItemTile(
                  icon: Icons.person_outline,
                  label: 'Profilo',
                  onTap: (ctx) {
                    setState(() => _currentIndex = 2);
                    Navigator.of(ctx).pop();
                  },
                ),
                const Divider(height: 24),
                _ItemTile(
                  icon: Icons.support_agent_outlined,
                  label: 'Supporto',
                  onTap: (ctx) => _tap(ctx, 'Supporto'),
                ),
                _ItemTile(
                  icon: Icons.settings_outlined,
                  label: 'Impostazioni',
                  onTap: (ctx) => _tap(ctx, 'Impostazioni'),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _supabase.auth.signOut();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Disconnesso')),
                          );
                          Navigator.of(context).pop(); // chiudi drawer
                          setState(() => _currentIndex = 0); // torna a mappa
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Esci'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'v0.1 • Pilot Milano – Santa Sofia',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),

      // Corpo principale: pagine
      body: pages[_currentIndex],

      // Bottom navigation (Mappa sempre accessibile)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black87,
        unselectedItemColor: Colors.grey,
        onTap: _onBottomTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Mappa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            label: 'Prenotazioni',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profilo',
          ),
        ],
      ),
    );
  }

  void _showPasswordResetSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final _formKey = GlobalKey<FormState>();
        final _pwd1 = TextEditingController();
        final _pwd2 = TextEditingController();
        bool busy = false;

        Future<void> doUpdate() async {
          FocusScope.of(ctx).unfocus();
          if (!(_formKey.currentState?.validate() ?? false)) return;

          busy = true;
          (ctx as Element).markNeedsBuild();

          try {
            await _supabase.auth.updateUser(
              UserAttributes(password: _pwd1.text),
            );
            if (!mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Password aggiornata.')),
            );
          } on AuthException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Errore: ${e.message}')));
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
          } finally {
            busy = false;
            (ctx).markNeedsBuild();
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Imposta nuova password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pwd1,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nuova password',
                  ),
                  validator: (v) => (v == null || v.trim().length < 6)
                      ? 'Minimo 6 caratteri'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pwd2,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Conferma password',
                  ),
                  validator: (v) => (v?.trim() != _pwd1.text.trim())
                      ? 'Le password non coincidono'
                      : null,
                  onFieldSubmitted: (_) => doUpdate(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: busy ? null : doUpdate,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Aggiorna'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Titolo “BagDrop” in AppBar con brand:
/// - “Bag” chiaro
/// - “Drop” giallo
class _LogoTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'Bag',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          TextSpan(text: ' '),
          TextSpan(
            text: 'Drop',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppTheme.brandYellow,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header del Drawer:
/// - Non loggato: invito ad accedere/registrarsi.
/// - Loggato: avatar con iniziali + email.
class _DrawerHeader extends StatelessWidget {
  final bool isLoggedIn;
  final User? user;

  const _DrawerHeader({required this.isLoggedIn, required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!isLoggedIn) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.primary,
          gradient: LinearGradient(
            colors: [cs.primary, AppTheme.brandPurple.withOpacity(0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Benvenuto in', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 4),
            Text(
              'BagDrop',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Accedi o registrati per prenotare e gestire i tuoi depositi.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final email = user?.email ?? 'utente@bagdrop.app';
    final initials = (email.isNotEmpty ? email[0] : 'U').toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: cs.primary,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.brandYellow,
            foregroundColor: Colors.black,
            child: Text(
              initials,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connesso come',
                  style: TextStyle(color: Colors.white70),
                ),
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Voce riutilizzabile del Drawer.
class _ItemTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final void Function(BuildContext) onTap;

  const _ItemTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => onTap(context),
    );
  }
}

/// PAGINE (scheletri)

class _MappaPage extends StatelessWidget {
  const _MappaPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 12),
          const Text(
            'Mappa (placeholder)\nQui integreremo la mappa con filtri.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PrenotazioniPage extends StatelessWidget {
  const _PrenotazioniPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SectionTitle('Le mie prenotazioni'),
        SizedBox(height: 8),
        _HintCard(
          'Non hai ancora prenotazioni. Quando prenoti, appariranno qui.',
        ),
      ],
    );
  }
}

class _ProfiloPage extends StatelessWidget {
  final User? user;
  const _ProfiloPage({this.user});

  @override
  Widget build(BuildContext context) {
    final email = user?.email ?? 'n/d';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Profilo'),
        const SizedBox(height: 8),
        _InfoTile(label: 'Email', value: email),
        const _InfoTile(label: 'KYC', value: 'none (placeholder)'),
      ],
    );
  }
}

/// Gate: se l’utente non è loggato, mostra invito ad accedere/registrarsi.
/// Usato nelle tab "Prenotazioni" e "Profilo".
class _RequireAuthCard extends StatelessWidget {
  final String tabTitle;
  const _RequireAuthCard({required this.tabTitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  '$tabTitle',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Accedi o registrati per continuare.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/registrazione'),
                        child: const Text('Registrati'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/accesso'),
                        child: const Text('Accedi'),
                      ),
                    ),
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

/// UI helpers

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
        fontSize: 18,
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
      ),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
