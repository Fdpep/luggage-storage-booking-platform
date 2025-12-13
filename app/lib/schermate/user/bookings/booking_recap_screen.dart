import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/schermate/partner/user_view/partner_detail_screen.dart';
import 'package:BagDrop/theme/app_theme.dart';

class BookingRecapScreen extends StatelessWidget {
  final Partner partner;
  final PartnerBooking booking;

  const BookingRecapScreen({
    super.key,
    required this.partner,
    required this.booking,
  });

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final totalBags = booking.totalBags;
    final dropoff = booking.plannedDropoffLocal;
    final pickup = booking.plannedPickupLocal;

    // Calcolo durata + prezzo
    BagDropDuration? duration;
    double? totalPrice;
    String durationLabel = '';

    if (pickup.isAfter(dropoff)) {
      duration = BagDropPricing.inferDuration(start: dropoff, end: pickup);
      totalPrice = BagDropPricing.totalFor(
        duration: duration,
        bagsS: booking.bagsS,
        bagsM: booking.bagsM,
        bagsL: booking.bagsL,
      );

      switch (duration) {
        case BagDropDuration.threeHours:
          durationLabel = '3 ore';
          break;
        case BagDropDuration.oneDay:
          durationLabel = '1 giorno';
          break;
        case BagDropDuration.oneAndHalfDay:
          durationLabel = '1,5 giorni';
          break;
        case BagDropDuration.twoDays:
          durationLabel = '2 giorni';
          break;
        case BagDropDuration.threeDays:
          durationLabel = '3 giorni';
          break;
      }
    }

    String statusText;
    Color statusColor;
    switch (booking.status.toLowerCase()) {
      case 'pending':
        statusText = 'In attesa';
        statusColor = Colors.orange;
        break;
      case 'cancelled':
      case 'canceled':
        statusText = 'Annullata';
        statusColor = Colors.red;
        break;
      case 'completed':
        statusText = 'Completata';
        statusColor = Colors.blue;
        break;
      default:
        statusText = 'Confermata';
        statusColor = Colors.green;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const _LogoTitle(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Riepilogo prenotazione',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Controlla i dettagli della tua prenotazione prima di recarti in negozio.',
            style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),

          // Card partner + stato + date
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Partner + stato chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partner.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            if (partner.address != null &&
                                partner.address!.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: cs.onSurface.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      partner.address!,
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Date e orari con icone
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconLabelRow(
                        icon: Icons.login,
                        label: 'Consegna prevista',
                        value: _formatDateTime(dropoff),
                      ),
                      const SizedBox(height: 4),
                      _IconLabelRow(
                        icon: Icons.logout,
                        label: 'Ritiro previsto',
                        value: _formatDateTime(pickup),
                      ),
                      const SizedBox(height: 4),
                      _IconLabelRow(
                        icon: Icons.schedule_outlined,
                        label: 'Prenotazione creata il',
                        value: _formatDateTime(booking.createdAt),
                        labelStyle: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                        valueStyle: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PartnerDetailScreen(partner: partner),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 18,
                      ),
                      label: const Text('Dettagli locale'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Dati contatto
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dati di contatto',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow('Nome', '${booking.firstName} ${booking.lastName}'),
                  _InfoRow('Email', booking.email),
                  if (booking.phone.isNotEmpty)
                    _InfoRow('Telefono', booking.phone),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Bagagli
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bagagli',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow('Totale bagagli', '$totalBags'),
                  _InfoRow('Small (S)', '${booking.bagsS}'),
                  _InfoRow('Medium (M)', '${booking.bagsM}'),
                  _InfoRow('Large (L)', '${booking.bagsL}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Prezzo totale
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Prezzo totale',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (totalPrice == null)
                    Text(
                      'Durata non valida: controlla che data e orario di ritiro siano successivi alla consegna.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    )
                  else ...[
                    Text(
                      BagDropPricing.formatEuro(totalPrice),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (durationLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Durata tariffaria: $durationLabel',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Note
          if (booking.notes != null && booking.notes!.trim().isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      booking.notes!.trim(),
                      style: TextStyle(color: cs.onSurface.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
            ),
        ],
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconLabelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const _IconLabelRow({
    required this.icon,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defaultLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: cs.onSurface.withOpacity(0.85),
    );
    final defaultValueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.9));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle ?? defaultLabelStyle),
              const SizedBox(height: 2),
              Text(value, style: valueStyle ?? defaultValueStyle),
            ],
          ),
        ),
      ],
    );
  }
}
