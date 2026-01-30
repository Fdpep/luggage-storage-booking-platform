import 'package:flutter/material.dart';
import 'package:BagDrop/models/partner_booking.dart';
import 'package:BagDrop/config/bagdrop_pricing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/theme/app_theme.dart';

class PartnerBookingDetailScreen extends StatefulWidget {
  final PartnerBooking booking;

  const PartnerBookingDetailScreen({super.key, required this.booking});

  @override
  State<PartnerBookingDetailScreen> createState() =>
      _PartnerBookingDetailScreenState();
}

class _PartnerBookingDetailScreenState
    extends State<PartnerBookingDetailScreen> {
  PartnerBooking get booking => widget.booking;
  bool _rejecting = false;

  String _formatDateTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm  $hh:$min';
  }

  bool get _canReject {
    final kind = _StatusUI.from(booking.uiStatus).kind;
    // ✅ rifiutabile SOLO prima del check-in
    return kind == _StatusKind.pending || kind == _StatusKind.confirmed;
  }

  Future<String?> _askRejectReason(BuildContext context) {
    const presets = [
      'Bagaglio non conforme (taglia diversa)',
      'Cliente non si è presentato',
      'Capienza insufficiente',
      'Orario non rispettato',
      'Altro',
    ];

    final ctrl = TextEditingController();
    final focus = FocusNode();
    String? selected;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setM) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;

            final canConfirm = ctrl.text.trim().isNotEmpty; // ✅ OBBLIGATORIO

            void selectPreset(String p) {
              setM(() {
                selected = (selected == p) ? null : p;
                if (selected == null) return;

                if (selected == 'Altro') {
                  ctrl.text = '';
                } else {
                  ctrl.text = selected!;
                }
                ctrl.selection = TextSelection.collapsed(
                  offset: ctrl.text.length,
                );
              });
              FocusScope.of(ctx).requestFocus(focus);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rifiuta prenotazione',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seleziona una motivazione o scrivila. Il campo è obbligatorio.',
                    style: TextStyle(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final isSel = selected == p;
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSel,
                        onSelected: (_) => selectPreset(p),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    focusNode: focus,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Motivazione *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) => setM(() {}),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Annulla'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: !canConfirm
                              ? null
                              : () => Navigator.pop(ctx, ctrl.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Conferma rifiuto'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withOpacity(0.18)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Il rifiuto è consentito solo prima del check-in. '
                            'Se l’utente ha già pagato, verrà avviato il rimborso automatico.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _rejectBooking() async {
    if (!_canReject || _rejecting) return;

    final reason = await _askRejectReason(context);
    if (!mounted || reason == null || reason.trim().isEmpty) return;

    setState(() => _rejecting = true);

    try {
      final repo = PartnerBookingRepo(Supabase.instance.client);
      await repo.rejectBooking(bookingId: booking.id, reason: reason.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prenotazione rifiutata')));
      Navigator.pop(context, true); // ✅ segnala alla lista di refreshare
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  _StatusUI _statusUi(String status) => _StatusUI.from(status);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final totalBags = (booking.bagsS) + (booking.bagsM) + (booking.bagsL);

    final dropoff = booking.plannedDropoffAtLocal;
    final pickup = booking.plannedPickupAtLocal;

    final dropoffStr = _formatDateTime(dropoff);
    final pickupStr = _formatDateTime(pickup);

    final statusUi = _StatusUI.from(booking.uiStatus);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Dettaglio prenotazione',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          // ✅ HERO HEADER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.brandPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${booking.firstName} ${booking.lastName}'.trim(),
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _StatusPill(ui: statusUi),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Consegna: $dropoffStr',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.history_toggle_off,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ritiro: $pickupStr',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Motivo rifiuto (callout)
          if (statusUi.kind == _StatusKind.rejected &&
              (booking.rejectReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _Callout(
              icon: Icons.info_outline,
              title: 'Motivazione rifiuto',
              text: booking.rejectReason!.trim(),
              tone: _CalloutTone.danger,
            ),
          ],

          const SizedBox(height: 14),

          // Contatto
          _SectionCard(
            title: 'Contatto',
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.firstName} ${booking.lastName}'.trim(),
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (booking.phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoLine(icon: Icons.phone_outlined, text: booking.phone!),
                ],
                if (booking.email.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoLine(icon: Icons.email_outlined, text: booking.email!),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Bagagli
          _SectionCard(
            title: 'Bagagli',
            icon: Icons.inventory_2_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Totale: $totalBags',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (booking.bagsS > 0)
                      _MiniPill(label: 'S × ${booking.bagsS}'),
                    if (booking.bagsM > 0)
                      _MiniPill(label: 'M × ${booking.bagsM}'),
                    if (booking.bagsL > 0)
                      _MiniPill(label: 'L × ${booking.bagsL}'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Note cliente
          if ((booking.notes ?? '').trim().isNotEmpty) ...[
            _Callout(
              icon: Icons.sticky_note_2_outlined,
              title: 'Note cliente',
              text: booking.notes!.trim(),
              tone: _CalloutTone.neutral,
            ),
            const SizedBox(height: 12),
          ],

          // Prezzo totale
          _SectionCard(
            title: 'Prezzo totale',
            icon: Icons.euro,
            child: Builder(
              builder: (context) {
                final start = dropoff;
                final end = booking.plannedPickupLocal;

                if (!end.isAfter(start)) {
                  return Text(
                    'Durata non disponibile: controlla che data/ora di ritiro siano impostate.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  );
                }

                final duration = BagDropPricing.inferDuration(
                  start: start,
                  end: end,
                );
                final total = BagDropPricing.totalFor(
                  duration: duration,
                  bagsS: booking.bagsS,
                  bagsM: booking.bagsM,
                  bagsL: booking.bagsL,
                );

                String durationLabel;
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

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      BagDropPricing.formatEuro(total),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Durata tariffaria: $durationLabel',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _canReject
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _rejecting ? null : _rejectBooking,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.block),
                    label: Text(
                      _rejecting ? 'Rifiuto…' : 'Rifiuta prenotazione',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandYellow,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

enum _StatusKind { pending, confirmed, inStore, rejected, cancelled, completed }

class _StatusUI {
  final _StatusKind kind;
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatusUI({
    required this.kind,
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  static _StatusUI from(String status) {
    final st = status.trim().toLowerCase();

    if (st == 'pending') {
      return _StatusUI(
        kind: _StatusKind.pending,
        label: 'In attesa',
        bg: AppTheme.brandYellow.withOpacity(0.20),
        fg: Colors.black87,
        icon: Icons.hourglass_bottom,
      );
    }

    if (st == 'in_store') {
      return _StatusUI(
        kind: _StatusKind.inStore,
        label: 'In deposito',
        bg: Colors.blue.withOpacity(0.12),
        fg: Colors.blue.shade800,
        icon: Icons.lock_clock_outlined,
      );
    }

    // ✅ rifiutata lato partner
    if (st == 'rejected' || st == 'cancelled_by_partner') {
      return _StatusUI(
        kind: _StatusKind.rejected,
        label: 'Rifiutata',
        bg: Colors.red.withOpacity(0.12),
        fg: Colors.red.shade800,
        icon: Icons.block,
      );
    }

    if (st == 'completed') {
      return _StatusUI(
        kind: _StatusKind.completed,
        label: 'Completata',
        bg: Colors.blue.withOpacity(0.12),
        fg: Colors.blue.shade800,
        icon: Icons.check_circle_outline,
      );
    }

    if (st == 'cancelled' ||
        st == 'canceled' ||
        st == 'cancelled_by_user' ||
        st == 'expired') {
      return _StatusUI(
        kind: _StatusKind.cancelled,
        label: 'Annullata',
        bg: Colors.grey.withOpacity(0.14),
        fg: Colors.grey.shade800,
        icon: Icons.cancel_outlined,
      );
    }

    // default: confirmed
    return _StatusUI(
      kind: _StatusKind.confirmed,
      label: 'Confermata',
      bg: AppTheme.brandPurple.withOpacity(0.14),
      fg: AppTheme.brandPurple,
      icon: Icons.verified_outlined,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _StatusUI ui;
  const _StatusPill({required this.ui});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: ui.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ui.icon, size: 16, color: ui.fg),
          const SizedBox(width: 6),
          Text(
            ui.label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: ui.fg,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.65)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  const _MiniPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

enum _CalloutTone { neutral, danger }

class _Callout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final _CalloutTone tone;

  const _Callout({
    required this.icon,
    required this.title,
    required this.text,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = tone == _CalloutTone.danger
        ? Colors.red.withOpacity(0.08)
        : cs.surfaceContainerHighest.withOpacity(0.6);

    final Color border = tone == _CalloutTone.danger
        ? Colors.red.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.35);

    final Color fg = tone == _CalloutTone.danger
        ? Colors.red.shade800
        : cs.onSurface.withOpacity(0.85);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900, color: fg),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
