import 'package:flutter/material.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:BagDrop/theme/app_theme.dart';

class BagDropPricingScreen extends StatelessWidget {
  const BagDropPricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: const _LogoTitle(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tariffe standard BagDrop',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Queste tariffe sono uguali per tutte le attività partner.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.75),
            ),
          ),

          const SizedBox(height: 16),

          // =========================
          // COME FUNZIONA (LOGICA)
          // =========================
          _InfoCard(
            title: 'Come funzionano le fasce',
            icon: Icons.layers_outlined,
            children: const [
              _Bullet('3 ore'),
              _Bullet('Tutto il giorno (fino alla chiusura del locale)'),
              _Bullet('1 giorno e mezzo (fino alle 13:00 del giorno dopo)'),
              _Bullet('2 giorni, 3 giorni, …'),
            ],
          ),
          const SizedBox(height: 12),

          _InfoCard(
            title: 'Ritiro scelto vs scadenza fascia',
            icon: Icons.compare_arrows_rounded,
            children: [
              _Bullet(
                'Puoi scegliere un orario per il ritiro anche prima della scadenza della fascia: è il tuo “ritiro scelto”.',
              ),
              _Bullet(
                'Il prezzo e la validità tariffaria seguono comunque le scadenze della fascia orario in cui si colloca il ritiro scelto.',
              ),
              const SizedBox(height: 8),
              _MiniNote(
                text:
                    'Esempio: consegni 14:00 e scegli ritiro 16:00 → ricadi nella fascia “3 ore” → scadenza fascia 17:00.',
              ),
            ],
          ),
          const SizedBox(height: 12),

          _InfoCard(
            title: 'Ritardo, supplemento ed estensione',
            icon: Icons.warning_amber_rounded,
            children: const [
              _Bullet(
                'C’è una tolleranza di 15 minuti dopo la scadenza fascia.',
              ),
              _Bullet(
                'Il ritardo si calcola dalla scadenza fascia (non dal ritiro scelto).',
              ),
              _Bullet(
                'Se superi scadenza fascia + 15 min, puoi pagare un supplemento per estendere la prenotazione.',
              ),
              _Bullet(
                'Il supplemento è la differenza tra la nuova fascia e quella già pagata (upgrade di fascia).',
              ),
              SizedBox(height: 8),
              _MiniNote(
                text:
                    'Esempio: 3 ore = €3, ma ritiri tardi → devi passare a 1 giorno = €5 → supplemento = €2 (5−3). '
                    'Dopo il pagamento la prenotazione viene estesa e torna “in regola”.',
              ),
            ],
          ),

          const SizedBox(height: 20),

          Divider(color: cs.onSurface.withOpacity(0.12)),
          const SizedBox(height: 12),

          // =========================
          // PREZZI
          // =========================
          Text(
            'Prezzi per taglia',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),

          _PricingCard(
            title: 'Small (S)',
            subtitle: 'Zaini / borse piccole',
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
            subtitle: 'Trolley / valigie medie',
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
            subtitle: 'Valigie grandi',
            rows: [
              _PricingRow('3 ore', BagDropPricing.l3h),
              _PricingRow('1 giorno', BagDropPricing.l1d),
              _PricingRow('1,5 giorni', BagDropPricing.l1_5d),
              _PricingRow('2 giorni', BagDropPricing.l2d),
              _PricingRow('3 giorni', BagDropPricing.l3d),
            ],
          ),

          const SizedBox(height: 18),

          _InfoCard(
            title: 'Esempi rapidi (supplemento)',
            icon: Icons.lightbulb_outline,
            children: const [
              _Bullet(
                'Paghi sempre e solo la differenza tra fasce, quando serve estendere.',
              ),
              _Bullet(
                'Puoi estendere più volte se vai di nuovo oltre la scadenza fascia.',
              ),
              SizedBox(height: 8),
              _MiniNote(
                text:
                    '3 ore → 1 giorno: supplemento = prezzo(1 giorno) − prezzo(3 ore)\n'
                    '1 giorno → 1,5 giorni: supplemento = prezzo(1,5) − prezzo(1)\n'
                    '1,5 giorni → 2 giorni: supplemento = prezzo(2) − prezzo(1,5)',
              ),
            ],
          ),

          const SizedBox(height: 18),

          _MiniNote(
            text:
                'Nota: la durata tariffaria e la scadenza fascia sono calcolate automaticamente in base alla consegna e al ritiro scelto.',
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
  final String subtitle;
  final List<_PricingRow> rows;

  const _PricingCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 10),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(r.label)),
                    Text(
                      BagDropPricing.formatEuro(r.price),
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MiniNote extends StatelessWidget {
  final String text;
  const _MiniNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.78)),
      ),
    );
  }
}
