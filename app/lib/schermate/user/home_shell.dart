import 'dart:async';
import 'package:BagDrop/schermate/partner/dashboard/pages/bagdrop_pricing_screen.dart';
import 'package:BagDrop/schermate/autenticazione/registrazione.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../autenticazione/auth_actions.dart';
import '../map/user_map_page.dart';
import '../autenticazione/accesso.dart';
import 'package:BagDrop/models/partner_booking.dart';
import '../../services/supabase/partner_booking_repo.dart';
import 'bookings/user_bookings_page.dart';
import 'package:BagDrop/models/user_profile.dart';
import 'package:BagDrop/services/supabase/user_repo.dart';
import 'delete_account_screen.dart';

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

  bool get _isLoggedIn => _supabase.auth.currentSession != null;
  User? get _user => _supabase.auth.currentUser;

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
    _checkOtpVerified();
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

  // Controlla se l’utente ha verificato l’OTP (e-mail).
  // Se non è verificato, lo disconnette e lo riporta alla root.

  Future<void> _checkOtpVerified() async {
    final session = _supabase.auth.currentSession;
    final user = session?.user;

    // Nessuna sessione = può essere OSPITE → non faccio nulla
    if (user == null) {
      return;
    }

    final meta = user.userMetadata ?? {};
    final otpVerified = meta['otp_verified'] == true;

    // Se ha sessione ma NON è verificato, non deve stare in HomeShell
    if (!otpVerified) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _supabase.auth.signOut();
        if (!mounted) return;

        // Torna alla root dell'app (RootGate) oppure alla schermata di accesso
        Navigator.of(context).popUntil((route) => route.isFirst);

        // Volendo, puoi anche mostrare un messaggio:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Completa prima la verifica dell’e-mail per accedere all’area utente.',
            ),
          ),
        );
      });
    }
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

    return Scaffold(
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
        actions: const [],
      ),
      //drawer laterale (menu a panino)
      drawer: Drawer(
        child: Builder(
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            final topPad = MediaQuery.of(ctx).padding.top;

            return Column(
              children: [
                Container(height: topPad, color: cs.primary),
                _DrawerHeader(isLoggedIn: _isLoggedIn, user: _user),

                // ✅ voci menu (scrollabili)
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const SizedBox(height: 8),

                      _ItemTile(
                        icon: Icons.list_alt_outlined,
                        label: 'Le mie prenotazioni',
                        onTap: (c) {
                          Navigator.of(c).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UserBookingsPage(),
                            ),
                          );
                        },
                      ),

                      _ItemTile(
                        icon: Icons.person_outline,
                        label: 'Profilo',
                        onTap: (c) {
                          Navigator.of(c).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _UserProfileScreen(user: _user),
                            ),
                          );
                        },
                      ),

                      const Divider(height: 24),

                      _ItemTile(
                        icon: Icons.payments_outlined,
                        label: 'Tariffe BagDrop',
                        onTap: (c) {
                          Navigator.of(c).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BagDropPricingScreen(),
                            ),
                          );
                        },
                      ),

                      _ItemTile(
                        icon: Icons.help_outline,
                        label: 'Assistenza e Domande frequenti',
                        onTap: (c) => _tap(c, 'Assistenza e FAQ'),
                      ),

                      _ItemTile(
                        icon: Icons.settings_outlined,
                        label: 'Impostazioni',
                        onTap: (c) => _tap(c, 'Impostazioni'),
                      ),

                      _ItemTile(
                        icon: Icons.description_outlined,
                        label: 'Documenti contrattuali & Privacy',
                        onTap: (c) =>
                            _tap(c, 'Documenti contrattuali & Privacy'),
                      ),
                    ],
                  ),
                ),

                // ✅ ESCI fisso in basso (come volevi)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final didLogout =
                                await AuthActions.confirmAndLogout(context);
                            if (!didLogout) return;
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Disconnesso')),
                            );
                            Navigator.of(context).pop(); // chiudi drawer
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Esci'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      // ✅ HOME = SOLO MAPPA
      body: const UserMapPage(),
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
  const _LogoTitle();

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

