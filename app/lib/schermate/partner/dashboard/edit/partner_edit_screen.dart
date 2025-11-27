import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';

import 'package:flutter/services.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';



/// Schermata per permettere al Partner di modificare la scheda del locale:
/// - nome / indirizzo
/// - descrizione breve
/// - telefono
/// - regole deposito
/// - orari di apertura (testo libero, salvato in opening_hours["text"])
/// - capacità massima per taglia (S/M/L) + totale (derivato)
/// - prezzi
/// - stato disponibilità (attivo / sospeso)
class PartnerEditScreen extends StatefulWidget {
  const PartnerEditScreen({super.key});

  @override
  State<PartnerEditScreen> createState() => _PartnerEditScreenState();
}

//modello locale di orari 

class OpeningInterval {
  final TimeOfDay open;
  final TimeOfDay close;

  OpeningInterval({required this.open, required this.close});

  Map<String, dynamic> toJson() => {
    "open": "${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}",
    "close": "${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}",
  };

  static OpeningInterval? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    TimeOfDay parse(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    return OpeningInterval(
      open: parse(json['open']),
      close: parse(json['close']),
    );
  }
}

//editor orari 

class OpeningHoursEditor extends StatefulWidget {
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const OpeningHoursEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<OpeningHoursEditor> createState() => _OpeningHoursEditorState();
}

class _OpeningHoursEditorState extends State<OpeningHoursEditor> {
  late Map<String, List<OpeningInterval>> _week;

  static const days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  static const labels = {
    "mon": "Lunedì",
    "tue": "Martedì",
    "wed": "Mercoledì",
    "thu": "Giovedì",
    "fri": "Venerdì",
    "sat": "Sabato",
    "sun": "Domenica",
  };

  @override
  void initState() {
    super.initState();
    _week = {};
    for (final d in days) {
      final list = widget.initialValue?[d] as List<dynamic>? ?? [];
      _week[d] = list
          .map((j) => OpeningInterval.fromJson(j as Map<String, dynamic>)!)
          .toList();
    }
  }

  void _addInterval(String day) async {
    final interval = await showDialog<OpeningInterval>(
      context: context,
      builder: (_) => _EditIntervalDialog(),
    );
    if (interval != null) {
      setState(() => _week[day]!.add(interval));
      widget.onChanged(_serialize());
    }
  }

  Map<String, dynamic> _serialize() {
    final map = <String, dynamic>{};
    for (final d in days) {
      map[d] = _week[d]!.map((i) => i.toJson()).toList();
    }
    return map;
  }

  void _removeInterval(String day, int index) {
    setState(() => _week[day]!.removeAt(index));
    widget.onChanged(_serialize());
  }

  void _copyToAll(String day) {
    final base = _week[day]!;
    setState(() {
      for (final d in days) {
        if (d != day) {
          _week[d] = List.from(base);
        }
      }
    });
    widget.onChanged(_serialize());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Orari di apertura", style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...days.map((day) {
          final intervals = _week[day]!;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[day]!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        onPressed: intervals.isEmpty
                            ? null
                            : () => _copyToAll(day),
                        tooltip: "Copia su tutti i giorni",
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _addInterval(day),
                      ),
                    ],
                  ),
                  if (intervals.isEmpty)
                    const Text("Chiuso"),
                  ...List.generate(intervals.length, (i) {
                    final intv = intervals[i];
                    return ListTile(
                      title: Text(
                          "${intv.open.format(context)} – ${intv.close.format(context)}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeInterval(day, i),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

//modifica intervallo

class _EditIntervalDialog extends StatefulWidget {
  @override
  State<_EditIntervalDialog> createState() => _EditIntervalDialogState();
}

class _EditIntervalDialogState extends State<_EditIntervalDialog> {
  TimeOfDay? open;
  TimeOfDay? close;

  Future<void> _pickOpen() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) setState(() => open = t);
  }

  Future<void> _pickClose() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) setState(() => close = t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Aggiungi intervallo"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: _pickOpen,
            child: Text(open == null ? "Ora apertura" : "Apertura: ${open!.format(context)}"),
          ),
          ElevatedButton(
            onPressed: _pickClose,
            child: Text(close == null ? "Ora chiusura" : "Chiusura: ${close!.format(context)}"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annulla"),
        ),
        ElevatedButton(
          onPressed: (open != null && close != null)
              ? () {
                  if (open!.hour > close!.hour ||
                      (open!.hour == close!.hour && open!.minute >= close!.minute)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("L'ora di chiusura deve essere dopo l'apertura")),
                    );
                    return;
                  }
                  Navigator.pop(context, OpeningInterval(open: open!, close: close!));
                }
              : null,
          child: const Text("Salva"),
        ),
      ],
    );
  }
}


