import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/schermate/partner/dashboard/pages/bagdrop_pricing_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';
import '../../user_view/partner_drawer.dart';
import '../../../../models/partner.dart';
import '../../auth_partner/partner_registration_screen.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';

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
        // iOS-like: pulita, niente ombre forti
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,

        // ✅ RICHIESTO: titolo centrale in home
        centerTitle: true,

        title: const _LogoTitle(),

        // tap area ok su azioni future
        titleSpacing: 12,
      ),

      // ✅ Menu hamburger
      drawer: const PartnerDrawer(),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: partner == null
              ? _NoPartnerState(user: user, onPartnerChanged: onPartnerChanged)
              : _PartnerDashboard(
                  partner: partner!,
                  onPartnerChanged: onPartnerChanged,
                ),
        ),
      ),
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
  final VoidCallback onPartnerChanged;

  const _PartnerDashboard({required this.partner , required this.onPartnerChanged});

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
            _CapacityCard(partnerId: partner.id),
            const SizedBox(height: 10),

            _BookingToggleCard(
              partnerId: partner.id,
              accepting: partner.acceptingBookings,
              onRefresh: onPartnerChanged,
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

class _CapacityCard extends StatefulWidget {
  final String partnerId;
  const _CapacityCard({required this.partnerId});

  @override
  State<_CapacityCard> createState() => _CapacityCardState();
}

class _CapacityCardState extends State<_CapacityCard> {
  late final PartnerBookingRepo _repo;
  PartnerAvailability? _a;
  Object? _err;
  bool _loading = true;

  // refresh live (poll)
  static const _pollEvery = Duration(seconds: 20);
  // animazione soft
  static const _animDuration = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _repo = PartnerBookingRepo(Supabase.instance.client);
    _load();
    _startPolling();
  }

  void _startPolling() {
    // poll semplice: ogni 20s ricarica
    Future.doWhile(() async {
      await Future.delayed(_pollEvery);
      if (!mounted) return false;
      await _load(silent: true);
      return mounted;
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }

    try {
      final a = await _repo.getPartnerAvailability(widget.partnerId);
      if (!mounted) return;
      setState(() {
        _a = a;
        _err = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e;
        _loading = false;
      });
    }
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        return AlertDialog(
          title: const Text('Come funziona lo spazio'),
          content: Text(
            'Lo spazio non è “per taglia separata”.\n\n'
            'Il sistema usa una capacità generale + eventuali extra dedicati.\n'
            'Per la disponibilità, prima vengono consumati gli extra e poi la capacità generale.\n\n'
            'Questi numeri indicano quante valigie puoi ancora accettare per ogni taglia (in questo momento).',
            style: tt.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.85)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget cardChild(Widget child) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: child,
        );

    // Header comune (icona + titolo + help + refresh)
    Widget header({required String subtitle}) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.inventory_2_outlined, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spazio disponibile',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Info',
            onPressed: () => _showHelp(context),
            icon: Icon(Icons.info_outline, color: cs.onSurface.withOpacity(0.65)),
          ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: () => _load(),
            icon: Icon(Icons.refresh, color: cs.onSurface.withOpacity(0.65)),
          ),
        ],
      );
    }

    if (_loading && _a == null) {
      return cardChild(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(subtitle: 'Caricamento…'),
            const SizedBox(height: 12),
            // barra loading “fake” (vuoto grigio + barra indeterminate)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(height: 12, color: cs.onSurface.withOpacity(0.12)),
                  const LinearProgressIndicator(minHeight: 12),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_err != null || _a == null) {
      return cardChild(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(subtitle: 'Errore'),
            const SizedBox(height: 8),
            Text(
              'Impossibile caricare la disponibilità.',
              style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }

    final a = _a!;

    final capacityU = a.capacityTotal <= 0 ? 0 : a.capacityTotal;
    final usedU = a.usedTotal < 0 ? 0 : a.usedTotal;

    final progress = capacityU == 0 ? 0.0 : (usedU / capacityU).clamp(0.0, 1.0);

    return cardChild(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(subtitle: _loading ? 'Aggiornamento…' : 'Aggiornato ora'),
          const SizedBox(height: 12),

          /// ✅ Barra con vuoto grigio + animazione soft
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 12, color: cs.onSurface.withOpacity(0.12)),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: _animDuration,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) {
                    return FractionallySizedBox(
                      widthFactor: v,
                      child: Container(height: 12, color: cs.primary),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Spazio rimasto per:',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BagChip(
                label: 'S',
                count: a.acceptS ? a.availableS : 0,
                enabled: a.acceptS && a.availableS > 0,
              ),
              _BagChip(
                label: 'M',
                count: a.acceptM ? a.availableM : 0,
                enabled: a.acceptM && a.availableM > 0,
              ),
              _BagChip(
                label: 'L',
                count: a.acceptL ? a.availableL : 0,
                enabled: a.acceptL && a.availableL > 0,
              ),
            ],
          ),

          // opzionale: nota piccola per chiarire che non è “tutto insieme”
          const SizedBox(height: 10),
          Text(
            'Nota: sono disponibilità per taglia, non una somma “S+M+L”.',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }
}

class _BagChip extends StatelessWidget {
  final String label;
  final int count;
  final bool enabled;

  const _BagChip({
    required this.label,
    required this.count,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = enabled
        ? cs.primary.withOpacity(0.12)
        : cs.onSurface.withOpacity(0.08);

    final Color fg = enabled
        ? cs.primary
        : cs.onSurface.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.work_outline, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            '$label × $count',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}


class _BookingToggleCard extends StatelessWidget {
  final String partnerId;
  final bool accepting;
  final VoidCallback onRefresh;

  const _BookingToggleCard({
    required this.partnerId,
    required this.accepting,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Accetto prenotazioni',
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          accepting
              ? 'Il locale è prenotabile dagli utenti.'
              : 'Il locale resta visibile ma non prenotabile.',
          style: tt.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.7),
          ),
        ),
        value: accepting,
        onChanged: (v) async {
          try {
            final repo = PartnerRepo(Supabase.instance.client);
            await repo.setAcceptingBookings(
              partnerId: partnerId,
              accepting: v,
            );

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  v ? 'Prenotazioni attivate' : 'Prenotazioni sospese',
                ),
              ),
            );

            onRefresh();
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Errore: ${e.toString()}')),
            );
          }
        },
      ),
    );
  }
}
