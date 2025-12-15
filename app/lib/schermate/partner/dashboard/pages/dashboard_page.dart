import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/schermate/partner/dashboard/pages/bagdrop_pricing_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';
import '../../user_view/partner_drawer.dart';
import '../../../../models/partner.dart';
import '../../auth_partner/partner_registration_screen.dart';

class DashboardPage extends StatelessWidget {
  final Partner? partner;
  final VoidCallback onPartnerChanged;

  const DashboardPage({
    super.key,
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
        centerTitle: false,
      ),

      // ✅ Menu hamburger
      drawer: const PartnerDrawer(),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: partner == null
              ? _NoPartnerState(user: user, onPartnerChanged: onPartnerChanged)
              : _PartnerDashboard(partner: partner!),
        ),
      ),
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

class _NoPartnerState extends StatelessWidget {
  final User? user;
  final VoidCallback onPartnerChanged;

  const _NoPartnerState({required this.user, required this.onPartnerChanged});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      children: [
        _HeroCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.storefront_outlined, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard Partner',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nessuna attività associata al tuo account.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'UID: ${user?.id ?? "-"}',
          style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.65)),
        ),
        const SizedBox(height: 16),

        _HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inizia ora',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Compila la domanda di partnership per pubblicare il locale e iniziare a ricevere prenotazioni.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.75),
                ),
              ),
              const SizedBox(height: 14),
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
                        .then((_) => onPartnerChanged());
                  },
                  icon: const Icon(Icons.business_outlined),
                  label: const Text('Compila domanda partner'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartnerDashboard extends StatelessWidget {
  final Partner partner;

  const _PartnerDashboard({required this.partner});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      children: [
        // ✅ Hero card con nome + indirizzo + badge stato moderno
        _HeroCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.store_mall_directory_outlined,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      partner.address ?? 'Indirizzo non specificato',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StatusChip(isActive: partner.isActive),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Informazioni',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),

        Column(
          children: [
            _InfoRow(
              icon: Icons.inventory_2_outlined,
              title: 'Capacità',
              value: '${partner.capacity} posti',
              onTap: null,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.verified_outlined,
              title: 'Stato',
              value: partner.isActive ? 'Attivo' : 'Sospeso',
              onTap: null,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.local_offer_outlined,
              title: 'Tariffe',
              value: 'Listino BagDrop',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BagDropPricingScreen(),
                  ),
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 20),

        _HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prossimi step',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _Bullet(text: 'Prenotazioni giornaliere'),
              _Bullet(text: 'Guadagni'),
              _Bullet(text: 'Stato posti in tempo reale'),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final row = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.35)),
        ],
      ),
    );

    return onTap == null
        ? row
        : InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: row,
          );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isActive;
  const _StatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color fg = isActive ? Colors.green.shade800 : Colors.orange.shade800;
    final Color bg = isActive
        ? Colors.green.withOpacity(0.12)
        : Colors.orange.withOpacity(0.14);
    final IconData icon = isActive
        ? Icons.verified_outlined
        : Icons.pause_circle_outline;
    final String label = isActive ? 'Attivo' : 'Sospeso';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final child = Padding(
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: 170, // look “card grid”
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.5)),
            ],
          ],
        ),
      ),
    );

    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final Widget child;
  const _HeroCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
