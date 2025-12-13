import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/theme/app_theme.dart';

class BagDropPricingScreen extends StatelessWidget {
  const BagDropPricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

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
            'Tariffe standard BagDrop',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Queste tariffe sono applicate in modo uguale per tutte le attività partner.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 16),

          _PricingCard(
            title: 'Small (S)',
            rows: [
              _PricingRow('3 ore', BagDropPricing.s3h),
              _PricingRow('1 giorno', BagDropPricing.s1d),
              _PricingRow('1,5 giorni', BagDropPricing.s1_5d),
              _PricingRow('2 giorni', BagDropPricing.s2d),
              _PricingRow('3 giorni', BagDropPricing.s3d),
            ],
          ),
          const SizedBox(height: 12),

          _PricingCard(
            title: 'Medium (M)',
            rows: [
              _PricingRow('3 ore', BagDropPricing.m3h),
              _PricingRow('1 giorno', BagDropPricing.m1d),
              _PricingRow('1,5 giorni', BagDropPricing.m1_5d),
              _PricingRow('2 giorni', BagDropPricing.m2d),
              _PricingRow('3 giorni', BagDropPricing.m3d),
            ],
          ),
          const SizedBox(height: 12),

          _PricingCard(
            title: 'Large (L)',
            rows: [
              _PricingRow('3 ore', BagDropPricing.l3h),
              _PricingRow('1 giorno', BagDropPricing.l1d),
              _PricingRow('1,5 giorni', BagDropPricing.l1_5d),
              _PricingRow('2 giorni', BagDropPricing.l2d),
              _PricingRow('3 giorni', BagDropPricing.l3d),
            ],
          ),
          const SizedBox(height: 24),

          Text(
            'Nota: la durata tariffaria viene calcolata automaticamente in base a orario di consegna e ritiro (3h, giornata, 1,5 giorni, 2 giorni ...).',
            style: tt.bodySmall?.copyWith(fontSize: 11),
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

class _PricingRow {
  final String label;
  final double price;

  _PricingRow(this.label, this.price);
}

class _PricingCard extends StatelessWidget {
  final String title;
  final List<_PricingRow> rows;

  const _PricingCard({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.label),
                    Text(
                      BagDropPricing.formatEuro(r.price),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
