import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/theme/app_theme.dart';

class BagDropPricingScreen extends StatelessWidget {
  const BagDropPricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget section({
      required String title,
      required IconData icon,
      required List<Widget> children,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(children: children),
          ),
        ],
      );
    }

    Widget cell({required String title, String? subtitle, Widget? trailing}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
      );
    }

    Widget divider() =>
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35));

    Widget priceRow(String label, double price) {
      return cell(
        title: label,
        trailing: Text(
          BagDropPricing.formatEuro(price),
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      );
    }

    Widget pricingSize({
      required String title,
      required String subtitle,
      required List<Widget> rows,
    }) {
      return section(
        title: title,
        icon: Icons.local_offer_outlined,
        children: [
          cell(
            title: title,
            subtitle: subtitle,
            trailing: Icon(
              Icons.check_circle_outline,
              color: cs.primary,
              size: 18,
            ),
          ),
          divider(),
          ..._withDividers(rows, divider),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Tariffe standard BagDrop',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Queste tariffe sono uguali per tutte le attività partner.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.75),
            ),
          ),

          const SizedBox(height: 16),

          section(
            title: 'Come funzionano le fasce',
            icon: Icons.layers_outlined,
            children: [
              cell(title: '• 3 ore'),
              divider(),
              cell(
                title: '• Tutto il giorno',
                subtitle: 'Fino alla chiusura del locale',
              ),
              divider(),
              cell(
                title: '• 1 giorno e mezzo',
                subtitle: 'Fino alle 13:00 del giorno dopo',
              ),
              divider(),
              cell(title: '• 2 giorni, 3 giorni, …'),
            ],
          ),

          const SizedBox(height: 14),

          section(
            title: 'Ritiro scelto vs scadenza fascia',
            icon: Icons.compare_arrows_rounded,
            children: [
              cell(
                title: 'Ritiro scelto',
                subtitle:
                    'Puoi scegliere un orario anche prima della scadenza della fascia.',
              ),
              divider(),
              cell(
                title: 'Scadenza fascia',
                subtitle:
                    'Prezzo e validità seguono la scadenza della fascia in cui ricade il ritiro scelto.',
              ),
              divider(),
              cell(
                title: 'Esempio',
                subtitle:
                    'Consegni 14:00 e scegli ritiro 16:00 → fascia “3 ore” → scadenza fascia 17:00.',
              ),
            ],
          ),

          const SizedBox(height: 14),

          section(
            title: 'Oltre 3 giorni',
            icon: Icons.add_circle_outline,
            children: [
              cell(
                title: 'Regola',
                subtitle:
                    'Dal 4° giorno in poi: +2,00 € per bagaglio per ogni giorno extra (qualsiasi taglia).',
              ),
              divider(),
              cell(
                title: 'Esempio',
                subtitle:
                    '2 bagagli per 6 giorni → prezzo(3 giorni) + 3 giorni extra × 2€ × 2 bagagli.',
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'Prezzi per taglia',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          pricingSize(
            title: 'Small (S)',
            subtitle: 'Zaini / borse piccole',
            rows: [
              priceRow('3 ore', BagDropPricing.s3h),
              priceRow('1 giorno', BagDropPricing.s1d),
              priceRow('1,5 giorni', BagDropPricing.s1_5d),
              priceRow('2 giorni', BagDropPricing.s2d),
              priceRow('3 giorni', BagDropPricing.s3d),
            ],
          ),

          const SizedBox(height: 12),

          pricingSize(
            title: 'Medium (M)',
            subtitle: 'Trolley / valigie medie',
            rows: [
              priceRow('3 ore', BagDropPricing.m3h),
              priceRow('1 giorno', BagDropPricing.m1d),
              priceRow('1,5 giorni', BagDropPricing.m1_5d),
              priceRow('2 giorni', BagDropPricing.m2d),
              priceRow('3 giorni', BagDropPricing.m3d),
            ],
          ),

          const SizedBox(height: 12),

          pricingSize(
            title: 'Large (L)',
            subtitle: 'Valigie grandi',
            rows: [
              priceRow('3 ore', BagDropPricing.l3h),
              priceRow('1 giorno', BagDropPricing.l1d),
              priceRow('1,5 giorni', BagDropPricing.l1_5d),
              priceRow('2 giorni', BagDropPricing.l2d),
              priceRow('3 giorni', BagDropPricing.l3d),
            ],
          ),

          const SizedBox(height: 16),

          section(
            title: 'Supplemento (estensione)',
            icon: Icons.warning_amber_rounded,
            children: [
              cell(
                title: 'Come si calcola',
                subtitle:
                    'Paghi sempre e solo la differenza tra la nuova fascia e quella già pagata.',
              ),
              divider(),
              cell(
                title: 'Esempio',
                subtitle:
                    '3 ore → 1 giorno: supplemento = prezzo(1 giorno) − prezzo(3 ore).',
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'Nota: durata tariffaria e scadenza fascia sono calcolate automaticamente in base a consegna e ritiro scelto.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

List<Widget> _withDividers(List<Widget> items, Widget Function() divider) {
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    out.add(items[i]);
    if (i != items.length - 1) out.add(divider());
  }
  return out;
}

/// Titolo “BagDrop” in AppBar con brand:
/// - “Bag” bianco fisso
/// - “Drop” giallo brand
class _LogoTitle extends StatelessWidget {
  const _LogoTitle({this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'BagDrop',
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Bag',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
                color: Colors.white,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: 'Drop',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
                color: AppTheme.brandYellow,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
