import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: unused_import
import 'package:BagDrop/theme/app_theme.dart';

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

enum _ToastKind { success, warning, info }

class _BookingQrScreenState extends State<BookingQrScreen> {
  late final Stream<PartnerBooking?> _bookingStream;

  static const Duration _tolerance = Duration(minutes: 15);
  Timer? _ticker;

  bool _paying = false;

  // quote supplemento (server-side)
  bool _quoteLoading = false;
  int? _quoteCents;
  String? _quoteMessage;

  int? _quotePaidTotalCents;
  int? _quoteRequiredTotalCents;
  String? _quoteFromDuration;
  String? _quoteToDuration;
  DateTime? _quoteFromUntil;
  DateTime? _quoteToUntil;
  int? _quoteToExtraDays;

  DateTime? _lastQuoteAttemptAt;
  static const Duration _quoteRetryEvery = Duration(seconds: 10);

  // ✅ notifiche SOLO su transizione (non quando riapri)
  bool _bootstrapped = false;
  DateTime? _seenDropoffAt;
  DateTime? _seenPickupAt;

  // ✅ optimistic pickup dopo pagamento (evita “ricalcolo…”)
  DateTime? _optimisticPickupPlannedAtLocal;
  DateTime? _optimisticSetAt;
  static const Duration _optimisticTtl = Duration(minutes: 2);

  // ✅ toast sheet handle (per non impilare più toast)
  BuildContext? _toastSheetCtx;

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

  DateTime _plannedPickupForUi(PartnerBooking b) {
    final opt = _optimisticPickupPlannedAtLocal;
    final setAt = _optimisticSetAt;

    if (opt != null && setAt != null) {
      final alive = DateTime.now().difference(setAt) <= _optimisticTtl;
      if (alive) return opt;
    }
    return b.plannedPickupAtLocal;
  }

  void _maybeClearOptimistic(PartnerBooking b) {
    if (_optimisticPickupPlannedAtLocal == null || _optimisticSetAt == null) return;

    final alive = DateTime.now().difference(_optimisticSetAt!) <= _optimisticTtl;
    if (!alive) {
      setState(() {
        _optimisticPickupPlannedAtLocal = null;
        _optimisticSetAt = null;
      });
      return;
    }

    final serverPickup = b.plannedPickupAtLocal;
    if (!serverPickup.isBefore(_optimisticPickupPlannedAtLocal!)) {
      setState(() {
        _optimisticPickupPlannedAtLocal = null;
        _optimisticSetAt = null;
      });
    }
  }

  Future<dynamic> _performLateFeePayment({required String bookingId}) async {
    return Supabase.instance.client.rpc(
      'pay_late_fee_and_extend',
      params: {'p_booking_id': bookingId},
    );
  }

  void _closeToastIfAny() {
    final ctx = _toastSheetCtx;
    if (ctx != null) {
      final nav = Navigator.of(ctx);
      if (nav.canPop()) nav.pop();
    }
    _toastSheetCtx = null;
  }

