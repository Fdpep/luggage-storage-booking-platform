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

  // Step corrente: 0 = contatto, 1 = bagagli, 2 = riepilogo
  int _step = 0;
  bool _busy = false;

  // CONTATTO
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // campi per disponibilità
  PartnerAvailability? _availability;
  bool _loadingAvailability = true;

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

  void _nextStep() {
    if (_step == 0) {
      // Valida form contatto
      if (!(_formContactKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      // Deve esserci almeno 1 bagaglio
      if (_bagsS + _bagsM + _bagsL <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno un bagaglio.')),
        );
        return;
      }
      setState(() => _step = 2);
    }
  }


  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final client = Supabase.instance.client;
    final repo = PartnerBookingRepo(client);

    try {
      final av = await repo.getPartnerAvailability(widget.partner.id);
      if (!mounted) return;
      setState(() {
        _availability = av;
        _loadingAvailability = false;
      });
    } catch (e, st) {
      debugPrint('Errore caricando disponibilità: $e\n$st');
      if (!mounted) return;
      setState(() {
        _availability = null;
        _loadingAvailability = false;
      });
    }
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

      // 2) Controllo disponibilità in tempo reale
      final availability =
          await repo.getPartnerAvailability(widget.partner.id);

      final totalRequested = _bagsS + _bagsM + _bagsL;
      final errors = <String>[];

      final bool hasPerSizeCapacity =
          (availability.capacityS +
                  availability.capacityM +
                  availability.capacityL) >
              0;

      // Controllo per taglia solo se il partner ha configurato capacità S/M/L
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

      // In ogni caso controlliamo anche il totale, se definito
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
                    'Per questa attività non ci sono abbastanza posti disponibili per i bagagli selezionati.',
                  ),
                  const SizedBox(height: 8),
                  ...errors.map(
                    (e) => Text('• $e'),
                  ),
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
    final steps = ['Contatto', 'Bagagli', 'Riepilogo'];

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
        return _buildBagsForm();
      case 2:
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
                    if (_step < 2) {
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
                : Text(_step < 2 ? 'Avanti' : 'Conferma prenotazione'),
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
