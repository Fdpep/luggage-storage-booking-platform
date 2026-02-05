import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../user_view/partner_drawer.dart';
import '../../../../services/supabase/partner_booking_repo.dart';
import '../../../../models/partner_booking.dart';
import 'partner_scan_camera_screen.dart';
import 'package:flutter/services.dart';

/// iOS-like helpers (locali al file)
Widget _iosSection(BuildContext context, {required List<Widget> children}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: cs.surfaceVariant.withOpacity(0.25),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

Widget _thinDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 1,
    color: cs.outlineVariant.withOpacity(0.7),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _busy = false;
  final _picker = ImagePicker();

  // Esito
  String? _message;
  bool _isError = false;
  bool _isWarning = false;
  PartnerBooking? _lastBooking;
  String? _lastAction;

  // Pending flow (inline)
  String? _pendingCode;
  Map<String, dynamic>? _pendingPreview;
  PartnerBooking? _pendingBooking;
  String? _pendingAction;
  File? _pendingPhotoFile; // check-in
  bool _pendingAck = false; // check-out
  bool _pendingNeedsPayStep = false; // supplemento
  String? _pendingLocalError;

  // Lost-data recovery (Android image_picker)
  File? _recoveredPhotoFile;
  String? _lostDataError;

  PartnerBookingRepo get _repo => PartnerBookingRepo(Supabase.instance.client);

  static const String kSupportEmail = 'bagdrop.milano@gmail.com';
  static const String kSupportSocial = '@bagdrop.ita';

  @override
  void initState() {
    super.initState();
    _recoverLostImageIfAny();
  }

  Future<void> _recoverLostImageIfAny() async {
    try {
      final res = await _picker.retrieveLostData();
      if (res.isEmpty) return;

      if (res.file != null) {
        final f = File(res.file!.path);
        if (!mounted) return;
        setState(() {
          _recoveredPhotoFile = f;
          _lostDataError = null;
        });
      } else if (res.exception != null) {
        if (!mounted) return;
        setState(() {
          _lostDataError = res.exception!.code;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lostDataError = e.toString();
      });
    }
  }

  String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  bool _isValidCode(String s) {
    return RegExp(r'^BD[0-9A-F]{10}$', caseSensitive: false)
        .hasMatch(s.trim());
  }

  void _clearPending() {
    setState(() {
      _pendingCode = null;
      _pendingPreview = null;
      _pendingBooking = null;
      _pendingAction = null;
      _pendingPhotoFile = null;
      _pendingAck = false;
      _pendingNeedsPayStep = false;
      _pendingLocalError = null;
    });
  }

  bool _looksLikeSupplementBlock(String? msg) {
    final m = (msg ?? '').toLowerCase();
    return m.contains('non autorizzato') ||
        m.contains('non autorizzata') ||
        m.contains('not authorized') ||
        m.contains('not authorised');
  }

  String _supplementHelpText({required String bookingCode}) {
    return 'Il cliente deve pagare il supplemento per completare il check-out.\n\n'
        
        'Se hai problemi, contatta l’assistenza e indica il codice: $bookingCode\n'
        'Social: $kSupportSocial\n'
        'Email: $kSupportEmail';
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
        _pendingLocalError = null;
        _pendingNeedsPayStep = false;
        _pendingBooking = null;
        _pendingAction = null;
        _pendingPreview = null;
        _pendingCode = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _pendingLocalError = null;
      _pendingNeedsPayStep = false;
      _pendingCode = null;
      _pendingPreview = null;
      _pendingBooking = null;
      _pendingAction = null;
      _pendingPhotoFile = null;
      _pendingAck = false;
    });

    try {
      final preview = await _repo.previewBookingCode(code: c);
      final okPreview = preview['ok'] == true;

      final action = (preview['action'] as String?) ?? '';
      final bookingId = preview['booking_id']?.toString();

      PartnerBooking? booking;
      if (bookingId != null && bookingId.isNotEmpty) {
        booking = await _repo.getBookingById(bookingId);
      }

      if (!okPreview) {
        final msg = (preview['message'] as String?) ?? 'Operazione non consentita.';
        final looksSupp = action == 'check_out' && _looksLikeSupplementBlock(msg);

        setState(() {
          _message = looksSupp && booking != null
              ? _supplementHelpText(bookingCode: booking.bookingCode)
              : msg;
          _isWarning = looksSupp;
          _isError = !looksSupp;
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

      final bool checkinAllowed = (preview['checkin_allowed'] as bool?) ?? true;
      if (action == 'check_in' && checkinAllowed == false) {
        setState(() {
          _message = (preview['message'] as String?) ??
              'Check-in non consentito: non è ancora l’orario previsto.';
          _isError = true;
          _isWarning = false;
          _lastBooking = booking;
          _lastAction = action;
        });
        return;
      }

      setState(() {
        _pendingCode = c;
        _pendingPreview = preview;
        _pendingBooking = booking;
        _pendingAction = action;
        _pendingPhotoFile = null;
        _pendingAck = false;
        _pendingNeedsPayStep = false;
        _pendingLocalError = null;
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

  Future<void> _pickPendingPhoto(ImageSource source) async {
    if (_busy) return;

    // ↓↓↓ più leggero: riduce rischio kill/recreate mentre camera è aperta
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (x == null) return;
    if (!mounted) return;

    setState(() {
      _pendingPhotoFile = File(x.path);
      _pendingLocalError = null;
      // se avevamo una foto recuperata, la consideriamo “superata”
      _recoveredPhotoFile = null;
      _lostDataError = null;
    });
  }

  Future<Map<String, dynamic>> _doCheckInInline({
    required String code,
    required PartnerBooking booking,
    required File photoFile,
  }) async {
    final photoPath = _repo.buildCheckinPhotoPath(
      partnerId: booking.partnerId,
      bookingId: booking.id,
    );

    await _repo.uploadCheckinPhoto(file: photoFile, path: photoPath);

    final res = await _repo.processBookingCodeV2(
      code: code,
      action: 'check_in',
      force: false,
      checkinPhotoPath: photoPath,
      ackPhoto: false,
    );
    return res;
  }

  Future<Map<String, dynamic>> _doCheckOutInline({
    required String code,
    required bool force,
  }) async {
    final res = await _repo.processBookingCodeV2(
      code: code,
      action: 'check_out',
      force: force,
      checkinPhotoPath: null,
      ackPhoto: true,
    );
    return res;
  }

  Future<void> _confirmPending() async {
    if (_busy) return;
    final booking = _pendingBooking;
    final action = _pendingAction;
    final code = _pendingCode;
    final preview = _pendingPreview;

    if (booking == null || action == null || code == null || preview == null) {
      return;
    }

    final isIn = action == 'check_in';
    final isOut = action == 'check_out';

    final bool checkinAllowed = (preview['checkin_allowed'] as bool?) ?? true;

    setState(() {
      _busy = true;
      _pendingLocalError = null;
      _pendingNeedsPayStep = false;
    });

    try {
      if (isIn) {
        if (!checkinAllowed) {
          setState(() {
            _pendingLocalError =
                (preview['message'] as String?) ??
                'Check-in non consentito: non è ancora l’orario previsto.';
          });
          return;
        }

        // Se c’è una foto recuperata e non ne hai scelta una nuova, proponila
        if (_pendingPhotoFile == null && _recoveredPhotoFile != null) {
          setState(() {
            _pendingPhotoFile = _recoveredPhotoFile;
            _recoveredPhotoFile = null;
          });
        }

        if (_pendingPhotoFile == null) {
          setState(() {
            _pendingLocalError = 'Scatta o carica una foto del bagaglio per continuare.';
          });
          return;
        }

        final res = await _doCheckInInline(
          code: code,
          booking: booking,
          photoFile: _pendingPhotoFile!,
        );

        final ok = (res['ok'] == true);
        final msg = (res['message'] as String?) ??
            (ok ? 'Check-in completato.' : 'Operazione non riuscita.');

        if (!ok) {
          setState(() {
            _pendingLocalError = msg;
          });
          return;
        }

        final bid = res['booking_id']?.toString() ?? booking.id;
        final updated = await _repo.getBookingById(bid);

        setState(() {
          _message = msg;
          _isWarning = false;
          _isError = false;
          _lastAction = 'check_in';
          _lastBooking = updated ?? booking;
        });

        _clearPending();
        return;
      }

      if (isOut) {
        final hasPath = (booking.checkinPhotoPath?.isNotEmpty ?? false);
        if (hasPath && !_pendingAck) {
          setState(() {
            _pendingLocalError = 'Conferma che il bagaglio è ok per continuare.';
          });
          return;
        }

        final res = await _doCheckOutInline(code: code, force: false);
        final ok = (res['ok'] == true);
        final rawMsg = res['message']?.toString();
        final requirePay = (res['require_payment'] == true) ||
            _looksLikeSupplementBlock(rawMsg);

        if (ok) {
          final bid = res['booking_id']?.toString() ?? booking.id;
          final updated = await _repo.getBookingById(bid);

          setState(() {
            _message = (res['message'] as String?) ?? 'Check-out completato.';
            _isWarning = false;
            _isError = false;
            _lastAction = 'check_out';
            _lastBooking = updated ?? booking;
          });

          _clearPending();
          return;
        }

        if (requirePay) {
          setState(() {
            _pendingNeedsPayStep = true;
            _pendingLocalError =
                _supplementHelpText(bookingCode: booking.bookingCode);
          });
          return;
        }

        setState(() {
          _pendingLocalError =
              rawMsg?.toString().trim().isNotEmpty == true
                  ? rawMsg
                  : 'Operazione non riuscita.';
        });
      }
    } catch (e) {
      setState(() {
        _pendingLocalError = 'Errore: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPayAndCheckout() async {
    if (_busy) return;
    final booking = _pendingBooking;
    final code = _pendingCode;
    if (booking == null || code == null) return;

    setState(() {
      _busy = true;
      _pendingLocalError = null;
    });

    try {
      final res = await _doCheckOutInline(code: code, force: true);
      final ok = (res['ok'] == true);
      final rawMsg = res['message']?.toString();

      if (!ok) {
        final requirePay = (res['require_payment'] == true) ||
            _looksLikeSupplementBlock(rawMsg);

        setState(() {
          _pendingNeedsPayStep = requirePay;
          _pendingLocalError = requirePay
              ? _supplementHelpText(bookingCode: booking.bookingCode)
              : (rawMsg?.trim().isNotEmpty == true ? rawMsg : 'Operazione non riuscita.');
        });
        return;
      }

      final bid = res['booking_id']?.toString() ?? booking.id;
      final updated = await _repo.getBookingById(bid);

      setState(() {
        _message = (res['message'] as String?) ?? 'Check-out completato.';
        _isWarning = false;
        _isError = false;
        _lastAction = 'check_out';
        _lastBooking = updated ?? booking;
      });

      _clearPending();
    } catch (e) {
      setState(() {
        _pendingLocalError = 'Errore: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildResultInline(ColorScheme cs) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_message == null) {
      return Text(
        'Scansiona un codice per iniziare.',
        style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
      );
    }

    IconData icon;
    Color color;

    if (_isError) {
      icon = Icons.error_outline;
      color = cs.error;
    } else if (_isWarning) {
      icon = Icons.warning_amber_rounded;
      color = cs.tertiary;
    } else {
      icon = Icons.check_circle_outline;
      color = cs.primary;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _message!,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
    );
  }

  Widget _kvRow(BuildContext context, {required String k, required String v}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              k,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iosToggleRow(
    BuildContext context, {
    required bool value,
    required String title,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final icon = value
        ? Icons.check_box_rounded
        : Icons.check_box_outline_blank_rounded;

    return InkWell(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: value ? cs.primary : cs.onSurface.withOpacity(0.35),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingBookingBox(BuildContext context, PartnerBooking b) {
    return _iosSection(
      context,
      children: [
        _kvRow(context, k: 'Codice', v: b.bookingCode),
        _thinDivider(context),
        _kvRow(context, k: 'Cliente', v: '${b.firstName} ${b.lastName}'),
        _thinDivider(context),
        _kvRow(
          context,
          k: 'Bagagli',
          v: '${b.bagsS}S  ${b.bagsM}M  ${b.bagsL}L',
        ),
        _thinDivider(context),
        _kvRow(context, k: 'Dropoff', v: _fmt(b.plannedDropoffAtLocal)),
        _thinDivider(context),
        _kvRow(context, k: 'Pickup', v: _fmt(b.plannedPickupAtLocal)),
      ],
    );
  }

  Widget _inlineBanner(BuildContext context, String text, {required bool warning}) {
    final cs = Theme.of(context).colorScheme;
    final bg = warning
        ? cs.tertiaryContainer.withOpacity(0.55)
        : cs.errorContainer.withOpacity(0.65);
    final fg = warning ? cs.onTertiaryContainer : cs.onErrorContainer;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _checkoutIssueHelp(BuildContext context, PartnerBooking booking) {
    final cs = Theme.of(context).colorScheme;

    Future<void> copyText(String text, String toast) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
    }

    return _iosSection(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Se non è tutto ok', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                '• Fai uno screen di questa schermata\n'
                '• Scatta una foto ai bagagli\n'
                '• Contattaci prima di concludere il check-out',
                style: TextStyle(color: cs.onSurface.withOpacity(0.78)),
              ),
              const SizedBox(height: 10),
              Text(
                'Social: $kSupportSocial',
                style: TextStyle(color: cs.onSurface.withOpacity(0.72)),
              ),
              const SizedBox(height: 2),
              Text(
                'Email: $kSupportEmail',
                style: TextStyle(color: cs.onSurface.withOpacity(0.72)),
              ),
            ],
          ),
        ),
        _thinDivider(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => copyText(kSupportEmail, 'Email copiata'),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Copia email'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => copyText(booking.bookingCode, 'Codice copiato'),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copia codice'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingFlow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = _pendingBooking;
    final action = _pendingAction;
    final preview = _pendingPreview;

    if (b == null || action == null || preview == null) {
      return const SizedBox.shrink();
    }

    final isIn = action == 'check_in';
    final isOut = action == 'check_out';

    final bool checkinAllowed = (preview['checkin_allowed'] as bool?) ?? true;
    final DateTime? notBefore = preview['not_before'] != null
        ? DateTime.parse(preview['not_before'].toString()).toLocal()
        : null;

    final title = isIn ? 'Conferma check-in' : (isOut ? 'Conferma check-out' : 'Conferma');
    final hasPath = (b.checkinPhotoPath?.isNotEmpty ?? false);

    Widget bannerEarly() {
      if (!isIn || checkinAllowed) return const SizedBox.shrink();
      final when = notBefore != null ? _fmt(notBefore) : 'più tardi';
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
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

    Widget checkinPhotoBox() {
      if (!isIn) return const SizedBox.shrink();

      return _iosSection(
        context,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text('Foto bagaglio', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          _thinDivider(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_lostDataError != null) ...[
                  Text(
                    'Nota: recupero foto non riuscito ($_lostDataError).',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_pendingPhotoFile == null && _recoveredPhotoFile != null) ...[
                  Text(
                    'Foto recuperata (da camera/galeria). Puoi usarla per completare il check-in.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      _recoveredPhotoFile!,
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
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _pendingPhotoFile = _recoveredPhotoFile;
                                    _recoveredPhotoFile = null;
                                    _pendingLocalError = null;
                                  }),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Usa questa foto'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _recoveredPhotoFile = null;
                                  }),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Scarta'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _thinDivider(context),
                  const SizedBox(height: 12),
                ],

                if (_pendingPhotoFile == null) ...[
                  Text(
                    'Scatta o carica una foto del bagaglio prima di confermare.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pickPendingPhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Scatta'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pickPendingPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Carica'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      _pendingPhotoFile!,
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
                          onPressed: _busy ? null : () => _pickPendingPhoto(ImageSource.camera),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Riscatta'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pickPendingPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Sostituisci'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    Widget checkoutPhotoBox() {
      if (!isOut) return const SizedBox.shrink();

      if (!hasPath) {
        return _iosSection(
          context,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text('Foto al check-in', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            _thinDivider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'Nessuna foto check-in associata.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
              ),
            ),
          ],
        );
      }

      return _iosSection(
        context,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text('Foto al check-in', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          _thinDivider(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: FutureBuilder<String?>(
              future: _signedUrlForBooking(b),
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
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    url,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
          _thinDivider(context),
          _iosToggleRow(
            context,
            value: _pendingAck,
            title: 'Confermo che il bagaglio è ok e procedo col check-out',
            onTap: () => setState(() => _pendingAck = !_pendingAck),
          ),
        ],
      );
    }

    final bool canConfirm = isIn
        ? (checkinAllowed && (_pendingPhotoFile != null || _recoveredPhotoFile != null) && !_busy)
        : (isOut ? ((!hasPath || _pendingAck) && !_busy) : false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        _pendingBookingBox(context, b),
        bannerEarly(),
        const SizedBox(height: 12),

        if (isIn) ...[
          checkinPhotoBox(),
          const SizedBox(height: 12),
        ],

        if (isOut) ...[
          checkoutPhotoBox(),
          const SizedBox(height: 12),
          _checkoutIssueHelp(context, b),
          const SizedBox(height: 12),
        ],

        if (_pendingLocalError != null) _inlineBanner(
          context,
          _pendingLocalError!,
          warning: _pendingNeedsPayStep,
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _clearPending,
                child: const Text('Annulla'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: canConfirm ? _confirmPending : null,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isIn ? 'Conferma check-in' : 'Conferma check-out'),
              ),
            ),
          ],
        ),

/*
        if (isOut && _pendingNeedsPayStep) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _confirmPayAndCheckout,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Conferma pagamento'),
            ),
          ),
        ],  */
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      drawer: const PartnerDrawer(),
      appBar: AppBar(
        title: const Text("Scanner / Codici"),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.onPrimary.withOpacity(0.12)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          Text(
            'Scanner',
            style: (tt.titleLarge ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scansiona un QR o inserisci un codice. Conferma check-in/check-out direttamente qui.',
            style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 14),

          _iosSection(
            context,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Text('Operazioni', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              _thinDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _openScanner,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scansiona QR'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _openManualDialog,
                        icon: const Icon(Icons.keyboard),
                        label: const Text('Inserisci codice'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _iosSection(
            context,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Text('Operazione corrente', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              _thinDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_pendingBooking != null && _pendingAction != null) ...[
                      _buildPendingFlow(context),
                      const SizedBox(height: 12),
                      _thinDivider(context),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Esito',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildResultInline(cs),

                    if (_lastBooking != null) ...[
                      const SizedBox(height: 12),
                      _thinDivider(context),
                      const SizedBox(height: 12),
                      Text(
                        'Dettagli prenotazione',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _pendingBookingBox(context, _lastBooking!),

                      if (_lastAction == 'check_in' &&
                          !_isError &&
                          _lastBooking!.checkinPhotoPath != null &&
                          _lastBooking!.checkinPhotoPath!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Foto check-in',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FutureBuilder<String?>(
                          future: _signedUrlForBooking(_lastBooking!),
                          builder: (ctx, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const SizedBox(
                                height: 160,
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final url = snap.data;
                            if (url == null) {
                              return Text(
                                'Foto non disponibile.',
                                style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(14),
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
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

//BD29DE336FF3  check out da fare
//BD765D15E529 check in tra tanto
//BD567AA0088E check in ora
//BDCAA24D8B66 supplemento da pagare
