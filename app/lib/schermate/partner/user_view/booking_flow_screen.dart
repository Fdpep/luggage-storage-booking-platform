// è la pagina che vede l'utente cliccando il tasto prenota ora dalla scheda dell'attività

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';

class BookingFlowScreen extends StatefulWidget {
  final Partner partner;

  const BookingFlowScreen({super.key, required this.partner});

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final _formContactKey = GlobalKey<FormState>();

  // Step corrente:
  // 0 = contatto
  // 1 = data + orario
  // 2 = bagagli
  // 3 = riepilogo
  int _step = 0;
  bool _busy = false;

  // CONTATTO
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // DATA / ORARIO
  DateTime? _selectedDate;
  bool _fullDay = true;
  TimeOfDay? _slotStart;
  TimeOfDay? _slotEnd;
  _TimeSlot? _selectedSlot; 

  PartnerAvailability? _availability;
  bool _loadingAvailability = false;

  // BAGAGLI
  int _bagsS = 0;
  int _bagsM = 0;
  int _bagsL = 0;


  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_step == 0) {
      // Valida form contatto
      if (!(_formContactKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Data + orario
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona un giorno.')),
        );
        return;
      }

      if (!_fullDay && _slotStart == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona una fascia oraria di 3 ore.')),
        );
        return;
      }

      await _loadAvailabilityForSelection();
      if (!mounted) return;
      if (_availability == null) {
        // errore già mostrato nello snackbar
        return;
      }

      setState(() => _step = 2);
    } else if (_step == 2) {
      // Deve esserci almeno 1 bagaglio
      if (_bagsS + _bagsM + _bagsL <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno un bagaglio.')),
        );
        return;
      }
      setState(() => _step = 3);
    }
  }


  @override
  void initState() {
    super.initState();
    // La disponibilità verrà caricata solo dopo che l’utente ha scelto
    // data + orario.
  }


  Future<void> _loadAvailabilityForSelection() async {
    if (_selectedDate == null) return;

    final startStr = _selectedStartTimeString;
    final endStr = _selectedEndTimeString;

    setState(() {
      _loadingAvailability = true;
      _availability = null;
    });

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final av = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: _selectedDate!,
        startTime: startStr,
        endTime: endStr,
      );

      if (!mounted) return;
      setState(() {
        _availability = av;
        _loadingAvailability = false;
      });
    } catch (e, st) {
      debugPrint('Errore caricando disponibilità per intervallo: $e\n$st');
      if (!mounted) return;
      setState(() {
        _availability = null;
        _loadingAvailability = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossibile calcolare la disponibilità per l\'orario scelto. Riprova.',
          ),
        ),
      );
    }
  }

  String get _selectedStartTimeString {
    if (_fullDay || _slotStart == null) return '00:00';
    return _formatTimeForApi(_slotStart!);
  }

  String get _selectedEndTimeString {
    if (_fullDay || _slotEnd == null) return '23:59';
    return _formatTimeForApi(_slotEnd!);
  }

  String _formatTimeForApi(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatTimeDisplay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  List<_TimeSlot> _buildTimeSlots() {
    final opening = widget.partner.openingHours;

    // Default 08:00–20:00 senza pausa
    TimeOfDay open1 = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay close1 = const TimeOfDay(hour: 20, minute: 0);
    TimeOfDay? open2;
    TimeOfDay? close2;

    if (opening != null && opening['type'] == 'daily_with_break') {
      final o1 = _parseTimeOfDay(opening['open_1'] as String?);
      final c1 = _parseTimeOfDay(opening['close_1'] as String?);
      final o2 = _parseTimeOfDay(opening['open_2'] as String?);
      final c2 = _parseTimeOfDay(opening['close_2'] as String?);

      if (o1 != null && c1 != null) {
        open1 = o1;
        close1 = c1;
      }
      if (o2 != null && c2 != null) {
        open2 = o2;
        close2 = c2;
      }
    }

    final slots = <_TimeSlot>[];

    void addSlots(TimeOfDay from, TimeOfDay to) {
      const slotMinutes = 180;
      var startMinutes = from.hour * 60 + from.minute;
      final limit = to.hour * 60 + to.minute;

      while (true) {
        final end = startMinutes + slotMinutes;
        if (end > limit) break;
        final s = TimeOfDay(
          hour: startMinutes ~/ 60,
          minute: startMinutes % 60,
        );
        final e = TimeOfDay(
          hour: end ~/ 60,
          minute: end % 60,
        );
        slots.add(_TimeSlot(start: s, end: e));
        startMinutes = end;
      }
    }

    addSlots(open1, close1);
    if (open2 != null && close2 != null) {
      addSlots(open2!, close2!);
    }

    // Se per qualche motivo non generiamo slot, fallback 08–20
    if (slots.isEmpty) {
      const fallbackFrom = TimeOfDay(hour: 8, minute: 0);
      const fallbackTo = TimeOfDay(hour: 20, minute: 0);
      const slotMinutes = 180;
      var startMinutes =
          fallbackFrom.hour * 60 + fallbackFrom.minute;
      final limit = fallbackTo.hour * 60 + fallbackTo.minute;

      while (true) {
        final end = startMinutes + slotMinutes;
        if (end > limit) break;
        final s = TimeOfDay(
          hour: startMinutes ~/ 60,
          minute: startMinutes % 60,
        );
        final e = TimeOfDay(
          hour: end ~/ 60,
          minute: end % 60,
        );
        slots.add(_TimeSlot(start: s, end: e));
        startMinutes = end;
      }
    }

    return slots;
  }



  void _prevStep() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _confirmBooking() async {
    if (_busy) return;
    setState(() => _busy = true);

    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      // 0) Controllo che il partner sia prenotabile
      if (!(widget.partner.isApproved)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Questo locale non è al momento prenotabile. Riprova più tardi.',
            ),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // 1) Safety: data + orario ancora validi?
      if (_selectedDate == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona una data.')),
        );
        setState(() => _busy = false);
        return;
      }
      if (!_fullDay && _slotStart == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleziona una fascia oraria di 3 ore.'),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      final startStr = _selectedStartTimeString;
      final endStr = _selectedEndTimeString;

      // 2) Controllo disponibilità per intervallo specifico
      final availability = await repo.getPartnerAvailabilityForInterval(
        partnerId: widget.partner.id,
        bookingDate: _selectedDate!,
        startTime: startStr,
        endTime: endStr,
      );

      final totalRequested = _bagsS + _bagsM + _bagsL;
      final errors = <String>[];

      final bool hasPerSizeCapacity =
          (availability.capacityS +
                  availability.capacityM +
                  availability.capacityL) >
              0;

      if (hasPerSizeCapacity) {
        if (_bagsS > 0 && _bagsS > availability.availableS) {
          errors.add(
            'Small (S): disponibili ${availability.availableS}, richiesti $_bagsS.',
          );
        }
        if (_bagsM > 0 && _bagsM > availability.availableM) {
          errors.add(
            'Medium (M): disponibili ${availability.availableM}, richiesti $_bagsM.',
          );
        }
        if (_bagsL > 0 && _bagsL > availability.availableL) {
          errors.add(
            'Large (L): disponibili ${availability.availableL}, richiesti $_bagsL.',
          );
        }
      }

      if (availability.capacityTotal > 0 &&
          totalRequested > availability.availableTotal) {
        errors.add(
          'Totale bagagli: disponibili ${availability.availableTotal}, richiesti $totalRequested.',
        );
      }

      if (errors.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Disponibilità insufficiente'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Per questa attività non ci sono abbastanza posti disponibili per i bagagli selezionati in questo orario.',
                  ),
                  const SizedBox(height: 8),
                  ...errors.map((e) => Text('• $e')),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Ok'),
                ),
              ],
            );
          },
        );
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }

      // 3) Se tutto ok → creiamo la prenotazione
      await repo.createBooking(
        partnerId: widget.partner.id,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        bagsS: _bagsS,
        bagsM: _bagsM,
        bagsL: _bagsL,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        bookingDate: _selectedDate!,
        startTime: startStr,
        endTime: endStr,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prenotazione creata! (Pagamento/QR in arrivo 😉)'),
        ),
      );

      Navigator.of(context).pop(); // torniamo al dettaglio partner
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore autenticazione: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imprevisto durante la prenotazione: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Prenota • ${widget.partner.name}'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStepHeader(),
              const SizedBox(height: 16),
              Expanded(child: _buildStepBody()),
              const SizedBox(height: 16),
              _buildBottomButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
    final cs = Theme.of(context).colorScheme;
    final steps = ['Contatto', 'Data e orario', 'Bagagli', 'Riepilogo'];

    return Row(
      children: List.generate(steps.length, (index) {
        final active = index == _step;
        final done = index < _step;

        Color fill;
        if (active) {
          fill = cs.primary;
        } else if (done) {
          fill = cs.primary.withOpacity(0.5);
        } else {
          fill = cs.surfaceVariant;
        }

        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: fill,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active || done ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 12,
                  color: active
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(done ? 0.8 : 0.6),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildContactForm();
      case 1:
        return _buildDateTimeForm();
      case 2:
        return _buildBagsForm();
      case 3:
        return _buildSummary();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContactForm() {
    return Form(
      key: _formContactKey,
      child: ListView(
        children: [
          Text(
            'Dati di contatto',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),

          // Nome
          TextFormField(
            controller: _firstNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome',
            ),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) {
                return 'Inserisci il nome';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Cognome
          TextFormField(
            controller: _lastNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Cognome',
            ),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) {
                return 'Inserisci il cognome';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Telefono
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Telefono',
              hintText: '+39 ...',
            ),
            keyboardType: TextInputType.phone,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) {
                return 'Inserisci un numero di telefono';
              }
              // Teniamo solo le cifre
              final digitsOnly = t.replaceAll(RegExp(r'[^0-9]'), '');
              if (digitsOnly.length != 10) {
                return 'Il numero deve avere esattamente 10 cifre';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Email
          TextFormField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'E-mail',
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Inserisci un’e-mail';
              if (!t.contains('@')) return 'E-mail non valida';
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // Note
          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Note per il locale (opzionale)',
              hintText: 'Es. Arrivo in treno alle 10:30…',
            ),
            maxLines: 3,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeForm() {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final slots = _buildTimeSlots();

    String dateLabel;
    if (_selectedDate == null) {
      dateLabel = 'Seleziona una data';
    } else {
      dateLabel =
          '${_selectedDate!.day.toString().padLeft(2, '0')}/'
          '${_selectedDate!.month.toString().padLeft(2, '0')}/'
          '${_selectedDate!.year}';
    }

    String slotLabel;
    if (_fullDay) {
      slotLabel = 'Tutto il giorno';
    } else if (_slotStart != null && _slotEnd != null) {
      slotLabel =
          '${_formatTimeDisplay(_slotStart!)} - ${_formatTimeDisplay(_slotEnd!)}';
    } else {
      slotLabel = 'Seleziona fascia 3h';
    }

    return ListView(
      children: [
        Text(
          'Quando vuoi lasciare i bagagli?',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),

        // Data
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Giorno'),
          subtitle: Text(dateLabel),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final now = DateTime.now();
            final initialDate = _selectedDate ?? now;
            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 1),
            );
            if (picked != null) {
              setState(() {
                _selectedDate = DateTime(picked.year, picked.month, picked.day);
                _selectedSlot = null;
                _slotStart = null;
                _slotEnd = null;
              });
            }
          },
        ),
        const SizedBox(height: 12),

        // Toggle full day vs 3h
        Text(
          'Durata',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Tutto il giorno'),
              selected: _fullDay,
              onSelected: (v) {
                if (!v) return;
                setState(() {
                  _fullDay = true;
                  _slotStart = null;
                  _slotEnd = null;
                  _selectedSlot = null;   // <--- AGGIUNGI
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Fascia di 3 ore'),
              selected: !_fullDay,
              onSelected: (v) {
                if (!v) return;
                setState(() {
                  _fullDay = false;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (!_fullDay) ...[
          Text(
            'Seleziona una fascia oraria di 3 ore',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<_TimeSlot>(
            value: _selectedSlot,
            items: slots
                .map(
                  (slot) => DropdownMenuItem<_TimeSlot>(
                    value: slot,
                    child: Text(slot.toLabel(_formatTimeDisplay)),
                  ),
                )
                .toList(),
            onChanged: (slot) {
              if (slot == null) return;
              setState(() {
                _selectedSlot = slot;
                _slotStart = slot.start;
                _slotEnd = slot.end;
              });
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Fascia oraria',
            ),
          ),

        ],

        const SizedBox(height: 16),
        Text(
          'Gli orari disponibili sono calcolati in base agli orari di apertura impostati dal locale.',
          style: textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }


  Widget _buildBagsForm() {
    if (_loadingAvailability) {
      return const Center(child: CircularProgressIndicator());
    }

    final av = _availability;

    int? maxS;
    int? maxM;
    int? maxL;

    if (av != null) {
      final hasPerSizeCapacity =
          (av.capacityS + av.capacityM + av.capacityL) > 0;

      if (hasPerSizeCapacity) {
        maxS = av.availableS;
        maxM = av.availableM;
        maxL = av.availableL;
      }
      // se non c'è capacità per taglia, lasciamo i max null
      // e lasciamo il controllo "di sicurezza" solo a _confirmBooking
    }

    return ListView(
      children: [
        Text(
          'Seleziona numero e dimensione dei bagagli',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (av != null) ...[
          const SizedBox(height: 4),
          Text(
            'Disponibili - S: ${av.availableS} • M: ${av.availableM} • L: ${av.availableL}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        _BagRow(
          label: 'Small (S)',
          description: 'Zainetti o trolley piccoli',
          count: _bagsS,
          max: maxS,
          onChanged: (v) => setState(() => _bagsS = v),
        ),
        const SizedBox(height: 8),
        _BagRow(
          label: 'Medium (M)',
          description: 'Trolley medi',
          count: _bagsM,
          max: maxM,
          onChanged: (v) => setState(() => _bagsM = v),
        ),
        const SizedBox(height: 8),
        _BagRow(
          label: 'Large (L)',
          description: 'Valigie grandi',
          count: _bagsL,
          max: maxL,
          onChanged: (v) => setState(() => _bagsL = v),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final totalBags = _bagsS + _bagsM + _bagsL;

    return ListView(
      children: [
        Text(
          'Riepilogo prenotazione',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.partner.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if ((widget.partner.address ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(widget.partner.address!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
                // Data e orario
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data e orario',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedDate == null
                      ? 'Non selezionata'
                      : '${_selectedDate!.day.toString().padLeft(2, '0')}/'
                        '${_selectedDate!.month.toString().padLeft(2, '0')}/'
                        '${_selectedDate!.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fullDay
                      ? 'Tutto il giorno (entro orario di apertura)'
                      : (_slotStart != null && _slotEnd != null)
                          ? '${_formatTimeDisplay(_slotStart!)} - ${_formatTimeDisplay(_slotEnd!)}'
                          : 'Orario non selezionato',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contatto',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                    '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'),
                Text(_phoneCtrl.text.trim()),
                Text(_emailCtrl.text.trim()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bagagli',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('Totale: $totalBags'),
                if (_bagsS > 0) Text('• $_bagsS × Small (S)'),
                if (_bagsM > 0) Text('• $_bagsM × Medium (M)'),
                if (_bagsL > 0) Text('• $_bagsL × Large (L)'),
              ],
            ),
          ),
        ),
        if (_notesCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Note',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(_notesCtrl.text.trim()),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Pagamento e QR code per il check-in saranno integrati in una fase successiva.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _prevStep,
              child: const Text('Indietro'),
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () {
                    if (_step < 3) {
                      _nextStep();
                    } else {
                      _confirmBooking();
                    }
                  },
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_step < 3 ? 'Avanti' : 'Conferma prenotazione'),

          ),
        ),
      ],
    );
  }
}

/// Riga per selezionare il numero di bagagli di una certa taglia.
class _BagRow extends StatelessWidget {
  final String label;
  final String description;
  final int count;
  final int? max;
  final ValueChanged<int> onChanged;

  const _BagRow({
    required this.label,
    required this.description,
    required this.count,
    required this.onChanged,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (max != null)
                    Text(
                      'Disponibili: $max',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: count > 0 ? () => onChanged(count - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$count'),
                IconButton(
                  onPressed: (max != null && count >= max!)
                      ? null
                      : () => onChanged(count + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSlot {
  final TimeOfDay start;
  final TimeOfDay end;

  const _TimeSlot({
    required this.start,
    required this.end,
  });

  String toLabel(String Function(TimeOfDay) fmt) {
    return '${fmt(start)} - ${fmt(end)}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _TimeSlot) return false;

    return start.hour == other.start.hour &&
        start.minute == other.start.minute &&
        end.hour == other.end.hour &&
        end.minute == other.end.minute;
  }

  @override
  int get hashCode =>
      start.hour.hashCode ^
      start.minute.hashCode ^ 
      end.hour.hashCode ^
      end.minute.hashCode;
}
