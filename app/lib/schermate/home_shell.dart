import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'autenticazione/auth_actions.dart';
import '../models/partner.dart';

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
                          final didLogout = await AuthActions.confirmAndLogout(
                            context,
                          );
                          if (!didLogout)
                            return; // utente ha annullato o errore
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

/// Pagina mappa utente basata su Google Maps:
/// - mostra una mappa centrata su Milano (per ora)
/// - carica i partner approvati + attivi da Supabase (lat/lng non null)
/// - mostra un marker per partner
/// - tap marker → seleziona partner e mostra card in basso
/// - pulsanti + / - per zoom
/// - pulsante "Cerca attività" (per ora ricarica i partner, in futuro aprirà la search avanzata)
class _MappaPage extends StatefulWidget {
  const _MappaPage();

  @override
  State<_MappaPage> createState() => _MappaPageState();
}

class _MappaPageState extends State<_MappaPage> {
  /// Client Supabase per leggere i partner
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Lista dei partner da visualizzare
  List<Partner> _partners = [];

  /// Partner attualmente selezionato
  Partner? _selectedPartner;

  /// Stato di caricamento / errore
  bool _isLoading = true;
  String? _errorMessage;

  /// Controller della Google Map per muovere la camera (zoom, ecc.)
  GoogleMapController? _mapController;

  /// Centro di default: Milano
  static const LatLng _defaultCenter = LatLng(45.4642, 9.19);
  static const double _defaultZoom = 13.0;

  /// Icone per marker normale e selezionato
  static final BitmapDescriptor _markerDefaultIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  static final BitmapDescriptor _markerSelectedIcon =
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  @override
  void initState() {
    super.initState();
    // All'avvio carichiamo i partner
    _loadPartners();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Carica i partner approvati + attivi da Supabase
  Future<void> _loadPartners() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _supabase
          .from('partners')
          .select()
          .eq('status', 'approved')
          .eq('is_active', true)
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      final partners = (data as List<dynamic>)
          .map((row) => Partner.fromMap(row as Map<String, dynamic>))
          .toList();

      setState(() {
        _partners = partners;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Errore caricamento partner per mappa: $e\n$st');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare i partner in questo momento.';
      });
    }
  }

  /// Costruisce il set di marker per Google Maps
  Set<Marker> _buildMarkers() {
    // 1) Filtra solo i partner che hanno lat/lng non null (sicurezza lato Dart)
    final validPartners = _partners.where(
      (p) => p.lat != null && p.lng != null,
    );

    // 2) Crea un Marker per ogni partner valido
    return validPartners.map((partner) {
      final isSelected = _selectedPartner?.id == partner.id;

      return Marker(
        markerId: MarkerId(partner.id),
        position: LatLng(
          partner.lat!,
          partner.lng!,
        ), // qui uso ! perché ho filtrato sopra
        icon: isSelected ? _markerSelectedIcon : _markerDefaultIcon,
        onTap: () {
          setState(() {
            _selectedPartner = partner;
          });
        },
      );
    }).toSet();
  }

  /// Tap sulla mappa "vuota" → deseleziona il partner
  void _onMapTap(LatLng position) {
    setState(() {
      _selectedPartner = null;
    });
  }

  /// Zoom in
  Future<void> _zoomIn() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.zoomIn());
  }

  /// Zoom out
  Future<void> _zoomOut() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.zoomOut());
  }

  /// Pulsante "Cerca attività":
  /// per ora fa semplicemente un refresh dei partner e mostra uno SnackBar.
  /// In futuro lo userai per:
  /// - cercare per zona / indirizzo
  /// - filtrare per prezzo, tipo locale, ecc.
  Future<void> _onSearchPressed() async {
    await _loadPartners();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Attività aggiornate. In futuro qui ci sarà la ricerca avanzata.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        // 1) Google Map principale
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _defaultCenter,
            zoom: _defaultZoom,
          ),
          markers: _buildMarkers(),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          onTap: _onMapTap,
          // Per ora niente posizione utente, la aggiungeremo con un LocationService
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false, // usiamo i nostri pulsanti custom
          mapToolbarEnabled: false,
        ),

        // 2) Overlay caricamento
        if (_isLoading)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        // 3) Overlay errore
        if (_errorMessage != null && !_isLoading)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _errorMessage!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),

        // 4) Messaggio "nessun partner"
        if (!_isLoading && _errorMessage == null && _partners.isEmpty)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  'Nessun partner disponibile in questa zona.\n'
                  'Prova a ricaricare più tardi.',
                  style: textTheme.bodyMedium,
                ),
              ),
            ),
          ),

        // 5) Pulsante "Cerca attività" in alto
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _onSearchPressed,
                  icon: const Icon(Icons.search),
                  label: const Text('Cerca attività'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 6) Pulsanti zoom + / - in basso a destra
        Positioned(
          right: 16,
          bottom: _selectedPartner != null
              ? 140
              : 24, // se c'è la card li spostiamo più in alto
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                onPressed: _zoomIn,
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                onPressed: _zoomOut,
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),

        // 7) Card in basso con il partner selezionato
        if (_selectedPartner != null)
          _PartnerBottomCard(
            partner: _selectedPartner!,
            onClose: () {
              setState(() {
                _selectedPartner = null;
              });
            },
            onOpenDetail: () {
              // TODO: navigazione alla schermata dettagli partner
              // Navigator.of(context).push(...);
            },
          ),
      ],
    );
  }
}

/// Card in basso che mostra le informazioni principali
/// del partner selezionato sulla mappa.
///
/// Per ora:
/// - mostra nome, prezzi, capacità
/// - ha un placeholder per l'immagine di copertina
/// - espone un bottone "Apri scheda" (callback onOpenDetail)
class _PartnerBottomCard extends StatelessWidget {
  final Partner partner;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  const _PartnerBottomCard({
    required this.partner,
    required this.onClose,
    required this.onOpenDetail,
  });

  /// Helper per formattare i prezzi se presenti
  String _formatPrice(double? value, String label) {
    if (value == null) return '';
    // In futuro potrai internazionalizzare/format tare meglio con intl
    return '$label ${value.toStringAsFixed(2)} €';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final price2h = _formatPrice(partner.price2h, '2h da');
    final pricePerDay = _formatPrice(partner.pricePerDay, 'Giorno da');

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Riga principale: immagine + info + X di chiusura
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Placeholder per immagine di copertina:
                    // in futuro potrai collegare PartnerPhotoRepo.fetchCoverPhoto(partner.id)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: cs.surfaceVariant,
                      ),
                      child: const Icon(Icons.photo, size: 32),
                    ),
                    const SizedBox(width: 12),
                    // Testi (nome, indirizzo, prezzi)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.name,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (partner.address != null &&
                              partner.address!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                partner.address!,
                                style: textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (price2h.isNotEmpty)
                                Text(
                                  price2h,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.primary,
                                  ),
                                ),
                              if (price2h.isNotEmpty && pricePerDay.isNotEmpty)
                                const SizedBox(width: 8),
                              if (pricePerDay.isNotEmpty)
                                Text(pricePerDay, style: textTheme.bodyMedium),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Pulsante chiusura card
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Riga inferiore: info extra + bottone "Apri scheda"
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Capacità: ${partner.capacity}',
                      style: textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: onOpenDetail,
                      child: const Text('Apri scheda'),
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
