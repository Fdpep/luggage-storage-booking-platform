import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner_requests.dart';
import '../../models/partner.dart';

/// Schermata principale con le richieste partner in attesa di revisione.
class AdminPartnerRequestsScreen extends StatefulWidget {
  const AdminPartnerRequestsScreen({super.key});

  @override
  State<AdminPartnerRequestsScreen> createState() =>
      _AdminPartnerRequestsScreenState();
}

class _AdminPartnerRequestsScreenState
    extends State<AdminPartnerRequestsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;

  List<_AdminRequestItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data =
          await _supabase
                  .from('partner_requests')
                  .select(
                    'id,user_id,partner_id,status,message,admin_note,created_at,reviewed_at,reviewed_by',
                  )
                  .eq('status', 'pending')
                  .order('created_at')
              as List<dynamic>;

      final requests = data
          .map((m) => PartnerRequest.fromMap(m as Map<String, dynamic>))
          .toList(growable: false);

      final partnerIds = requests.map((r) => r.partnerId).toSet().toList();

      Map<String, Partner> partnersById = {};

      if (partnerIds.isNotEmpty) {
        final partnersData =
            await _supabase
                    .from('partners')
                    .select(
                      'id,name,address,capacity,price_2h,price_per_day,status,is_active,reject_reason,created_at,updated_at,owner_id,lat,lng,opening_hours',
                    )
                    .inFilter('id', partnerIds)
                as List<dynamic>;

        partnersById = {
          for (final raw in partnersData)
            (raw as Map<String, dynamic>)['id'] as String: Partner.fromMap(raw),
        };
      }

      if (!mounted) return;
      setState(() {
        _items = requests
            .map(
              (r) => _AdminRequestItem(
                request: r,
                partner: partnersById[r.partnerId],
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Errore caricando richieste: $e';
        _loading = false;
      });
    }
  }

  Future<void> _decidi({
    required PartnerRequest req,
    required String nuovoStatus,
    String? adminNote,
  }) async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Admin non autenticato')));
        return;
      }

      final nowIso = DateTime.now().toIso8601String();

      // Aggiorno stato partner
      await _supabase
          .from('partners')
          .update({
            'status': nuovoStatus,
            'is_active': nuovoStatus == 'approved',
            'reject_reason': nuovoStatus == 'rejected' ? adminNote : null,
          })
          .eq('id', req.partnerId);

      // Aggiorno richiesta
      await _supabase
          .from('partner_requests')
          .update({
            'status': nuovoStatus,
            'admin_note': adminNote,
            'reviewed_at': nowIso,
            'reviewed_by': adminId,
          })
          .eq('id', req.id);

      await _loadRequests();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Richiesta ${nuovoStatus == 'approved' ? 'approvata' : 'rifiutata'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nell’aggiornare richiesta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Richieste partner'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Richieste partner in attesa'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.inbox_outlined, size: 48, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(
                    'Nessuna richiesta in attesa',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Quando un nuovo locale invierà la domanda per diventare partner, lo vedrai qui.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final r = item.request;
                  final p = item.partner;

                  final shortId = r.id.substring(0, 8);
                  final name = p?.name ?? 'Attività senza nome';
                  final address = p?.address ?? 'Indirizzo non specificato';
                  final capacity = p?.capacity ?? 0;

                  return _AdminRequestCard(
                    shortId: shortId,
                    name: name,
                    address: address,
                    capacity: capacity,
                    note: r.message,
                    createdAt: r.createdAt,
                    onApprove: () => _decidi(req: r, nuovoStatus: 'approved'),
                    onReject: () async {
                      final note = await _chiediMotivo(context);
                      if (note == null) return;
                      await _decidi(
                        req: r,
                        nuovoStatus: 'rejected',
                        adminNote: note,
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  /// Dialog che chiede all'admin il motivo del rifiuto.
  Future<String?> _chiediMotivo(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo del rifiuto'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motivazione da inviare al partner',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }
}

/// Item aggregato: richiesta + eventuale partner associato.
class _AdminRequestItem {
  final PartnerRequest request;
  final Partner? partner;

  _AdminRequestItem({required this.request, required this.partner});
}

/// Card singola per una richiesta partner.
class _AdminRequestCard extends StatelessWidget {
  final String shortId;
  final String name;
  final String address;
  final int capacity;

  final String? note;
  final DateTime? createdAt;
  final VoidCallback onApprove;
  final Future<void> Function() onReject;

  const _AdminRequestCard({
    Key? key,
    required this.shortId,
    required this.name,
    required this.address,
    required this.capacity,
    required this.note,
    required this.createdAt,
    required this.onApprove,
    required this.onReject,
  }) : super(key: key);

  String _formatCreatedAt() {
    if (createdAt == null) return '';
    final d = createdAt!;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final createdStr = _formatCreatedAt();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riga superiore: icona + nome + id + badge "In attesa"
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primary.withOpacity(0.08),
                  child: Icon(Icons.storefront_outlined, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Richiesta #$shortId',
                        style: textTheme.bodySmall?.copyWith(
                          color: textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'In attesa',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Indirizzo
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 4),
                Expanded(child: Text(address, style: textTheme.bodySmall)),
              ],
            ),

            const SizedBox(height: 6),

            // Capacità + info tariffe
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Capacità: $capacity', style: textTheme.bodySmall),
                Text(
                  'Tariffe: listino BagDrop',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            if ((note ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Nota del partner:',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(note!, style: textTheme.bodySmall),
            ],

            const SizedBox(height: 8),

            if (createdStr.isNotEmpty)
              Text(
                'Inviata il $createdStr',
                style: textTheme.bodySmall?.copyWith(
                  color: textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),

            const SizedBox(height: 12),

            // Bottoni Approva / Rifiuta
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Approva'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      onReject();
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Rifiuta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