class _ProfiloPage extends StatefulWidget {
  final User? user;
  const _ProfiloPage({this.user});

  @override
  State<_ProfiloPage> createState() => _ProfiloPageState();
}

class _ProfiloPageState extends State<_ProfiloPage> {
  final _userRepo = UserRepo();

  User? _currentUser;
  UserProfile? _userProfile;
  bool _loading = true;
  String? _error;
  int _myBookingsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser ?? widget.user;

      if (user == null) {
        throw StateError('Nessun utente autenticato.');
      }

      // Profilo user_profiles
      UserProfile? profile;
      try {
        profile = await _userRepo.getMe();
      } catch (_) {
        profile =
            null; // se non esiste ancora la riga non è un errore bloccante
      }

      // Numero prenotazioni totali effettuate
      final bookingRepo = PartnerBookingRepo(client);
      List<PartnerBooking> myBookings = [];
      try {
        myBookings = await bookingRepo.getMyBookings();
      } catch (_) {
        myBookings = [];
      }

      if (!mounted) return;

      setState(() {
        _currentUser = user;
        _userProfile = profile;
        _myBookingsCount = myBookings.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossibile caricare i dati profilo. Riprova più tardi.';
      });
    }
  }

  String _buildFullName(Map<String, dynamic> meta) {
    final first = (meta['first_name'] as String?)?.trim() ?? '';
    final last = (meta['last_name'] as String?)?.trim() ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return _currentUser?.email ?? 'Utente BagDrop';
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'partner':
        return 'Partner';
      case 'admin':
        return 'Amministratore';
      default:
        return 'Utente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentUser == null) {
      return const Center(child: Text('Nessun utente autenticato.'));
    }

    final meta = _currentUser!.userMetadata ?? {};
    final fullName = _buildFullName(meta);
    final email = _currentUser!.email ?? 'n/d';
    final phone = (meta['phone'] as String?)?.trim().isNotEmpty == true
        ? (meta['phone'] as String).trim()
        : 'Non impostato';

    final role = _roleLabel(_userProfile?.role ?? 'user');
    final createdAt = _userProfile?.createdAt;
    final createdText = createdAt == null
        ? 'n/d'
        : '${createdAt.day.toString().padLeft(2, '0')}/'
              '${createdAt.month.toString().padLeft(2, '0')}/'
              '${createdAt.year}';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Profilo'),
          const SizedBox(height: 12),

          // HEADER PROFILO
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.brandYellow,
                    foregroundColor: Colors.black,
                    child: Text(
                      fullName.isNotEmpty
                          ? fullName[0].toUpperCase()
                          : (email.isNotEmpty ? email[0].toUpperCase() : 'U'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
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

          Text(
            'Dati personali',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          _CardGroup(
            children: [
              _InfoTile(
                label: 'Nome',
                value: fullName,
                icon: Icons.badge_outlined,
              ),
              _InfoTile(
                label: 'Telefono',
                value: phone,
                icon: Icons.phone_outlined,
              ),
              _InfoTile(label: 'Email', value: email, icon: Icons.mail_outline),
              _InfoTile(
                label: 'Cliente su BagDrop dal',
                value: createdText,
                icon: Icons.event_outlined,
              ),
              _InfoTile(
                label: 'Prenotazioni effettuate',
                value: '$_myBookingsCount',
                icon: Icons.receipt_long_outlined,
              ),

              // ✅ Modifica dati (come riga, non bottone)
              _ActionTile(
                icon: Icons.edit_outlined,
                title: 'Modifica dati',
                subtitle: 'Aggiorna le informazioni del profilo',
                onTap: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const _EditProfileScreen(),
                    ),
                  );
                  if (changed == true) {
                    await _loadData();
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            'Azioni account',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          _CardGroup(
            children: [
              _ActionTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                subtitle: 'Esci dal tuo account',
                onTap: () async {
                  final didLogout = await AuthActions.confirmAndLogout(context);
                  if (!didLogout) return;
                  if (!mounted) return;

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Disconnesso')));

                  // ✅ torna alla root (dove di solito hai AuthGate / schermata "Accedi")
                  Navigator.of(context).popUntil((route) => route.isFirst);

                  // opzionale: se questa pagina rimane visibile per qualche motivo
                  // setState(() => _currentUser = null);
                },
              ),
              _ActionTile(
                icon: Icons.delete_outline,
                title: 'Elimina account',
                subtitle: 'Operazione irreversibile',
                color: cs.error,
                onTap: () async {
                  final deleted = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const DeleteAccountScreen(),
                    ),
                  );
                  if (deleted == true && mounted) {
                    // di solito la schermata gestisce già signOut/redirect
                  }
                },
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

//helper widget titolo sezioni profilo:
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (color ?? cs.primary).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: effectiveColor),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: effectiveColor),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: cs.onSurface.withOpacity(0.65)),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: cs.onSurface.withOpacity(0.45),
      ),
      onTap: onTap,
    );
  }
}

