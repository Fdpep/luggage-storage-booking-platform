import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/supabase/partner_repo.dart';
import '../../../../models/partner.dart';
import '../../../autenticazione/auth_actions.dart';
import '../../dashboard/edit/partner_edit_screen.dart';
import '../../dashboard/edit/partner_photos_screen.dart';
import '../../user_view/partner_drawer.dart';

class ProfiloPage extends StatelessWidget {
  final Partner? partner;
  final VoidCallback onPartnerChanged;

  const ProfiloPage({
    super.key,
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Scaffold(
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        centerTitle: false, // ✅ titolo a sinistra
        title: const Text('Profilo partner'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          110,
        ), // spazio per logout in basso
        children: [
          _SectionTitle(title: 'Account', subtitle: 'Informazioni di accesso'),
          const SizedBox(height: 10),
          _Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: const Icon(Icons.person_outline),
              ),
              title: Text(user?.email ?? '-'),
              subtitle: const Text('Account partner BagDrop'),
            ),
          ),
          const SizedBox(height: 18),

          _SectionTitle(
            title: 'Scheda locale',
            subtitle: 'Visibilità e prenotazioni',
          ),
          const SizedBox(height: 10),

          if (partner == null)
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined, color: cs.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nessuna attività registrata.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _PartnerSummaryCard(
              partner: partner!,
              onPartnerChanged: onPartnerChanged,
            ),

          const SizedBox(height: 18),

          _SectionTitle(title: 'Gestione', subtitle: 'Modifica e contenuti'),
          const SizedBox(height: 10),

          _Card(
            child: Column(
              children: [
                if (partner != null) ...[
                  _ActionTile(
                    icon: Icons.photo_library_outlined,
                    title: 'Gestisci foto locale',
                    subtitle: 'Aggiungi, rimuovi o riordina le foto',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PartnerPhotosScreen(partner: partner!),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                ],
                _ActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Modifica scheda locale',
                  subtitle: 'Nome, descrizione, regole, orari e capacità',
                  onTap: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const PartnerEditScreen(),
                      ),
                    );
                    if (ok == true) onPartnerChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      ),

      // ✅ Logout separato, “a parte” in basso
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => AuthActions.confirmAndLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Esci'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PartnerSummaryCard extends StatelessWidget {
  final Partner partner;
  final VoidCallback onPartnerChanged;

  const _PartnerSummaryCard({
    required this.partner,
    required this.onPartnerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: nome + chip stato
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.storefront, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partner.name,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        partner.address ?? '',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  text: partner.isActive ? 'Attivo' : 'Sospeso',
                  filled: partner.isActive,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Dettagli rapidi “più completi”

            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.visibility_outlined,
              label: 'Visibilità su mappa',
              value: partner.isActive ? 'Visibile' : 'Nascosto / sospeso',
            ),

            const SizedBox(height: 10),

            // Switch prenotazioni dentro la card (più chiaro)
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                title: const Text('Accetto prenotazioni'),
                subtitle: const Text(
                  'Se disattivi, il locale resta visibile ma non prenotabile.',
                ),
                value: partner.acceptingBookings,
                onChanged: (v) async {
                  try {
                    final repo = PartnerRepo(Supabase.instance.client);
                    await repo.setAcceptingBookings(
                      partnerId: partner.id,
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

                    onPartnerChanged();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Errore: ${e.toString()}')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: child,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: cs.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final bool filled;

  const _StatusChip({required this.text, required this.filled});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = filled ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = filled ? cs.onPrimaryContainer : cs.onSurface.withOpacity(0.8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6), width: 1),
      ),

      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 12),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
