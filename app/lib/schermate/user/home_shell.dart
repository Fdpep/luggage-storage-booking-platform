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
                _DrawerHeader(
                  isLoggedIn: _isLoggedIn,
                  user: _user,
                  onAction: _tap,
                ),

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
/// - “Bag” bianco fisso
/// - “Drop” giallo brand
class _LogoTitle extends StatelessWidget {
  const _LogoTitle({this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'BagDrop',
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Bag',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                color: Colors.white,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: 'Drop',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                color: AppTheme.brandYellow,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header del Drawer:
/// - Non loggato: invito ad accedere/registrarsi.
/// - Loggato: avatar con iniziali + email.
/// Usa `onAction(ctx, '...')` per azioni non implementate (es. _tap).
class _DrawerHeader extends StatelessWidget {
  final bool isLoggedIn;
  final User? user;
  final void Function(BuildContext context, String target)? onAction;

  const _DrawerHeader({
    required this.isLoggedIn,
    required this.user,
    this.onAction,
  });

  String _firstLetter(String fullName, String email) {
    final s = fullName.trim().isNotEmpty ? fullName.trim() : email.trim();
    if (s.isEmpty) return 'U';
    return s.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topPad = MediaQuery.of(context).padding.top;

    final email = user?.email ?? '';
    final meta = user?.userMetadata ?? {};
    final first = (meta['first_name'] as String?)?.trim() ?? '';
    final last = (meta['last_name'] as String?)?.trim() ?? '';
    final fullName = ('$first $last').trim();

    final initial = _firstLetter(fullName, email);

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 14, 16, 14),
      color: cs.primary, // ✅ niente gradiente: uniforme con status bar/appbar
      child: Row(
        children: [
          // Avatar coerente col profilo: soft purple + iniziale viola
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            alignment: Alignment.center,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white.withOpacity(0.92),
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn
                      ? (fullName.isNotEmpty ? fullName : 'Profilo')
                      : 'Benvenuto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLoggedIn
                      ? (email.isNotEmpty ? email : 'Account')
                      : 'Accedi o registrati per gestire prenotazioni e profilo.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onPrimary.withOpacity(0.78),
                    height: 1.25,
                  ),
                ),
                if (!isLoggedIn) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onAction?.call(context, 'Accedi'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: cs.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Accedi'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              onAction?.call(context, 'Registrati'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.35),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Registrati'),
                        ),
                      ),
                    ],
                  ),
                ],
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

  String _firstLetter(String fullName, String email) {
    final s = fullName.trim().isNotEmpty ? fullName.trim() : email.trim();
    if (s.isEmpty) return 'U';
    return s.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget thinDivider() => Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.7),
    );

    Widget iosSection(List<Widget> children) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: children),
        ),
      );
    }

    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title,
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface.withOpacity(0.9),
          ),
        ),
      );
    }

    Widget infoRow({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurface.withOpacity(0.75)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget actionRow({
      required IconData icon,
      required String title,
      String? subtitle,
      Color? color,
      required VoidCallback onTap,
    }) {
      final rowColor = color ?? cs.onSurface;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: cs.onSurface.withOpacity(0.04),
          splashColor: cs.onSurface.withOpacity(0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: rowColor.withOpacity(0.85)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: rowColor.withOpacity(0.92),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.65),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: cs.onSurface.withOpacity(0.35),
                ),
              ],
            ),
          ),
        ),
      );
    }

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

    final initial = _firstLetter(fullName, email);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Titolo pagina (gerarchia iOS)
          Text(
            'Profilo',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Dati account e preferenze.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),

          // Header profilo in section
          iosSection([
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.primary.withOpacity(0.12),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: cs.primary.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            role,
                            style: tt.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
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
          ]),

          const SizedBox(height: 16),
          sectionTitle('Dati personali'),

          iosSection([
            infoRow(icon: Icons.badge_outlined, label: 'Nome', value: fullName),
            thinDivider(),
            infoRow(
              icon: Icons.phone_outlined,
              label: 'Telefono',
              value: phone,
            ),
            thinDivider(),
            infoRow(icon: Icons.mail_outline, label: 'Email', value: email),
            thinDivider(),
            infoRow(
              icon: Icons.event_outlined,
              label: 'Cliente su BagDrop dal',
              value: createdText,
            ),
            thinDivider(),
            infoRow(
              icon: Icons.receipt_long_outlined,
              label: 'Prenotazioni effettuate',
              value: '$_myBookingsCount',
            ),
            thinDivider(),

            actionRow(
              icon: Icons.edit_outlined,
              title: 'Modifica dati',
              subtitle: 'Aggiorna le informazioni del profilo',
              onTap: () async {
                // 🔧 FIX: push sul rootNavigator per evitare apertura “in overlay/trasparente”
                final changed = await Navigator.of(context, rootNavigator: true)
                    .push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const _EditProfileScreen(),
                      ),
                    );

                if (!mounted) return;
                if (changed == true) {
                  await _loadData();
                }
              },
            ),
          ]),

          const SizedBox(height: 16),
          sectionTitle('Azioni account'),

          iosSection([
            actionRow(
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

                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            thinDivider(),
            actionRow(
              icon: Icons.delete_outline,
              title: 'Elimina account',
              subtitle: 'Operazione irreversibile',
              color: cs.error,
              onTap: () async {
                // 🔧 FIX: push sul rootNavigator per evitare apertura “in overlay/trasparente”
                final deleted = await Navigator.of(context, rootNavigator: true)
                    .push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const DeleteAccountScreen(),
                      ),
                    );

                if (!mounted) return;
                if (deleted == true) {
                  // la schermata gestisce già signOut/redirect
                }
              },
            ),
          ]),

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
