import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/theme/app_theme.dart';

import '../../../../models/partner.dart';
import '../../autenticazione/auth_actions.dart';

class PartnerShellScope extends InheritedWidget {
  final Partner? partner;
  final User? user;
  final int index;
  final ValueChanged<int> setIndex;
  final VoidCallback reloadPartner;

  const PartnerShellScope({
    super.key,
    required super.child,
    required this.partner,
    required this.user,
    required this.index,
    required this.setIndex,
    required this.reloadPartner,
  });

  static PartnerShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PartnerShellScope>();
    assert(scope != null, 'PartnerShellScope non trovato nel widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant PartnerShellScope oldWidget) {
    return oldWidget.partner != partner ||
        oldWidget.user != user ||
        oldWidget.index != index;
  }
}

/// ✅ Brand “Bag Drop” (Bag bianco + Drop giallo) — lo teniamo per coerenza brand
class PartnerBrandTitle extends StatelessWidget {
  const PartnerBrandTitle({super.key, this.fontSize = 20});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Bag',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              color: Colors.white,
              letterSpacing: 0.2,
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
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerDrawer extends StatelessWidget {
  const PartnerDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PartnerShellScope.of(context);
    final cs = Theme.of(context).colorScheme;

    final p = scope.partner;
    final email = scope.user?.email ?? '';

    return Drawer(
      elevation: 0,
      backgroundColor: cs.surface,
      child: Column(
        children: [
          // ✅ HEADER: riprende lo stile del drawer utente (uniforme, non “pesante”)
          _PartnerDrawerHeader(partner: p, email: email),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _NavTile(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  selected: scope.index == 0,
                  onTap: () => _go(context, 0),
                ),
                _NavTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Prenotazioni',
                  selected: scope.index == 1,
                  onTap: () => _go(context, 1),
                ),
                _NavTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scanner',
                  selected: scope.index == 2,
                  onTap: () => _go(context, 2),
                ),
                _NavTile(
                  icon: Icons.business_outlined,
                  label: 'Spazi',
                  selected: scope.index == 3,
                  onTap: () => _go(context, 3),
                ),
                _NavTile(
                  icon: Icons.person_outline,
                  label: 'Profilo',
                  selected: scope.index == 4,
                  onTap: () => _go(context, 4),
                ),
              ],
            ),
          ),

          // ✅ ESCI: stessa logica, solo styling più coerente
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final didLogout = await AuthActions.confirmAndLogout(context);
                      if (!didLogout) return;
                      if (!context.mounted) return;

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
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, int index) {
    final scope = PartnerShellScope.of(context);
    scope.setIndex(index);
    Navigator.of(context).pop(); // chiudi drawer
  }
}

class _PartnerDrawerHeader extends StatelessWidget {
  final Partner? partner;
  final String email;

  const _PartnerDrawerHeader({
    required this.partner,
    required this.email,
  });

  String _firstLetter(String partnerName, String email) {
    final s = partnerName.trim().isNotEmpty ? partnerName.trim() : email.trim();
    if (s.isEmpty) return 'P';
    return s.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topPad = MediaQuery.of(context).padding.top;

    final name = partner?.name ?? 'Dashboard Partner';
    final initial = _firstLetter(name, email);

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 14, 16, 14),
      color: cs.primary, // ✅ uniforme con status bar/appbar (come drawer utente)
      child: Row(
        children: [


          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand in alto (leggero) + nome partner sotto
                const PartnerBrandTitle(fontSize: 18),
                const SizedBox(height: 8),

                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isNotEmpty ? email : 'Account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onPrimary.withOpacity(0.78),
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (partner != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PillInfo(
                        icon: partner!.isActive
                            ? Icons.verified_outlined
                            : Icons.pause_circle_outline,
                        label: partner!.isActive ? 'Attivo' : 'Sospeso',
                        bg: Colors.white.withOpacity(0.16),
                        fg: Colors.white,
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: selected ? cs.primary.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: cs.primary.withOpacity(0.06),
          highlightColor: cs.primary.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? cs.primary : cs.onSurface.withOpacity(0.75),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.88),
                    ),
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
      ),
    );
  }
}

class _PillInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  const _PillInfo({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
