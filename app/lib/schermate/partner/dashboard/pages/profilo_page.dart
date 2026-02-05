import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../models/partner.dart';
import '../../../autenticazione/auth_actions.dart';
import '../../dashboard/edit/partner_edit_screen.dart';
import '../../dashboard/edit/partner_photos_screen.dart';
import '../../user_view/partner_drawer.dart';
import 'package:BagDrop/schermate/partner/user_view/partner_detail_screen.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';

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
          child: Container(height: 1, color: cs.onPrimary.withOpacity(0.12)),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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

          if (partner != null) ...[
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Anteprima scheda',
              subtitle: 'Scheda partner che viene visualizzata nella mappa',
            ),
            const SizedBox(height: 10),

            _PartnerMapCardPreview(
              partner: partner!,
              onOpenDetail: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PartnerDetailScreen(
                      partner: partner!,
                      showBookingCta: false,
                    ),
                  ),
                );
                onPartnerChanged();
              },
            ),
          ],

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
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerPhotosScreen(partner: partner!),
                      ),
                    );
                    onPartnerChanged(); // ✅ così l’anteprima si aggiorna dopo modifiche foto/cover/ordine
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
                textStyle: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
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
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
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

class _PartnerMapCardPreview extends StatelessWidget {
  final Partner partner;

  /// Apri la scheda dettagli (PartnerDetailScreen con showBookingCta:false)
  final VoidCallback onOpenDetail;

  const _PartnerMapCardPreview({
    required this.partner,
    required this.onOpenDetail,
  });

  static const _photoRepo = PartnerPhotoRepo();

  Future<String?> _loadCoverUrl() async {
    final photos = await _photoRepo.fetchPhotosForPartner(partner.id);
    if (photos.isEmpty) return null;
    final cover = photos.where((p) => p.isCover == true).toList();
    return (cover.isNotEmpty ? cover.first : photos.first).url;
  }

  // ---- OPEN NOW helper (supporta weekly_v1 / daily_with_break / legacy) ----
  static const _dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  String _todayKey(DateTime now) => _dayOrder[(now.weekday - 1).clamp(0, 6)];

  int? _parseHmToMin(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  List<Map<String, dynamic>> _todayIntervals(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];

    final dayKey = _todayKey(DateTime.now());
    final type = raw['type'] as String?;

    if (type == 'weekly_v1') {
      final list = raw[dayKey] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    if (type == 'daily_with_break') {
      final o1 = raw['open_1'] as String?;
      final c1 = raw['close_1'] as String?;
      final o2 = raw['open_2'] as String?;
      final c2 = raw['close_2'] as String?;

      final out = <Map<String, dynamic>>[];
      if (o1 != null && c1 != null) out.add({'open': o1, 'close': c1});
      if (o2 != null && c2 != null) out.add({'open': o2, 'close': c2});
      return out;
    }

    // legacy: raw come weekly senza type
    final list = raw[dayKey] as List<dynamic>? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  bool _isOpenNow(Partner p) {
    final intervals = _todayIntervals(p.openingHours);
    if (intervals.isEmpty) return false;

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    for (final i in intervals) {
      final o = (i['open'] ?? '').toString();
      final c = (i['close'] ?? '').toString();
      final oMin = _parseHmToMin(o);
      final cMin = _parseHmToMin(c);
      if (oMin == null || cMin == null) continue;

      // h24 (anche 23:59 -> 00:00, oppure open==close)
      if (oMin == cMin) return true;
      if (o == '23:59' && c == '00:00') return true;

      if (cMin > oMin) {
        if (nowMin >= oMin && nowMin < cMin) return true;
      } else {
        // attraversa mezzanotte
        if (nowMin >= oMin || nowMin < cMin) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final isOpen = _isOpenNow(partner);
    final hasAddress =
        partner.address != null && partner.address!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: InkWell(
        onTap: onOpenDetail, // ✅ tap card apre dettagli
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<String?>(
                    future: _loadCoverUrl(),
                    builder: (context, snap) {
                      final url = snap.data;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 84,
                          height: 84,
                          color: cs.surfaceVariant.withOpacity(0.55),
                          child: (url == null)
                              ? Icon(Icons.photo, color: cs.onSurfaceVariant)
                              : Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.broken_image,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isOpen
                                ? Colors.green.withOpacity(0.15)
                                : Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: (isOpen ? Colors.green : Colors.red)
                                  .withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            isOpen ? 'Aperto ora' : 'Chiuso',
                            style: tt.labelSmall?.copyWith(
                              color: isOpen
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (hasAddress) ...[
                          const SizedBox(height: 8),
                          Text(
                            partner.address!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.70),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onOpenDetail, // ✅ apre dettagli partner
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.arrow_forward_ios, size: 14),
                    label: const Text('Apri scheda'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
