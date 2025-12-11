import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/schermate/user/bookings/booking_recap_screen.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';

import 'booking_partner_detail_screen.dart';

class UserBookingsPage extends StatefulWidget {
  const UserBookingsPage({super.key});

  @override
  State<UserBookingsPage> createState() => _UserBookingsPageState();
}

class _UserBookingsPageState extends State<UserBookingsPage> {
  late Future<List<PartnerBooking>> _futureBookings;
  final _bookingRepo = PartnerBookingRepo(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _futureBookings = _bookingRepo.getMyBookings();
  }

  Future<void> _reload() async {
    setState(() {
      _futureBookings = _bookingRepo.getMyBookings();
    });
    await _futureBookings;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<PartnerBooking>>(
      future: _futureBookings,
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Errore
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text(
                    'Impossibile caricare le prenotazioni.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          );
        }

        final bookings = snapshot.data ?? [];

        // Vuoto
        if (bookings.isEmpty) {
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

        // Lista
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Le mie prenotazioni'),
                    SizedBox(height: 8),
                  ],
                );
              }

              final booking = bookings[index - 1];
              return _BookingListItem(booking: booking);
            },
          ),
        );
      },
    );
  }
}

/// Card di lista con partner + stato + data.
/// Cliccando apre la schermata di dettaglio attività + bottoni recap/QR.
class _BookingListItem extends StatefulWidget {
  final PartnerBooking booking;

  const _BookingListItem({required this.booking});

  @override
  State<_BookingListItem> createState() => _BookingListItemState();
}

class _BookingListItemState extends State<_BookingListItem> {
  final _partnerRepo = PartnerRepo(Supabase.instance.client);
  late Future<Partner?> _futurePartner;

  @override
  void initState() {
    super.initState();
    _futurePartner = _partnerRepo.getPartnerById(widget.booking.partnerId);
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'confirmed':
        return Colors.green.shade600;
      case 'pending':
        return cs.primary;
      case 'cancelled':
        return Colors.red.shade600;
      default:
        return cs.onSurface.withOpacity(0.7);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Confermata';
      case 'pending':
        return 'In attesa';
      case 'cancelled':
        return 'Annullata';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final booking = widget.booking;
    final dropoff = booking.plannedDropoffLocal;

    return FutureBuilder<Partner?>(
      future: _futurePartner,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final partner = snapshot.data;
        final hasError = snapshot.hasError;

        final partnerName = isLoading
            ? 'Caricamento attività...'
            : (partner?.name ?? 'Attività non disponibile');

        final status = booking.status.toLowerCase();
        final isConfirmed = status == 'confirmed';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Riga superiore: stato + date
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(context, booking.status)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(booking.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(context, booking.status),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDate(dropoff),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'creata il ${_formatDate(booking.createdAt)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Nome partner
                Text(
                  partnerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Errore nel caricamento dell’attività.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ),

                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.luggage_outlined,
                      size: 16,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bagagli: ${booking.bagsS + booking.bagsM + booking.bagsL}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Bottoni: Riepilogo + QR code
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: partner == null
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => BookingRecapScreen(
                                      partner: partner,
                                      booking: booking,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Riepilogo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (partner == null || !isConfirmed)
                            ? null
                            : () {
                                // Placeholder: QR code verrà implementato in seguito
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'QR code in arrivo in uno step successivo.',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('QR code'),
                      ),
                    ),
                  ],
                ),

                if (!isConfirmed) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Il QR code sarà disponibile quando la prenotazione sarà confermata.',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

}

/// Versione light di SectionTitle / HintCard per riusare lo stile in questa pagina.
/// Puoi anche importarli da home_shell.dart se preferisci.

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}