class _CardGroup extends StatelessWidget {
  final List<Widget> children;

  const _CardGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withOpacity(0.35),
              ),
          ],
        ],
      ),
    );
  }
}

/// Schermata separata per modificare i dati del profilo utente.
/// Apre un form con Nome, Cognome e Telefono.
/// Alla fine aggiorna i metadata di Supabase + user_profiles.full_name
class _EditProfileScreen extends StatefulWidget {
  const _EditProfileScreen();

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final meta = user?.userMetadata ?? {};

    _firstNameCtrl.text = (meta['first_name'] as String?) ?? '';
    _lastNameCtrl.text = (meta['last_name'] as String?) ?? '';
    _phoneCtrl.text = (meta['phone'] as String?) ?? '';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('Nessun utente autenticato');
      }

      // Aggiorniamo i metadata mantenendo il resto (otp_verified, source, ecc.)
      final meta = Map<String, dynamic>.from(user.userMetadata ?? {});
      meta['first_name'] = _firstNameCtrl.text.trim();
      meta['last_name'] = _lastNameCtrl.text.trim();
      meta['phone'] = _phoneCtrl.text.trim();

      await client.auth.updateUser(UserAttributes(data: meta));

      // Aggiorniamo anche user_profiles.full_name per avere un nome leggibile lì
      final fullName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
      final userRepo = UserRepo();
      await userRepo.upsertMe(nomeCompleto: fullName);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dati profilo aggiornati')));

      // Torniamo alla pagina profilo, indicando che ci sono state modifiche
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aggiorna i tuoi dati personali',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Nome
                TextFormField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci il nome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Cognome
                TextFormField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cognome',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci il cognome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Telefono
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    hintText: '+39 ...',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) {
                      return 'Inserisci un numero di telefono';
                    }
                    final digitsOnly = t.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digitsOnly.length < 9 || digitsOnly.length > 15) {
                      return 'Inserisci un numero di telefono valido';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salva modifiche'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const RegistrazioneScreen(),
                            ),
                          );
                        },
                        child: const Text('Registrati'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const AccessoScreen(),
                            ),
                          );
                        },
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
  final IconData? icon;

  const _InfoTile({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: icon == null
          ? null
          : Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary, size: 20),
            ),
      title: Text(
        label,
        style: TextStyle(
          color: cs.onSurface.withOpacity(0.65),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.45,
        ),
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _UserBookingsScreen extends StatelessWidget {
  const _UserBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserBookingsPage(); // <-- NO Scaffold qui
  }
}

class _UserProfileScreen extends StatelessWidget {
  final User? user;
  const _UserProfileScreen({this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: _ProfiloPage(user: user),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip ?? '',
            child: Icon(icon, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}
