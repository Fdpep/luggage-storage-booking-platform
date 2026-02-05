import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../user_view/partner_drawer.dart';
import '../../../../services/supabase/partner_booking_repo.dart';
import '../../../../models/partner_booking.dart';
import 'partner_scan_camera_screen.dart';
import 'package:flutter/services.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _busy = false;
  final _picker = ImagePicker();
  String? _lastAction; // 'check_in' | 'check_out' | ...

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
        _lastAction = null;
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
      // 1) PREVIEW (no side effects)
      final preview = await _repo.previewBookingCode(code: c);
      final okPreview = preview['ok'] == true;

      final action = (preview['action'] as String?) ?? '';
      final bookingId = preview['booking_id']?.toString();

      PartnerBooking? booking;
      if (bookingId != null && bookingId.isNotEmpty) {
        booking = await _repo.getBookingById(bookingId);
      }

      if (!okPreview) {
        setState(() {
          _message =
              (preview['message'] as String?) ?? 'Operazione non consentita.';
          _isError = true;
          _isWarning = false;
          _lastBooking = booking;
          _lastAction = action;
        });
        return;
      }

      if (action == 'already_done') {
        setState(() {
          _message = (preview['message'] as String?) ?? 'Già completata.';
          _isError = false;
          _isWarning = false;
          _lastBooking = booking;
          _lastAction = action;
        });
        return;
      }

      if (booking == null) {
        setState(() {
          _message = 'Prenotazione non trovata.';
          _isError = true;
          _isWarning = false;
          _lastBooking = null;
          _lastAction = action;
        });
        return;
      }

      //  se è check-in e NON è ancora l’ora → messaggio subito, niente sheet
      final bool checkinAllowed = (preview['checkin_allowed'] as bool?) ?? true;
      if (action == 'check_in' && checkinAllowed == false) {
        setState(() {
          _message =
              (preview['message'] as String?) ??
              'Check-in non consentito: non è ancora l’orario previsto.';
          _isError = true;
          _isWarning = false;
          _lastBooking = booking;
          _lastAction = action;
        });
        return;
      }

      // 2) SHEET di conferma
      final res = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        useRootNavigator: false,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => _ScanConfirmSheet(
          repo: _repo,
          picker: _picker,
          code: c,
          booking: booking!,
          preview: preview,
          fmt: _fmt,
        ),
      );

      if (res == null) return;

      final ok = (res['ok'] == true);
      final requirePay = (res['require_payment'] == true);
      final msg = (res['message'] as String?) ?? 'Operazione completata.';
      final act = (res['action'] as String?) ?? action;

      final bid = res['booking_id']?.toString() ?? booking.id;
      final updated = await _repo.getBookingById(bid);

      setState(() {
        _message = msg;
        _isWarning = requirePay == true;
        _isError = !ok && !_isWarning;
        _lastBooking = updated ?? booking;
        _lastAction = act;
      });
    } catch (e) {
      setState(() {
        _message = 'Errore: $e';
        _isError = true;
        _isWarning = false;
        _lastBooking = null;
        _lastAction = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _signedUrlForBooking(PartnerBooking b) async {
    final path = b.checkinPhotoPath;
    if (path == null || path.isEmpty) return null;

    final bucket =
        (b.checkinPhotoBucket == null || b.checkinPhotoBucket!.isEmpty)
        ? PartnerBookingRepo.bookingCheckinBucket
        : b.checkinPhotoBucket!;

    return _repo.createSignedCheckinPhotoUrl(
      path: path,
      bucket: bucket,
      expiresInSeconds: 300,
    );
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

  // Apri il bottom sheet di conferma check-in/check-out

  Future<Map<String, dynamic>?> _openConfirmSheet({
    required String code,
    required PartnerBooking booking,
    required Map<String, dynamic> preview,
  }) async {
    final cs = Theme.of(context).colorScheme;

    final action = (preview['action'] as String?) ?? '';
    final isCheckIn = action == 'check_in';
    final isCheckOut = action == 'check_out';

    final bool checkinAllowed = (preview['checkin_allowed'] as bool?) ?? true;
    final DateTime? notBefore = preview['not_before'] != null
        ? DateTime.parse(preview['not_before'].toString()).toLocal()
        : null;

    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        File? photoFile;
        bool ack = false;
        bool loading = false;
        bool needsPayStep = false;
        String? localError;

        final String bucket =
            (booking.checkinPhotoBucket ??
            PartnerBookingRepo.bookingCheckinBucket);
        final String? path = booking.checkinPhotoPath;

        Future<String?> signedUrlFuture() async {
          if (path == null || path.isEmpty) return null;
          return _repo.createSignedCheckinPhotoUrl(path: path, bucket: bucket);
        }

        String fmt(DateTime dt) => _fmt(dt);

        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> pickPhoto() async {
              final x = await _picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 82,
                maxWidth: 1600,
              );
              if (x == null) return;
              setModal(() {
                photoFile = File(x.path);
                localError = null;
              });
            }

            Future<Map<String, dynamic>> doCheckIn() async {
              setModal(() {
                loading = true;
                localError = null;
              });
              try {
                final photoPath = _repo.buildCheckinPhotoPath(
                  partnerId: booking.partnerId,
                  bookingId: booking.id,
                );

                await _repo.uploadCheckinPhoto(
                  file: photoFile!,
                  path: photoPath,
                );

                final res = await _repo.processBookingCodeV2(
                  code: code,
                  action: 'check_in',
                  force: false,
                  checkinPhotoPath: photoPath,
                  ackPhoto: false,
                );
                return res;
              } finally {
                setModal(() => loading = false);
              }
            }

            Future<Map<String, dynamic>> doCheckOut({
              required bool force,
            }) async {
              setModal(() {
                loading = true;
                localError = null;
              });
              try {
                final res = await _repo.processBookingCodeV2(
                  code: code,
                  action: 'check_out',
                  force: force,
                  checkinPhotoPath: null,
                  ackPhoto: true,
                );
                return res;
              } finally {
                setModal(() => loading = false);
              }
            }

            final title = isCheckIn
                ? 'Conferma check-in'
                : isCheckOut
                ? 'Conferma check-out'
                : 'Conferma';

            final canConfirmCheckIn =
                isCheckIn && checkinAllowed && photoFile != null && !loading;
            final canConfirmCheckOut =
                isCheckOut && (path == null || path.isEmpty || ack) && !loading;

            Widget bookingBox() {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Codice: ${booking.bookingCode}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text('Cliente: ${booking.firstName} ${booking.lastName}'),
                    Text(
                      'Bagagli: ${booking.bagsS}S  ${booking.bagsM}M  ${booking.bagsL}L',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dropoff previsto: ${fmt(booking.plannedDropoffAtLocal)}',
                    ),
                    Text(
                      'Pickup previsto:  ${fmt(booking.plannedPickupAtLocal)}',
                    ),
                  ],
                ),
              );
            }

            Widget bannerEarly() {
              if (!isCheckIn || checkinAllowed) return const SizedBox.shrink();
              final when = notBefore != null ? fmt(notBefore!) : 'più tardi';
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Check-in disponibile dalle $when',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget photoPickerBox() {
              if (!isCheckIn) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Foto bagaglio',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    if (photoFile == null) ...[
                      Text(
                        'Scatta una foto del bagaglio prima di confermare.',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : pickPhoto,
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Scatta foto'),
                        ),
                      ),
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          photoFile!,
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: loading ? null : pickPhoto,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Riprova'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }

            Widget checkoutPhotoBox() {
              if (!isCheckOut) return const SizedBox.shrink();

              if (path == null || path.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    'Nessuna foto check-in associata.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Foto al check-in',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<String?>(
                      future: signedUrlFuture(),
                      builder: (ctx, snap) {
                        final url = snap.data;
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 190,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (url == null) {
                          return Text(
                            'Impossibile caricare la foto.',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            height: 190,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ack,
                      onChanged: loading
                          ? null
                          : (v) => setModal(() => ack = v == true),
                      title: const Text(
                        'Confermo che il bagaglio è ok e procedo col check-out',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }

            Future<void> onPrimary() async {
              if (loading) return;

              // Check-in
              if (isCheckIn) {
                if (!checkinAllowed) return;
                if (photoFile == null) {
                  setModal(
                    () => localError = 'Scatta una foto per continuare.',
                  );
                  return;
                }

                final res = await doCheckIn();
                if (res['ok'] == true) {
                  if (ctx.mounted) Navigator.of(ctx).pop(res);
                  return;
                }

                // errori “leggibili” dal server
                final codeErr = res['code']?.toString();
                if (codeErr == 'BD_CHECKIN_TOO_EARLY') {
                  setModal(() => localError = res['message']?.toString());
                  return;
                }
                setModal(
                  () => localError =
                      res['message']?.toString() ?? 'Operazione non riuscita.',
                );
                return;
              }

              // Check-out
              if (isCheckOut) {
                if (path != null && path.isNotEmpty && !ack) {
                  setModal(
                    () => localError = 'Seleziona la conferma per continuare.',
                  );
                  return;
                }

                // step 1: prova senza force
                final res = await doCheckOut(force: false);
                if (res['ok'] == true) {
                  if (ctx.mounted) Navigator.of(ctx).pop(res);
                  return;
                }

                if (res['require_payment'] == true) {
                  setModal(() {
                    needsPayStep = true;
                    localError = res['message']?.toString();
                  });
                  return;
                }

                setModal(
                  () => localError =
                      res['message']?.toString() ?? 'Operazione non riuscita.',
                );
              }
            }

            Future<void> onPayNow() async {
              final res = await doCheckOut(force: true);
              if (res['ok'] == true) {
                if (ctx.mounted) Navigator.of(ctx).pop(res);
                return;
              }
              setModal(
                () => localError =
                    res['message']?.toString() ?? 'Operazione non riuscita.',
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  bookingBox(),
                  const SizedBox(height: 10),
                  bannerEarly(),
                  if (!checkinAllowed) const SizedBox(height: 10),
                  photoPickerBox(),
                  if (isCheckIn) const SizedBox(height: 10),
                  checkoutPhotoBox(),
                  if (isCheckOut) const SizedBox(height: 10),

                  if (localError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        localError!,
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: loading
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          child: const Text('Annulla'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              (isCheckIn && !canConfirmCheckIn) ||
                                  (isCheckOut && !canConfirmCheckOut)
                              ? null
                              : onPrimary,
                          child: loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isCheckIn
                                      ? 'Conferma check-in'
                                      : 'Conferma check-out',
                                ),
                        ),
                      ),
                    ],
                  ),

                  if (isCheckOut && needsPayStep) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : onPayNow,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Paga ora'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
  // fine openConfirmSheet

  // Costruisci la riga di esito

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
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Scanner / Codici',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
              .copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: cs.onPrimary,
              ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.onPrimary.withOpacity(0.12)),
        ),
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
                            'Dropoff previsto: ${_fmt(_lastBooking!.plannedDropoffAtLocal)}',
                          ),
                          Text(
                            'Pickup previsto:  ${_fmt(_lastBooking!.plannedPickupAtLocal)}',
                          ),

                          if (_lastAction == 'check_in' &&
                              !_isError &&
                              _lastBooking!.checkinPhotoPath != null &&
                              _lastBooking!.checkinPhotoPath!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Foto check-in',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<String?>(
                              future: _signedUrlForBooking(_lastBooking!),
                              builder: (ctx, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox(
                                    height: 160,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final url = snap.data;
                                if (url == null) {
                                  return Text(
                                    'Foto non disponibile.',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(0.7),
                                    ),
                                  );
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    url,
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),
                          ],
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

class _ScanConfirmSheet extends StatefulWidget {
  final PartnerBookingRepo repo;
  final ImagePicker picker;
  final String code;
  final PartnerBooking booking;
  final Map<String, dynamic> preview;
  final String Function(DateTime) fmt;

  const _ScanConfirmSheet({
    required this.repo,
    required this.picker,
    required this.code,
    required this.booking,
    required this.preview,
    required this.fmt,
  });

  @override
  State<_ScanConfirmSheet> createState() => _ScanConfirmSheetState();
}

class _ScanConfirmSheetState extends State<_ScanConfirmSheet> {
  File? _photoFile;
  bool _ack = false;
  bool _loading = false;
  bool _needsPayStep = false;
  String? _localError;

  final ScrollController _scroll = ScrollController();

  static const String kSupportEmail = 'bagdrop.milano@gmail.com';
  static const String kSupportSocial = '@bagdrop.ita';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _isCheckIn => (widget.preview['action'] as String?) == 'check_in';
  bool get _isCheckOut => (widget.preview['action'] as String?) == 'check_out';

  bool get _checkinAllowed =>
      (widget.preview['checkin_allowed'] as bool?) ?? true;

  DateTime? get _notBefore {
    final v = widget.preview['not_before'];
    if (v == null) return null;
    return DateTime.parse(v.toString()).toLocal();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await widget.picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (x == null) return;
    if (!mounted) return;

    setState(() {
      _photoFile = File(x.path);
      _localError = null;
    });

    // ✅ evita “glitch” post-camera e riporta il focus nella sheet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0, // puoi anche mettere maxScrollExtent se vuoi scrollare in basso
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<String?> _signedUrlIfAny() async {
    final path = widget.booking.checkinPhotoPath;
    if (path == null || path.isEmpty) return null;

    final bucket =
        (widget.booking.checkinPhotoBucket == null ||
            widget.booking.checkinPhotoBucket!.isEmpty)
        ? PartnerBookingRepo.bookingCheckinBucket
        : widget.booking.checkinPhotoBucket!;

    return widget.repo.createSignedCheckinPhotoUrl(
      path: path,
      bucket: bucket,
      expiresInSeconds: 300,
    );
  }

  Future<Map<String, dynamic>> _doCheckIn() async {
    setState(() {
      _loading = true;
      _localError = null;
    });
    try {
      final photoPath = widget.repo.buildCheckinPhotoPath(
        partnerId: widget.booking.partnerId,
        bookingId: widget.booking.id,
      );

      await widget.repo.uploadCheckinPhoto(file: _photoFile!, path: photoPath);

      final res = await widget.repo.processBookingCodeV2(
        code: widget.code,
        action: 'check_in',
        force: false,
        checkinPhotoPath: photoPath,
        ackPhoto: false,
      );
      return res;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _doCheckOut({required bool force}) async {
    setState(() {
      _loading = true;
      _localError = null;
    });
    try {
      final res = await widget.repo.processBookingCodeV2(
        code: widget.code,
        action: 'check_out',
        force: force,
        checkinPhotoPath: null,
        ackPhoto: true,
      );
      return res;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = _isCheckIn
        ? 'Conferma check-in'
        : _isCheckOut
        ? 'Conferma check-out'
        : 'Conferma';

    final canConfirmCheckIn =
        _isCheckIn && _checkinAllowed && _photoFile != null && !_loading;
    final hasPath = (widget.booking.checkinPhotoPath?.isNotEmpty ?? false);
    final canConfirmCheckOut = _isCheckOut && (!hasPath || _ack) && !_loading;

    Widget bookingBox() {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Codice: ${widget.booking.bookingCode}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Cliente: ${widget.booking.firstName} ${widget.booking.lastName}',
            ),
            Text(
              'Bagagli: ${widget.booking.bagsS}S  ${widget.booking.bagsM}M  ${widget.booking.bagsL}L',
            ),
            const SizedBox(height: 6),
            Text(
              'Dropoff previsto: ${widget.fmt(widget.booking.plannedDropoffAtLocal)}',
            ),
            Text(
              'Pickup previsto:  ${widget.fmt(widget.booking.plannedPickupAtLocal)}',
            ),
          ],
        ),
      );
    }

    Widget bannerEarly() {
      if (!_isCheckIn || _checkinAllowed) return const SizedBox.shrink();
      final when = _notBefore != null ? widget.fmt(_notBefore!) : 'più tardi';
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Check-in disponibile dalle $when',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    Widget photoPickerBox() {
      if (!_isCheckIn) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Foto bagaglio',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),

            if (_photoFile == null) ...[
              Text(
                'Scatta o carica una foto del bagaglio prima di confermare.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Scatta'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Carica'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _photoFile!,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riscatta'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Sostituisci'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    Widget checkoutPhotoBox() {
      if (!_isCheckOut) return const SizedBox.shrink();

      if (!hasPath) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Text(
            'Nessuna foto check-in associata.',
            style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Foto al check-in',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            FutureBuilder<String?>(
              future: _signedUrlIfAny(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 190,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final url = snap.data;
                if (url == null) {
                  return Text(
                    'Impossibile caricare la foto.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _ack,
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _ack = v == true),
              title: const Text(
                'Confermo che il bagaglio è ok e procedo col check-out',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    Widget issueHelpBox() {
      if (!_isCheckOut) return const SizedBox.shrink();

      Future<void> copy(String text, String toast) async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(toast)));
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se non è tutto ok',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '• Fai uno screen di questa schermata\n'
              '• Scatta una foto ai bagagli\n'
              '• Contattaci via email o social prima di concludere il check-out',
              style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => copy(
                            kSupportEmail,
                            'Email copiata: $kSupportEmail',
                          ),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Copia email'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => copy(
                            widget.booking.bookingCode,
                            'Codice copiato',
                          ),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copia codice'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Social: $kSupportSocial',
              style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
            ),
          ],
        ),
      );
    }

    Future<void> onPrimary() async {
      if (_loading) return;

      if (_isCheckIn) {
        if (!_checkinAllowed) return;
        if (_photoFile == null) {
          setState(
            () => _localError = 'Scatta o carica una foto per continuare.',
          );
          return;
        }

        final res = await _doCheckIn();
        if (res['ok'] == true) {
          if (mounted) Navigator.of(context).pop(res);
          return;
        }
        setState(
          () => _localError =
              res['message']?.toString() ?? 'Operazione non riuscita.',
        );
        return;
      }

      if (_isCheckOut) {
        if (hasPath && !_ack) {
          setState(() => _localError = 'Seleziona la conferma per continuare.');
          return;
        }

        final res = await _doCheckOut(force: false);
        if (res['ok'] == true) {
          if (mounted) Navigator.of(context).pop(res);
          return;
        }

        if (res['require_payment'] == true) {
          setState(() {
            _needsPayStep = true;
            _localError = res['message']?.toString();
          });
          return;
        }

        setState(
          () => _localError =
              res['message']?.toString() ?? 'Operazione non riuscita.',
        );
      }
    }

    Future<void> onPayNow() async {
      final res = await _doCheckOut(force: true);
      if (res['ok'] == true) {
        if (mounted) Navigator.of(context).pop(res);
        return;
      }
      setState(
        () => _localError =
            res['message']?.toString() ?? 'Operazione non riuscita.',
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          bookingBox(),
          const SizedBox(height: 10),
          bannerEarly(),
          if (!_checkinAllowed) const SizedBox(height: 10),
          photoPickerBox(),
          if (_isCheckIn) const SizedBox(height: 10),
          checkoutPhotoBox(),
          const SizedBox(height: 10),
          issueHelpBox(),
          if (_isCheckOut) const SizedBox(height: 10),

          if (_localError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.65),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Text(
                _localError!,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (_isCheckIn && !canConfirmCheckIn) ||
                          (_isCheckOut && !canConfirmCheckOut)
                      ? null
                      : onPrimary,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isCheckIn
                              ? 'Conferma check-in'
                              : 'Conferma check-out',
                        ),
                ),
              ),
            ],
          ),

          /*
          if (_isCheckOut && _needsPayStep) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : onPayNow,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Paga ora'),
              ),
            ),
          ],  */
        ],
      ),
    );
  }
}



/* Come viene salvata la foto e come la ritrovi
Dove finisce fisicamente

Supabase Storage

bucket: booking-checkin-photos

path deterministico:
{partner_id}/{booking_id}/checkin.jpg
(quindi non hai duplicati, e puoi sovrascrivere se rifai la foto)

Cosa viene scritto nel DB

Nella riga public.partner_bookings (ID = booking_id) vengono salvati:

checkin_photo_bucket = 'booking-checkin-photos'

checkin_photo_path = 'partnerId/bookingId/checkin.jpg'

checkin_photo_uploaded_at = timestamp upload (server-side)

checkin_photo_expires_at = timestamp TTL (server-side, es. now()+7 giorni)

Quindi se “succede qualcosa” e vuoi recuperare la foto:

prendi la booking (es. select * from partner_bookings where id = ...)

leggi checkin_photo_bucket + checkin_photo_path

da Flutter fai createSignedUrl(path, 300) e la mostri / scarichi

Finché non parte il cleanup TTL, la foto rimane recuperabile con quel path (e policy corrette).

*/


//BD29DE336FF3  check out da fare
//BD765D15E529 check in tra tanto
//BD567AA0088E check in ora
//BDE69D7B1815 supplemento da pagare