  Future<void> _showToast({
    required IconData icon,
    required String title,
    required String subtitle,
    _ToastKind kind = _ToastKind.info,
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (!mounted) return;

    // chiudo eventuale toast precedente (no stacking)
    _closeToastIfAny();

    HapticFeedback.lightImpact();

    BuildContext? sheetCtx;

    final future = showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.12),
      isScrollControlled: false,
      useSafeArea: true,
      enableDrag: true,
      builder: (ctx) {
        sheetCtx = ctx;

        final cs = Theme.of(ctx).colorScheme;
        final (bg, fg) = switch (kind) {
          _ToastKind.success => (Colors.green.withOpacity(0.14), Colors.green.shade900),
          _ToastKind.warning => (Colors.orange.withOpacity(0.16), Colors.orange.shade900),
          _ToastKind.info => (cs.surfaceContainerHighest.withOpacity(0.60), cs.onSurface),
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _IosToastCard(
              bg: bg,
              fg: fg,
              icon: icon,
              title: title,
              subtitle: subtitle,
            ),
          ),
        );
      },
    );

    // memorizzo ctx per chiuderlo se arriva un nuovo toast
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sheetCtx != null) _toastSheetCtx = sheetCtx;
    });

    // auto-dismiss
    Future.delayed(duration, () {
      final ctx = sheetCtx;
      if (!mounted || ctx == null) return;
      final nav = Navigator.of(ctx);
      if (nav.canPop()) nav.pop();
    });

    await future;

    // cleanup handle
    if (_toastSheetCtx == sheetCtx) _toastSheetCtx = null;
  }

  Future<bool> _confirmPayDialog({int? cents, String? detail}) async {
    if (!mounted) return false;
    final cs = Theme.of(context).colorScheme;

    final amountLine = cents != null ? 'Importo: ${_euro(cents)}' : 'Importo: da calcolare';
    final body = [
      'Stai per pagare il supplemento e prolungare la prenotazione.',
      amountLine,
      if (detail != null && detail.trim().isNotEmpty) detail.trim(),
    ].join('\n\n');

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.payments_outlined, color: cs.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Confermi il pagamento?', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(cents != null ? 'Paga ${_euro(cents)}' : 'Paga'),
          ),
        ],
      ),
    );

    return res == true;
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
    _closeToastIfAny();
    super.dispose();
  }

  Future<void> _onBookingSnapshot(PartnerBooking b) async {
    _maybeClearOptimistic(b);

    final drop = b.dropoffEffectiveAt;
    final pick = b.pickupEffectiveAt;

    if (!_bootstrapped) {
      _bootstrapped = true;
      _seenDropoffAt = drop;
      _seenPickupAt = pick;
      return;
    }

    // check-in: null -> non-null
    if (_seenDropoffAt == null && drop != null) {
      _seenDropoffAt = drop;

      if (!mounted) return;
      await _showToast(
        icon: Icons.check_circle_outline,
        title: 'Check-in eseguito',
        subtitle: 'Consegna registrata alle ${_fmt(b.effectiveDropoffAtLocal!)}.',
        kind: _ToastKind.success,
      );
    } else {
      _seenDropoffAt = drop;
    }

    // check-out: null -> non-null
    if (_seenPickupAt == null && pick != null) {
      _seenPickupAt = pick;

      if (!mounted) return;
      await _showToast(
        icon: Icons.verified_outlined,
        title: 'Check-out eseguito',
        subtitle: 'Ritiro registrato alle ${_fmt(b.effectivePickupAtLocal!)}.',
        kind: _ToastKind.success,
      );

      if (mounted) Navigator.of(context).pop(true);
    } else {
      _seenPickupAt = pick;
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.bookingCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Codice copiato')));
  }

  bool _isLateOverTolerance(PartnerBooking b) {
    if (b.dropoffEffectiveAt == null) return false;
    if (b.pickupEffectiveAt != null) return false;

    final now = DateTime.now();
    final pickup = _plannedPickupForUi(b);
    final deadline = pickup.add(_tolerance);

    return now.isAfter(deadline);
  }

  bool _isInTolerance(PartnerBooking b) {
    if (b.dropoffEffectiveAt == null) return false;
    if (b.pickupEffectiveAt != null) return false;

    final now = DateTime.now();
    final pickup = _plannedPickupForUi(b);
    final deadline = pickup.add(_tolerance);

    return now.isAfter(pickup) && now.isBefore(deadline);
  }

  Future<void> _payLateFee() async {
    if (_paying) return;

    final amountCents = _quoteCents;
    if (amountCents == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importo non disponibile. Riprova tra qualche secondo.')),
      );
      return;
    }
    if (amountCents == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun importo aggiuntivo.')),
      );
      return;
    }

    final confirmed = await _confirmPayDialog(
      cents: amountCents,
      detail: 'Dopo il pagamento la prenotazione viene estesa e il QR torna valido.',
    );
    if (!confirmed) return;

    setState(() => _paying = true);

    try {
      final res = await _performLateFeePayment(bookingId: widget.bookingId);

      final ok = (res is Map && res['ok'] == true);
      final msg = (res is Map ? (res['message']?.toString()) : null) ??
          (ok ? 'Supplemento pagato' : 'Pagamento non riuscito');

      DateTime? newPickupLocal;
      final newPickup = (res is Map) ? res['new_pickup_planned_at'] : null;
      if (newPickup != null) {
        try {
          newPickupLocal = DateTime.parse(newPickup.toString()).toLocal();
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _quoteCents = null;
        _quoteMessage = null;
        _quoteLoading = false;
        _lastQuoteAttemptAt = null;

        if (ok && newPickupLocal != null) {
          _optimisticPickupPlannedAtLocal = newPickupLocal;
          _optimisticSetAt = DateTime.now();
        }
      });

      final extra = (newPickupLocal != null) ? ' • Estesa fino a ${_fmt(newPickupLocal)}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '✅ $msg$extra' : '⚠️ $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore pagamento: $e')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _ensureLateFeeQuote(PartnerBooking b, {bool force = false}) async {
    if (!_isLateOverTolerance(b)) {
      if (_quoteCents != null || _quoteMessage != null || _quoteLoading) {
        if (!mounted) return;
        setState(() {
          _quoteLoading = false;
          _quoteCents = null;
          _quoteMessage = null;
        });
      }
      return;
    }

    if (_quoteLoading) return;

    final now = DateTime.now();
    if (!force && _lastQuoteAttemptAt != null && now.difference(_lastQuoteAttemptAt!) < _quoteRetryEvery) {
      return;
    }
    if (!force && _quoteCents != null) return;

    _lastQuoteAttemptAt = now;

    if (!mounted) return;
    setState(() {
      _quoteLoading = true;
      if (force) _quoteMessage = null;
    });

    try {
      final res = await Supabase.instance.client.rpc(
        'get_late_fee_quote',
        params: {'p_booking_id': widget.bookingId},
      );

      final ok = (res is Map && res['ok'] == true);
      if (ok) {
        final amount = (res)['amount_cents'];
        final cents = (amount is int) ? amount : int.tryParse('$amount');

        _quotePaidTotalCents = int.tryParse('${res['paid_total_cents']}');
        _quoteRequiredTotalCents = int.tryParse('${res['required_total_cents']}');
        _quoteFromDuration = res['from_duration']?.toString();
        _quoteToDuration = res['to_duration']?.toString();
        _quoteToExtraDays = int.tryParse('${res['to_extra_days']}');

        final fu = res['from_covered_until'];
        final tu = res['to_covered_until'];
        _quoteFromUntil = fu != null ? DateTime.parse(fu.toString()).toLocal() : null;
        _quoteToUntil = tu != null ? DateTime.parse(tu.toString()).toLocal() : null;

        if (!mounted) return;
        setState(() {
          _quoteCents = cents;
          _quoteMessage = (res['message']?.toString());
        });
      } else {
        final msg = (res is Map ? res['message']?.toString() : null);
        if (!mounted) return;
        setState(() {
          _quoteCents = null;
          _quoteMessage = (msg?.isNotEmpty == true)
              ? msg
              : 'Supplemento calcolato al momento del pagamento.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteCents = null;
        _quoteMessage = 'Errore calcolo importo: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _quoteLoading = false);
    }
  }

  Widget _statusCard({
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: fg.withOpacity(0.85), fontSize: 12, height: 1.2),
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
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('QR CODE'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: StreamBuilder<PartnerBooking?>(
        stream: _bookingStream,
        builder: (context, snap) {
          final booking = snap.data;

          if (booking != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await _onBookingSnapshot(booking);
              await _ensureLateFeeQuote(booking);
            });
          }

          final waiting = booking?.dropoffEffectiveAt == null;
          final inStore = booking?.dropoffEffectiveAt != null && booking?.pickupEffectiveAt == null;
          final completed = booking?.pickupEffectiveAt != null;

          final liveActive = snap.connectionState == ConnectionState.active && !snap.hasError;

          final headerGradient = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.95),
              cs.primaryContainer.withOpacity(0.85),
            ],
          );

          final qrDisabled = booking != null && _isLateOverTolerance(booking);
          final hasQuote = (_quoteCents ?? 0) > 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              // HERO + LIVE
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: headerGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
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
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.qr_code_2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mostra il QR al partner',
                            style: tt.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Check-in e check-out si aggiornano in tempo reale.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _LiveBadge(active: liveActive),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // STATUS
              if (snap.connectionState == ConnectionState.waiting && booking == null)
                _statusCard(
                  icon: Icons.wifi_tethering,
                  title: 'Connessione…',
                  subtitle: 'Sto sincronizzando lo stato della prenotazione.',
                  bg: cs.surfaceContainerHighest.withOpacity(0.6),
                  fg: cs.onSurface,
                )
              else if (waiting)
                _statusCard(
                  icon: Icons.hourglass_top_rounded,
                  title: 'In attesa di check-in',
                  subtitle: 'Quando il partner scannerizza, vedrai subito l’esito qui.',
                  bg: cs.surfaceContainerHighest.withOpacity(0.6),
                  fg: cs.onSurface,
                )
              else if (inStore)
                _statusCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Depositato',
                  subtitle: 'Check-in: ${_fmt(booking!.effectiveDropoffAtLocal!)}',
                  bg: Colors.green.withOpacity(0.10),
                  fg: Colors.green.shade800,
                )
              else if (completed)
                _statusCard(
                  icon: Icons.verified_outlined,
                  title: 'Completato',
                  subtitle: 'Check-out: ${_fmt(booking!.effectivePickupAtLocal!)}',
                  bg: Colors.green.withOpacity(0.10),
                  fg: Colors.green.shade800,
                ),

              if (booking != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, color: cs.onSurface.withOpacity(0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ritiro previsto: ${_fmt(_plannedPickupForUi(booking))}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withOpacity(0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // QR CARD (disabled overlay se serve supplemento)
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest.withOpacity(0.55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: cs.surface,
                              child: Opacity(
                                opacity: qrDisabled ? 0.22 : 1,
                                child: QrImageView(data: widget.bookingCode, size: 240),
                              ),
                            ),

                            if (qrDisabled) ...[
                              Positioned.fill(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                                  child: Container(color: Colors.black.withOpacity(0.05)),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.20)),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lock_outline, color: Colors.white),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'QR disabilitato',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Paga il supplemento per riattivarlo.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.bookingCode,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: qrDisabled ? cs.onSurface.withOpacity(0.45) : cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Copia',
                            onPressed: _copyCode,
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),

                      Text(
                        'Se il partner non riesce a leggere il QR, può inserire il codice manualmente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.7),
                          height: 1.2,
                        ),
                      ),

                      if (qrDisabled) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.withOpacity(0.20)),
                          ),
                          child: Text(
                            '⚠️ Il partner non potrà completare il check-out finché non paghi il supplemento.',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface.withOpacity(0.85),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // TOLLERANZA
              if (booking != null && _isInTolerance(booking)) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.orange.withOpacity(0.20)),
                  ),
                  child: Text(
                    '⚠️ Sei oltre l’orario di ritiro ma ancora in tolleranza (15 min).',
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.85),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // SUPPLEMENTO
              if (booking != null && _isLateOverTolerance(booking)) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.orange.withOpacity(0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Supplemento necessario', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        hasQuote
                            ? 'È richiesto un supplemento di ${_euro(_quoteCents!)}. Pagalo ora per riattivare il QR.'
                            : (_quoteMessage ?? 'È richiesto un supplemento. Tocca per calcolare l’importo.'),
                        style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
                      ),

                      if (_quotePaidTotalCents != null && _quoteRequiredTotalCents != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Hai pagato : ${_euro(_quotePaidTotalCents!)}'
                          '${_quoteFromUntil != null ? ' (coperto fino a ${_fmt(_quoteFromUntil!)} )' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.75)),
                        ),
                        Text(
                          'Fascia: ${_quoteToDuration ?? '-'}'
                          '${_quoteToUntil != null ? ' → copre fino a ${_fmt(_quoteToUntil!)}' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.75)),
                        ),
                        Text(
                          'Totale dovuto ora: ${_euro(_quoteRequiredTotalCents!)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.75)),
                        ),
                      ],

                      const SizedBox(height: 10),

                      if (_quoteLoading) ...[
                        const LinearProgressIndicator(minHeight: 4),
                        const SizedBox(height: 10),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_paying || _quoteLoading)
                                  ? null
                                  : (hasQuote ? _payLateFee : () => _ensureLateFeeQuote(booking, force: true)),
                              icon: _paying
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(hasQuote ? Icons.payments_outlined : Icons.refresh_rounded),
                              label: Text(
                                _paying
                                    ? 'Pagamento…'
                                    : (_quoteLoading
                                        ? 'Calcolo importo…'
                                        : (hasQuote ? 'Paga ${_euro(_quoteCents!)}' : 'Calcola importo')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Text(
                'Suggerimento: tieni questa schermata aperta mentre il partner scannerizza.',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.65)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IosToastCard extends StatelessWidget {
  final Color bg;
  final Color fg;
  final IconData icon;
  final String title;
  final String subtitle;

  const _IosToastCard({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: fg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: fg.withOpacity(0.85), fontSize: 12, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final bool active;

  const _LiveBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = active ? Colors.green.withOpacity(0.22) : Colors.white.withOpacity(0.18);
    final fg = active ? Colors.white : Colors.white.withOpacity(0.85);
    final dot = active ? Colors.greenAccent : cs.onSurface.withOpacity(0.45);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'LIVE' : 'OFF',
            style: TextStyle(fontWeight: FontWeight.w900, color: fg, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
