import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';

/// Pagina "Prenotazioni" dentro la PartnerShell.
/// Mostra tutte le prenotazioni ricevute dal locale.
class PrenotazioniPage extends StatefulWidget {
  final Partner? partner;

  const PrenotazioniPage({
    super.key,
    required this.partner,
  });

  @override
  State<PrenotazioniPage> createState() => _PrenotazioniPageState();
}

class _PrenotazioniPageState extends State<PrenotazioniPage> {
  bool _loading = true;
  String? _error;
  List<PartnerBooking> _bookings = [];

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    if (widget.partner == null) {
      setState(() {
        _loading = false;
        _error =
            'Nessuna attività associata a questo account.\nCompleta prima la registrazione del locale.';
        _bookings = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final items = await repo.getBookingsForPartner(widget.partner!.id);

      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Errore _loadBookings PrenotazioniPage: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore durante il caricamento delle prenotazioni.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prenotazioni'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_bookings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Non hai ancora ricevuto prenotazioni.\n'
            'Quando un utente prenota il tuo locale, vedrai qui i dettagli.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final b = _bookings[index];
        return _BookingCard(booking: b);
      },
    );
  }
}

/// Card singola prenotazione.
class _BookingCard extends StatelessWidget {
  final PartnerBooking booking;

  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final totalBags = (booking.bagsS ?? 0) +
        (booking.bagsM ?? 0) +
        (booking.bagsL ?? 0);

    // Data/ora di CONSEGNA prevista (usiamo i nuovi campi)
    final d = booking.plannedDropoffLocal;
    final createdAtStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';


    final status = (booking.status ?? 'confirmed').toLowerCase();
    Color chipColor;
    String statusLabel;
    switch (status) {
      case 'cancelled':
      case 'canceled':
        chipColor = Colors.red.withOpacity(0.1);
        statusLabel = 'Annullata';
        break;
      case 'pending':
        chipColor = Colors.orange.withOpacity(0.1);
        statusLabel = 'In attesa';
        break;
      default:
        chipColor = Colors.green.withOpacity(0.1);
        statusLabel = 'Confermata';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riga superiore: nome + status chip + data
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${booking.firstName ?? ''} ${booking.lastName ?? ''}'
                        .trim(),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (createdAtStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Consegna: $createdAtStr',
                    style: tt.bodySmall?.copyWith(
                      color: tt.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Contatti
            if ((booking.phone ?? '').isNotEmpty ||
                (booking.email ?? '').isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      booking.phone ?? '',
                      style: tt.bodySmall,
                    ),
                  ),
                ],
              ),
              if ((booking.email ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        booking.email ?? '',
                        style: tt.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],

            // Bagagli
            Text(
              'Bagagli: $totalBags',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                if ((booking.bagsS ?? 0) > 0)
                  _ChipMini(
                    label: 'S × ${booking.bagsS}',
                    color: cs.primary.withOpacity(0.1),
                  ),
                if ((booking.bagsM ?? 0) > 0)
                  _ChipMini(
                    label: 'M × ${booking.bagsM}',
                    color: cs.primary.withOpacity(0.1),
                  ),
                if ((booking.bagsL ?? 0) > 0)
                  _ChipMini(
                    label: 'L × ${booking.bagsL}',
                    color: cs.primary.withOpacity(0.1),
                  ),
              ],
            ),

            // Note
            if ((booking.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note:',
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                booking.notes!.trim(),
                style: tt.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipMini extends StatelessWidget {
  final String label;
  final Color color;

  const _ChipMini({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: tt.labelSmall,
      ),
    );
  }
}