class _PartnerEditScreenState extends State<PartnerEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _repo = PartnerRepo(Supabase.instance.client);

  Partner? _partner;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Controller dei campi testo
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();

  // Orario giornaliero con possibile pausa
  TimeOfDay? _open1;
  TimeOfDay? _close1;
  TimeOfDay? _open2;
  TimeOfDay? _close2;

  // Capacità per taglia
  final _capacitySCtrl = TextEditingController();
  final _capacityMCtrl = TextEditingController();
  final _capacityLCtrl = TextEditingController();

  final _price2hCtrl = TextEditingController();
  final _pricePerDayCtrl = TextEditingController();

  Map<String, dynamic>? _openingHoursStructured;
  bool _isActive = true;
  bool _hasFutureBookings = false;

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _rulesCtrl.dispose();
    _capacitySCtrl.dispose();
    _capacityMCtrl.dispose();
    _capacityLCtrl.dispose();
    _price2hCtrl.dispose();
    _pricePerDayCtrl.dispose();
    super.dispose();
  }

  /// Carica il partner associato all'utente corrente
  /// e popola i campi del form.
  Future<void> _loadPartner() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final partner = await _repo.getMyPartner();

      if (!mounted) return;

      if (partner == null) {
        setState(() {
          _loading = false;
          _partner = null;
          _error = 'Nessun locale associato a questo account.';
        });
        return;
      }

      _partner = partner;

      _nameCtrl.text = partner.name;
      _addressCtrl.text = partner.address ?? '';
      _descCtrl.text = partner.description ?? '';
      _phoneCtrl.text = partner.phone ?? '';
      _rulesCtrl.text = partner.rules ?? '';

      // Capacità S/M/L con fallback su capacity totale
      int capS = partner.capacityS;
      int capM = partner.capacityM;
      int capL = partner.capacityL;

      if (capS == 0 && capM == 0 && capL == 0 && partner.capacity > 0) {
        capM = partner.capacity;
      }

      _capacitySCtrl.text = capS.toString();
      _capacityMCtrl.text = capM.toString();
      _capacityLCtrl.text = capL.toString();

      if (partner.price2h != null) {
        _price2hCtrl.text =
            partner.price2h!.toStringAsFixed(2).replaceAll('.', ',');
      }
      if (partner.pricePerDay != null) {
        _pricePerDayCtrl.text =
            partner.pricePerDay!.toStringAsFixed(2).replaceAll('.', ',');
      }

      // Orari apertura strutturati
      final opening = partner.openingHours;
      if (opening != null && opening['type'] == 'daily_with_break') {
        _open1 = _parseTimeOfDay(opening['open_1'] as String?);
        _close1 = _parseTimeOfDay(opening['close_1'] as String?);
        _open2 = _parseTimeOfDay(opening['open_2'] as String?);
        _close2 = _parseTimeOfDay(opening['close_2'] as String?);
      } else {
        // Fallback: 08:00 - 20:00 senza pausa
        _open1 = const TimeOfDay(hour: 8, minute: 0);
        _close1 = const TimeOfDay(hour: 20, minute: 0);
        _open2 = null;
        _close2 = null;
      }

      _isActive = partner.isActive;

      // Controllo se ci sono prenotazioni future
      final bookingRepo = PartnerBookingRepo(Supabase.instance.client);
      final hasFuture =
          await bookingRepo.hasActiveFutureBookingsForPartner(partner.id);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = null;
        _hasFutureBookings = hasFuture;
      });
    } catch (e, st) {
      debugPrint('Errore _loadPartner: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore durante il caricamento del locale.';
      });
    }
  }

  /// Converte una stringa in double, gestendo anche la virgola.
  double? _parsePrice(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final normalized = t.replaceAll(',', '.');
    return double.tryParse(normalized);
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

  String _timeToString(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }


  /// Salva le modifiche su Supabase usando PartnerRepo.updateBasics.
  Future<void> _save() async {
    if (_partner == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final sText = _capacitySCtrl.text.trim();
    final mText = _capacityMCtrl.text.trim();
    final lText = _capacityLCtrl.text.trim();

    final capS = int.tryParse(sText) ?? 0;
    final capM = int.tryParse(mText) ?? 0;
    final capL = int.tryParse(lText) ?? 0;

    if (capS < 0 || capM < 0 || capL < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le capacità devono essere numeri ≥ 0.'),
        ),
      );
      return;
    }

    final totalCapacity = capS + capM + capL;
    if (totalCapacity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Imposta almeno 1 posto totale tra S / M / L.',
          ),
        ),
      );
      return;
    }

    final price2h = _parsePrice(_price2hCtrl.text);
    final pricePerDay = _parsePrice(_pricePerDayCtrl.text);

    // Orari di apertura strutturati
    Map<String, dynamic>? openingHours;
    if (_open1 != null && _close1 != null) {
      openingHours = {
        'type': 'daily_with_break',
        'open_1': _timeToString(_open1!),
        'close_1': _timeToString(_close1!),
      };
      if (_open2 != null && _close2 != null) {
        openingHours['open_2'] = _timeToString(_open2!);
        openingHours['close_2'] = _timeToString(_close2!);
      }
    }

    final canEditCapacityAndHours = !_hasFutureBookings;

    setState(() {
      _saving = true;
    });

    try {
      await _repo.updateBasics(
        partnerId: _partner!.id,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        capacity: canEditCapacityAndHours ? totalCapacity : null,
        capacityS: canEditCapacityAndHours ? capS : null,
        capacityM: canEditCapacityAndHours ? capM : null,
        capacityL: canEditCapacityAndHours ? capL : null,
        price2h: price2h,
        pricePerDay: pricePerDay,
        isActive: _isActive,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        rules: _rulesCtrl.text.trim().isEmpty ? null : _rulesCtrl.text.trim(),
        openingHours: canEditCapacityAndHours ? openingHours : null,
      );

      if (!mounted) return;

      if (_hasFutureBookings) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dati salvati. Orari e capacità non sono stati modificati perché ci sono prenotazioni future.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scheda locale aggiornata.')),
        );
      }

      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint('Errore salvataggio partner: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante il salvataggio. Riprova.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifica locale')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_partner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Modifica locale')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error ??
                  'Nessun locale trovato. Completa prima la registrazione dell’attività.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Modifica locale')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1) Nome attività
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome attività',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Inserisci il nome dell’attività';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // 2) Indirizzo
                TextFormField(
                  controller: _addressCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo',
                    hintText: 'Via / Piazza, numero civico, città',
                    border: OutlineInputBorder(),
                    helperText:
                        'Per modificare l\'indirizzo contatta il supporto BagDrop via email.',
                  ),
                  onTap: () {
                    // Messaggio veloce: l’indirizzo non è modificabile da qui
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Per modificare l\'indirizzo del locale scrivi a support@bagdrop.app',
                        ),
                      ),
                    );
                  },
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Indirizzo non disponibile: contatta il supporto.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),
                Text(
                  'Vuoi aggiornare l\'indirizzo del locale?\n'
                  'Scrivi a support@bagdrop.app indicando il nuovo indirizzo.',
                  style: theme.textTheme.bodySmall,
                ),

                const SizedBox(height: 12),

                // 3) Descrizione breve
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrizione breve',
                    hintText:
                        'Es. Bar accogliente vicino al Duomo, deposito sicuro...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 4) Telefono
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    hintText: 'Es. +39 333 1234567',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),

                // 5) Regole deposito
                TextFormField(
                  controller: _rulesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Regole deposito',
                    hintText:
                        'Es. Max 25kg a bagaglio, no oggetti di valore, no liquidi...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // 6) Orari di apertura (giornalieri con eventuale pausa)
                Text(
                  'Orari di apertura (tutti i giorni)',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                if (_hasFutureBookings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Ci sono prenotazioni future: non puoi modificare orari e capacità finché non saranno concluse.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasFutureBookings
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _open1 ?? const TimeOfDay(hour: 8, minute: 0),
                                );
                                if (picked != null) {
                                  setState(() => _open1 = picked);
                                }
                              },
                        child: Text(
                          _open1 == null
                              ? 'Apertura mattina'
                              : 'Apre: ${_open1!.format(context)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasFutureBookings
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _close1 ?? const TimeOfDay(hour: 13, minute: 0),
                                );
                                if (picked != null) {
                                  setState(() => _close1 = picked);
                                }
                              },
                        child: Text(
                          _close1 == null
                              ? 'Chiusura mattina'
                              : 'Chiude: ${_close1!.format(context)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasFutureBookings
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _open2 ?? const TimeOfDay(hour: 15, minute: 0),
                                );
                                if (picked != null) {
                                  setState(() => _open2 = picked);
                                }
                              },
                        child: Text(
                          _open2 == null
                              ? 'Apertura pomeriggio (opz.)'
                              : 'Apre: ${_open2!.format(context)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasFutureBookings
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _close2 ?? const TimeOfDay(hour: 20, minute: 0),
                                );
                                if (picked != null) {
                                  setState(() => _close2 = picked);
                                }
                              },
                        child: Text(
                          _close2 == null
                              ? 'Chiusura pom. (opz.)'
                              : 'Chiude: ${_close2!.format(context)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),


                // 7) Capacità per taglia
                Text(
                  'Capacità massima per taglia bagagli',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacitySCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli SMALL (S)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacityMCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli MEDIUM (M)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _capacityLCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bagagli LARGE (L)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_hasFutureBookings,
                ),
                const SizedBox(height: 12),

                // 8) Prezzi
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price2hCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Prezzo 2h (€)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pricePerDayCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Prezzo / giorno (€)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 9) Stato disponibilità
                SwitchListTile(
                  title: const Text('Locale attivo su BagDrop'),
                  subtitle: const Text(
                    'Disattiva per sospendere temporaneamente le prenotazioni.',
                  ),
                  value: _isActive,
                  onChanged: (v) {
                    setState(() {
                      _isActive = v;
                    });
                  },
                ),

                const SizedBox(height: 16),
                Text(
                  'Queste informazioni saranno visibili agli utenti nella scheda del locale (mappa + dettaglio).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salva modifiche'),
            ),
          ),
        ),
      ),
    );
  }
}
