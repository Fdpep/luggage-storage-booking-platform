import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/schermate/user/bookings/booking_recap_screen.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';
import 'package:BagDrop/schermate/user/bookings/booking_qr_screen.dart';
import 'package:BagDrop/schermate/user/bookings/booking_final_recap_screen.dart';

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

  String _formatCountdown(Duration diff) {
    final isLate = diff.isNegative;
    final d = diff.abs();
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);

    if (h > 0) {
      return isLate ? 'In ritardo di ${h}h ${m}m' : 'Manca ${h}h ${m}m';
    }
    final mins = d.inMinutes;
    return isLate ? 'In ritardo di ${mins} min' : 'Manca ${mins} min';
  }

  Widget _buildInStoreReminder(
    BuildContext context, {
    required DateTime dropoff,
    required DateTime pickup,
  }) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final diff = pickup.difference(now);
    final isLate = diff.isNegative;

    // progress: da dropoff -> pickup
    final totalSec = pickup.difference(dropoff).inSeconds;
    double? progress;
    if (totalSec > 0) {
      final elapsedSec = now.difference(dropoff).inSeconds;
      progress = (elapsedSec / totalSec).clamp(0.0, 1.0);
    }

    final accent = isLate ? Colors.red.shade600 : Colors.blue.shade600;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ritiro previsto',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatCountdown(diff),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(pickup),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withOpacity(0.9),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: cs.onSurface.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            isLate
                ? '⚠️ Hai superato l’orario previsto: potrebbe esserci un sovrapprezzo.'
                : 'Ricorda di fare il check-out entro l’orario previsto.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, String statusRaw) {
    final cs = Theme.of(context).colorScheme;
    final status = statusRaw.toLowerCase();

    switch (status) {
      case 'confirmed':
        return Colors.green.shade600;

      case 'pending':
        return Colors.orange.shade700;

      case 'in_store':
        return Colors.blue.shade600;

      case 'completed':
        return Colors.indigo.shade600;

      case 'cancelled':
      case 'canceled':
        return Colors.red.shade600;

      case 'rejected':
        return Colors.red.shade700;

      default:
        return cs.onSurface.withOpacity(0.7);
    }
  }

  String _statusLabel(String statusRaw) {
    switch (statusRaw.toLowerCase()) {
      case 'confirmed':
        return 'Confermata';
      case 'pending':
        return 'In attesa';
      case 'in_store':
        return 'In deposito';
      case 'completed':
        return 'Completata';
      case 'cancelled':
      case 'canceled':
        return 'Annullata';
      case 'rejected':
        return 'Rifiutata';
      default:
        return statusRaw;
    }
  }

  IconData _statusIcon(String statusRaw) {
    switch (statusRaw.toLowerCase()) {
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'in_store':
        return Icons.lock_clock_outlined;
      case 'completed':
        return Icons.verified_outlined;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_outlined;
      case 'rejected':
        return Icons.block_outlined;
      default:
        return Icons.info_outline;
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
        final isCompleted = status == 'completed';

        // QR: solo quando ha senso (es: confirmed / in_store) e NON completed
        final qrAvailable =
            !isCompleted && (status == 'confirmed' || status == 'in_store');

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
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(
                          context,
                          booking.status,
                        ).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(booking.status),
                            size: 14,
                            color: _statusColor(context, booking.status),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _statusLabel(booking.status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _statusColor(context, booking.status),
                            ),
                          ),
                        ],
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

                if (status == 'in_store') ...[
                  const SizedBox(height: 10),
                  _buildInStoreReminder(
                    context,
                    dropoff: booking.plannedDropoffLocal,
                    pickup: booking.plannedPickupLocal,
                  ),
                ],

                const SizedBox(height: 8),

                // Bottoni: Riepilogo + QR code
                // Bottoni: se completed -> solo riepilogo finale
                if (isCompleted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: partner == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookingFinalRecapScreen(
                                    partner: partner,
                                    booking: booking,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('Riepilogo finale'),
                    ),
                  ),
                ] else ...[
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
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                          ),
                          label: const Text('Riepilogo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (partner == null || !qrAvailable)
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingQrScreen(
                                        bookingId: booking.id,
                                        bookingCode: booking.bookingCode,
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
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}
