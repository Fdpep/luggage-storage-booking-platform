import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../user_view/partner_drawer.dart';
import '../../../../services/supabase/partner_booking_repo.dart';
import '../../../../models/partner_booking.dart';
import 'partner_scan_camera_screen.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _busy = false;

  // area esito
  String? _message;
  bool _isError = false;
  bool _isWarning = false; // serve supplemento, ma non è errore
  PartnerBooking? _lastBooking;

  PartnerBookingRepo get _repo => PartnerBookingRepo(Supabase.instance.client);

  String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/${m} $h:$min';
  }

  bool _isValidCode(String s) {
    return RegExp(r'^BD[0-9A-F]{10}$', caseSensitive: false).hasMatch(s.trim());
  }

  Future<void> _handleCode(String code, {required bool force}) async {
    if (_busy) return;

    final c = code.trim().toUpperCase();
    if (!_isValidCode(c)) {
      setState(() {
        _message = 'Codice non valido. Formato atteso: BDXXXXXXXXXX (HEX).';
        _isError = true;
        _isWarning = false;
        _lastBooking = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
      _isWarning = false;
    });

    try {
      final res = await _repo.processBookingCode(code: c, force: force);

      final ok = (res['ok'] == true);
      final requirePay = (res['require_payment'] == true);
      final msg = (res['message'] as String?) ?? 'Operazione completata.';
      final bookingId = res['booking_id']?.toString();

      PartnerBooking? booking;
      if (bookingId != null && bookingId.isNotEmpty) {
        booking = await _repo.getBookingById(bookingId);
      }

      setState(() {
        _message = msg;
        _isWarning =
            requirePay == true; // se la RPC dice require_payment, è warning
        _isError =
            !ok && !_isWarning; // errore solo se ok=false e non è warning
        _lastBooking = booking;
      });
    } catch (e) {
      setState(() {
        _message = 'Errore: $e';
        _isError = true;
        _isWarning = false;
        _lastBooking = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PartnerScanCameraScreen()),
    );

    if (code == null) return;
    await _handleCode(code, force: false);
  }

  Future<void> _openManualDialog() async {
    final ctrl = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Inserisci codice'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'BD1A2B3C4D5E',
                      errorText: error,
                    ),
                    onChanged: (v) {
                      final up = v.toUpperCase();
                      if (up != v) {
                        ctrl.value = ctrl.value.copyWith(
                          text: up,
                          selection: TextSelection.collapsed(offset: up.length),
                        );
                      }
                      setLocal(() => error = null);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Formato: BD + 10 caratteri HEX (0-9, A-F).',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final v = ctrl.text.trim().toUpperCase();
                    if (!_isValidCode(v)) {
                      setLocal(() => error = 'Codice non valido');
                      return;
                    }
                    Navigator.of(ctx).pop();
                    _handleCode(v, force: false);
                  },
                  child: const Text('Conferma'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildResultRow(ColorScheme cs) {
    if (_message == null) {
      return Text(
        'Nessuna operazione eseguita.',
        style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
      );
    }

    IconData icon;
    Color color;

    if (_isError) {
      icon = Icons.error_outline;
      color = Colors.red;
    } else if (_isWarning) {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange;
    } else {
      icon = Icons.check_circle_outline;
      color = Colors.green;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _message!,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        title: const Text("Scanner / Codici"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operazioni',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _openScanner,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scansiona QR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _openManualDialog,
                          icon: const Icon(Icons.keyboard),
                          label: const Text('Inserisci codice'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nota emulatore: la “stanza col gatto” è la camera virtuale. Su telefono reale si apre la fotocamera.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Esito',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  if (_busy) ...[
                    const Center(child: CircularProgressIndicator()),
                  ] else ...[
                    _buildResultRow(cs),
                  ],

                  if (_lastBooking != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Codice: ${_lastBooking!.bookingCode}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Cliente: ${_lastBooking!.firstName} ${_lastBooking!.lastName}',
                          ),
                          Text(
                            'Bagagli: ${_lastBooking!.bagsS}S  ${_lastBooking!.bagsM}M  ${_lastBooking!.bagsL}L',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Dropoff previsto: ${_fmt(_lastBooking!.plannedDropoffLocal)}',
                          ),
                          Text(
                            'Pickup previsto:  ${_fmt(_lastBooking!.plannedPickupLocal)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//a
