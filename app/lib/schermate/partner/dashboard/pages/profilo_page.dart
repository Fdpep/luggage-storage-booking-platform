import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Profilo partner',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (tt.titleMedium ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            color: cs.onPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: cs.onPrimary.withOpacity(0.12),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          _SectionTitle(title: 'Account', subtitle: 'Informazioni di accesso'),
          const SizedBox(height: 10),
          iosSection(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: cs.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.email ?? '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Account partner BagDrop',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _SectionTitle(title: 'Gestione', subtitle: 'Modifica e contenuti'),
          const SizedBox(height: 10),

          iosSection(
            context,
            children: [
              if (partner != null) ...[
                iosNavRow(
                  context,
                  icon: Icons.photo_library_outlined,
                  title: 'Gestisci foto locale',
                  subtitle: 'Aggiungi, rimuovi o riordina le foto',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerPhotosScreen(partner: partner!),
                      ),
                    );
                  },
                ),
                thinDivider(context),
              ],
              iosNavRow(
                context,
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
        ],
      ),

      // ✅ Logout separato, “a parte” in basso (logica invariata)
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
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===========================
/// UI helpers (iOS-like sections)
/// ===========================

Widget iosSection(BuildContext context, {required List<Widget> children}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: cs.surfaceVariant.withOpacity(0.25),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

Widget thinDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 1,
    color: cs.outlineVariant.withOpacity(0.7),
  );
}

/// Row stile “Settings iOS”
Widget iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment:
            subtitle == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.35)),
        ],
      ),
    ),
  );
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

    return iosSection(
      context,
      children: [
        Padding(
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
                            fontWeight: FontWeight.w900,
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
              _InfoRow(
                icon: Icons.visibility_outlined,
                label: 'Visibilità su mappa',
                value: partner.isActive ? 'Visibile' : 'Nascosto / sospeso',
              ),
            ],
          ),
        ),
      ],
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
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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

class _StatusChip extends StatelessWidget {
  final String text;
  final bool filled;

  const _StatusChip({required this.text, required this.filled});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
