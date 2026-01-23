import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/partner_booking.dart';

class BookingQrScreen extends StatefulWidget {
  final String bookingId;
  final String bookingCode;

  const BookingQrScreen({
    super.key,
    required this.bookingId,
    required this.bookingCode,
  });

  @override
  State<BookingQrScreen> createState() => _BookingQrScreenState();
}

class _BookingQrScreenState extends State<BookingQrScreen> {
  late final Stream<PartnerBooking?> _bookingStream;

  bool _paying = false;

  static const Duration _tolerance = Duration(minutes: 15);

  Timer? _ticker;

  // quote supplemento (Step 2: calcolo server-side)
  bool _quoteLoading = false;
  int? _quoteCents;
  String? _quoteMessage; // testo “pulito” (no erroracci)

  // per snack “una volta sola”
  bool _notifiedCheckin = false;
  bool _notifiedCheckout = false;

  String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  String _euro(int cents) {
    final s = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '€ $s';
  }

  @override
  void initState() {
    super.initState();

    final sb = Supabase.instance.client;

    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });

    _bookingStream = sb
        .from('partner_bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return PartnerBooking.fromMap(rows.first);
        });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _maybeNotify(PartnerBooking b) {
    // check-in
    if (!_notifiedCheckin && b.dropoffEffectiveAt != null) {
      _notifiedCheckin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _miniDialog(
          icon: Icons.check_circle_outline,
          title: 'Check-in eseguito',
          subtitle:
              'Consegna registrata alle ${_fmt(b.effectiveDropoffAtLocal!)}.',
        );
      });
    }

    // check-out
    if (!_notifiedCheckout && b.pickupEffectiveAt != null) {
      _notifiedCheckout = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _miniDialog(
          icon: Icons.verified_outlined,
          title: 'Check-out eseguito',
          subtitle:
              'Ritiro registrato alle ${_fmt(b.effectivePickupAtLocal!)}.',
        );

        // per ora chiudiamo la schermata (poi decidiamo recap)
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.bookingCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Codice copiato')));
  }

  bool _isLateOverTolerance(PartnerBooking b) {
    // Mostro supplemento solo se ha già fatto check-in e non ha ancora fatto check-out
    if (b.dropoffEffectiveAt == null) return false;
    if (b.pickupEffectiveAt != null) return false;

    final now = DateTime.now();
    final pickup = b.plannedPickupAtLocal;
    final deadline = pickup.add(_tolerance);

    return now.isAfter(deadline);
  }

  bool _isInTolerance(PartnerBooking b) {
    if (b.dropoffEffectiveAt == null) return false;
    if (b.pickupEffectiveAt != null) return false;

    final now = DateTime.now();
    final pickup = b.plannedPickupAtLocal;
    final deadline = pickup.add(_tolerance);

    return now.isAfter(pickup) && now.isBefore(deadline);
  }

  Future<void> _payLateFeeMock() async {
    if (_paying) return;

    setState(() => _paying = true);

    try {
      dynamic res;

      // STEP 2: quando la mettiamo su Supabase, questa farà:
      // - calcolo differenza tariffe
      // - update end_time/end_date (o pickup) per estendere fino a chiusura
      // - marca late fee paid
      try {
        res = await Supabase.instance.client.rpc(
          'pay_late_fee_and_extend',
          params: {'p_booking_id': widget.bookingId},
        );
      } catch (_) {
        // fallback compatibilità col tuo attuale backend
        res = await Supabase.instance.client.rpc(
          'pay_late_fee',
          params: {'p_booking_id': widget.bookingId},
        );
      }

      final ok = (res is Map && res['ok'] == true);
      final msg =
          (res is Map ? (res['message']?.toString()) : null) ??
          (ok ? 'Pagamento completato' : 'Pagamento non riuscito');

      if (!mounted) return;

      // reset quote: dopo pagamento dovrebbe sparire il blocco “ritardo”
      setState(() {
        _quoteCents = null;
        _quoteMessage = null;
        _quoteLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ok ? '✅ $msg' : '⚠️ $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore pagamento: $e')));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _ensureLateFeeQuote(PartnerBooking b) async {
    if (!_isLateOverTolerance(b)) {
      if (_quoteCents != null || _quoteMessage != null || _quoteLoading) {
        setState(() {
          _quoteLoading = false;
          _quoteCents = null;
          _quoteMessage = null;
        });
      }
      return;
    }

    if (_quoteLoading || _quoteCents != null || _quoteMessage != null) return;

    setState(() {
      _quoteLoading = true;
      _quoteMessage = null;
    });

    try {
      final res = await Supabase.instance.client.rpc(
        // STEP 2: la creeremo
        'get_late_fee_quote',
        params: {'p_booking_id': widget.bookingId},
      );

      final ok = (res is Map && res['ok'] == true);
      if (ok) {
        final amount = (res )['amount_cents'];
        final cents = (amount is int) ? amount : int.tryParse('$amount');
        setState(() {
          _quoteCents = cents;
          _quoteMessage = (res['message']?.toString());
        });
      } else {
        // messaggio “soft”
        setState(() {
          _quoteCents = null;
          _quoteMessage =
              (res is Map ? res['message']?.toString() : null) ??
              'Supplemento calcolato al momento del pagamento.';
        });
      }
    } catch (_) {
      // Se la RPC non esiste ancora, niente panico: UI resta pulita.
      setState(() {
        _quoteCents = null;
        _quoteMessage = 'Supplemento calcolato al momento del pagamento.';
      });
    } finally {
      if (mounted) setState(() => _quoteLoading = false);
    }
  }

  Future<void> _miniDialog({
    required IconData icon,
    required String title,
    required String subtitle,
  }) async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Text(subtitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Widget _statusPill({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: fg,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: fg.withOpacity(0.9),
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('QR prenotazione'),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      body: StreamBuilder<PartnerBooking?>(
        stream: _bookingStream,
        builder: (context, snap) {
          final booking = snap.data;

          if (booking != null) {
            _maybeNotify(booking);

            // ✅ carica quote solo se serve (ritardo oltre tolleranza)
            // e NON dentro la lista Widget
            _ensureLateFeeQuote(booking);
          }

          // calcolo stato “user-friendly”
          final inStore =
              booking?.dropoffEffectiveAt != null &&
              booking?.pickupEffectiveAt == null;
          final completed = booking?.pickupEffectiveAt != null;
          final waiting = booking?.dropoffEffectiveAt == null;

          final headerGradient = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.95),
              cs.primaryContainer.withOpacity(0.85),
            ],
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 90, 16, 20),
            children: [
              // HEADER “moderno”
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: headerGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.qr_code_2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mostra questo QR al partner',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Check-in e check-out verranno aggiornati in tempo reale.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // STATUS TIMELINE
              if (snap.connectionState == ConnectionState.waiting &&
                  booking == null)
                _statusPill(
                  icon: Icons.wifi_tethering,
                  title: 'Connessione…',
                  subtitle: 'Sto sincronizzando lo stato della prenotazione.',
                  bg: cs.surfaceContainerHighest.withOpacity(0.7),
                  fg: cs.onSurface,
                )
              else if (waiting)
                _statusPill(
                  icon: Icons.hourglass_top_rounded,
                  title: 'In attesa di check-in',
                  subtitle:
                      'Quando il partner scannerizza, qui vedrai l’esito.',
                  bg: cs.surfaceContainerHighest.withOpacity(0.7),
                  fg: cs.onSurface,
                )
              else if (inStore)
                _statusPill(
                  icon: Icons.inventory_2_outlined,
                  title: 'Depositato',
                  subtitle:
                      'Check-in: ${_fmt(booking!.effectiveDropoffAtLocal!)}',
                  bg: Colors.green.withOpacity(0.12),
                  fg: Colors.green.shade800,
                )
              else if (completed)
                _statusPill(
                  icon: Icons.verified_outlined,
                  title: 'Completato',
                  subtitle:
                      'Check-out: ${_fmt(booking!.effectivePickupAtLocal!)}',
                  bg: Colors.green.withOpacity(0.12),
                  fg: Colors.green.shade800,
                ),

              const SizedBox(height: 14),

              // CARD QR
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest.withOpacity(0.55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(data: widget.bookingCode, size: 240),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.bookingCode,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copia codice'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Se il partner non riesce a leggere il QR, può inserire il codice manualmente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.7),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // PAGAMENTO RITARDO — SOLO LATO UTENTE (compare appena sei oltre tolleranza)
              if (booking != null) ...[
                // carico la quote se serve (solo quando è in ritardo)

                if (_isInTolerance(booking)) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.20),
                      ),
                    ),
                    child: Text(
                      '⚠️ Sei oltre l’orario di ritiro ma ancora in tolleranza (15 min).',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_isLateOverTolerance(booking)) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Supplemento necessario',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _quoteCents != null
                              ? 'È richiesto un supplemento di ${_euro(_quoteCents!)}. Puoi pagarlo ora, prima di mostrare il QR.'
                              : (_quoteMessage ??
                                    'È richiesto un supplemento. Puoi pagarlo ora, prima di mostrare il QR.'),
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_quoteLoading) ...[
                          const LinearProgressIndicator(minHeight: 4),
                          const SizedBox(height: 10),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _paying ? null : _payLateFeeMock,
                            icon: _paying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.payments_outlined),
                            label: Text(
                              _paying ? 'Pagamento…' : 'Paga ora (mock)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],

              Text(
                'Suggerimento: tieni questa schermata aperta mentre il partner scannerizza: lo stato si aggiorna da solo.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.65),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
