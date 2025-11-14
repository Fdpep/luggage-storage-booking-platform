import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner_requests.dart';
import '../../models/partner.dart';

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
      final data = await _supabase
          .from('partner_requests')
          .select(
              'id,user_id,partner_id,status,message,admin_note,created_at,reviewed_at,reviewed_by')
          .eq('status', 'pending')
          .order('created_at');

      final requests = (data as List)
          .map((m) => PartnerRequest.fromMap(m as Map<String, dynamic>))
          .toList();

      final partnerIds = requests.map((r) => r.partnerId).toSet().toList();

      Map<String, Partner> partnersById = {};

      if (partnerIds.isNotEmpty) {
        final partnersData = await _supabase
            .from('partners')
            .select(
                'id,name,address,capacity,price_2h,price_per_day,status,is_active,reject_reason,created_at,updated_at,owner_id,lat,lng,opening_hours')
            .inFilter('id', partnerIds);

        partnersById = {
          for (final m in partnersData as List)
            (m['id'] as String): Partner.fromMap(m as Map<String, dynamic>)
        };
      }

      setState(() {
        _items = requests
            .map(
              (r) => _AdminRequestItem(
                request: r,
                partner: partnersById[r.partnerId],
              ),
            )
            .toList();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin non autenticato')),
        );
        return;
      }

      await _supabase
          .from('partners')
          .update({
            'status': nuovoStatus,
            'is_active': nuovoStatus == 'approved',
            'reject_reason': nuovoStatus == 'rejected' ? adminNote : null,
          })
          .eq('id', req.partnerId);

      await _supabase
          .from('partner_requests')
          .update({
            'status': nuovoStatus,
            'admin_note': adminNote,
            'reviewed_at': DateTime.now().toIso8601String(),
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

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
        child: ListView.builder(
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final r = item.request;
            final p = item.partner;

            final shortId = r.id.substring(0, 8);
            final name = p?.name ?? 'Attività senza nome';
            final address = p?.address ?? 'Indirizzo non specificato';
            final capacity = p?.capacity ?? 0;
            final price2h = p?.price2h?.toStringAsFixed(2) ?? '-';
            final pricePerDay = p?.pricePerDay?.toStringAsFixed(2) ?? '-';

            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text('$name  •  $shortId'),
                subtitle: Text(
                  'Indirizzo: $address\n'
                  'Capacità: $capacity  •  €2h: $price2h  •  €/giorno: $pricePerDay\n'
                  'nota: ${r.message ?? '-'}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Approva',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _decidi(
                        req: r,
                        nuovoStatus: 'approved',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rifiuta',
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () async {
                        final note = await _chiediMotivo(context);
                        if (note == null) return;
                        _decidi(
                          req: r,
                          nuovoStatus: 'rejected',
                          adminNote: note,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

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

class _AdminRequestItem {
  final PartnerRequest request;
  final Partner? partner;

  _AdminRequestItem({
    required this.request,
    required this.partner,
  });
}
