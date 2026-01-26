import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/services/supabase/partner_repo.dart';

import 'package:flutter/services.dart';
import 'package:BagDrop/services/supabase/partner_booking_repo.dart';
import 'package:BagDrop/widgets/opening_hours_editors.dart';

/// Schermata per permettere al Partner di modificare la scheda del locale:
/// - nome / indirizzo
/// - descrizione breve
/// - telefono
/// - regole deposito
/// - orari di apertura (JSON settimanale + eccezioni in opening_hours)
/// - capacità massima per taglia (S/M/L) + totale (derivato)
/// - prezzi
/// - stato disponibilità (attivo / sospeso)
class PartnerEditScreen extends StatefulWidget {
  const PartnerEditScreen({super.key});

  @override
  State<PartnerEditScreen> createState() => _PartnerEditScreenState();
}

//modello locale di orari

//editor orari

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

  // Capacità V2
  final _baseMCtrl = TextEditingController(text: '10');
  final _extraSCtrl = TextEditingController(text: '0');
  final _extraMCtrl = TextEditingController(text: '0');
  final _extraLCtrl = TextEditingController(text: '0');

  bool _acceptS = true;
  bool _acceptM = true;
  bool _acceptL = true;


  Map<String, dynamic>? _openingHoursStructured;
  Map<String, dynamic>? _openingExceptions;
  bool _isActive = true;
  bool _hasFutureBookings = false;

  /// Normalizza opening_hours in formato settimanale:
  /// - se è null → 08:00-20:00 tutti i giorni
  /// - se è 'daily_with_break' → stessi intervalli ogni giorno
  /// - se è 'weekly_v1' → lo lascia com'è
  /// - se è legacy (mon/tue/... senza type) → lo usa direttamente
  Map<String, dynamic> _normalizeOpeningWeekly(Map<String, dynamic>? raw) {
    const dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

    // Base: tutte le giornate "chiuse" (liste vuote)
    final result = <String, dynamic>{
      for (final d in dayKeys) d: <Map<String, dynamic>>[],
    };

    // Nessun dato -> fallback 08:00-20:00 tutti i giorni
    if (raw == null) {
      final def = OpeningInterval(
        open: const TimeOfDay(hour: 8, minute: 0),
        close: const TimeOfDay(hour: 20, minute: 0),
      ).toJson();
      for (final d in dayKeys) {
        result[d] = [def];
      }
      return result;
    }

    final type = raw['type'] as String?;

    // Già weekly_v1
    if (type == 'weekly_v1') {
      for (final d in dayKeys) {
        final list = raw[d] as List<dynamic>? ?? [];
        result[d] = list.map((e) => e as Map<String, dynamic>).toList();
      }
      return result;
    }

    // Vecchio formato daily_with_break
    if (type == 'daily_with_break') {
      final String? o1 = raw['open_1'] as String?;
      final String? c1 = raw['close_1'] as String?;
      final String? o2 = raw['open_2'] as String?;
      final String? c2 = raw['close_2'] as String?;

      final intervals = <Map<String, dynamic>>[];
      if (o1 != null && c1 != null) {
        intervals.add({'open': o1, 'close': c1});
      }
      if (o2 != null && c2 != null) {
        intervals.add({'open': o2, 'close': c2});
      }

      if (intervals.isEmpty) {
        // Nessun orario -> tutti chiusi
        return result;
      }

      for (final d in dayKeys) {
        result[d] = List<Map<String, dynamic>>.from(intervals);
      }
      return result;
    }

    // Caso legacy: trattiamo raw come weekly senza 'type'
    for (final d in dayKeys) {
      final list = raw[d] as List<dynamic>? ?? [];
      result[d] = list.map((e) => e as Map<String, dynamic>).toList();
    }
    return result;
  }

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
    _baseMCtrl.dispose();
    _extraSCtrl.dispose();
    _extraMCtrl.dispose();
    _extraLCtrl.dispose();
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

      // Capacità V2
      _baseMCtrl.text = partner.baseM.toString();
      _extraSCtrl.text = partner.extraCapacityS.toString();
      _extraMCtrl.text = partner.extraCapacityM.toString();
      _extraLCtrl.text = partner.extraCapacityL.toString();

      _acceptS = partner.acceptS;
      _acceptM = partner.acceptM;
      _acceptL = partner.acceptL;


      // Orari di apertura settimanali (weekly)
      _openingHoursStructured = _normalizeOpeningWeekly(partner.openingHours);

      // NUOVO: eccezioni calendario (se presenti nel JSON)
      final rawOpening = partner.openingHours;
      if (rawOpening != null &&
          rawOpening['exceptions'] is Map<String, dynamic>) {
        _openingExceptions = Map<String, dynamic>.from(
          rawOpening['exceptions'] as Map,
        );
      } else {
        _openingExceptions = null;
      }

      _isActive = partner.isActive;

      // Controllo se ci sono prenotazioni future
      final bookingRepo = PartnerBookingRepo(Supabase.instance.client);
      final hasFuture = await bookingRepo.hasActiveFutureBookingsForPartner(
        partner.id,
      );

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

  /// Salva le modifiche su Supabase usando PartnerRepo.updateBasics.
  Future<void> _save() async {
    if (_partner == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    int nn(String s) => (int.tryParse(s.trim()) ?? 0).clamp(0, 1000000);

    final baseM = nn(_baseMCtrl.text);
    final extraS = nn(_extraSCtrl.text);
    final extraM = nn(_extraMCtrl.text);
    final extraL = nn(_extraLCtrl.text);

    if (baseM <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci almeno 1 bagaglio M nello spazio generale.')),
      );
      return;
    }
    if (!_acceptS && !_acceptM && !_acceptL) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno una taglia (S/M/L).')),
      );
      return;
    }

    final baseCapacityU = baseM * 2;


    // Orari di apertura settimanali (weekly_v1)
    Map<String, dynamic>? openingHours;
    if (_openingHoursStructured != null) {
      openingHours = {
        'type': 'weekly_v1',
        ..._openingHoursStructured!,
        if (_openingExceptions != null) 'exceptions': _openingExceptions,
      };
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
        baseCapacityU: canEditCapacityAndHours ? baseCapacityU : null,
        extraCapacityS: canEditCapacityAndHours ? extraS : null,
        extraCapacityM: canEditCapacityAndHours ? extraM : null,
        extraCapacityL: canEditCapacityAndHours ? extraL : null,
        acceptS: canEditCapacityAndHours ? _acceptS : null,
        acceptM: canEditCapacityAndHours ? _acceptM : null,
        acceptL: canEditCapacityAndHours ? _acceptL : null,
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
        appBar: AppBar(
          centerTitle: false,
          title: const Text('Modifica scheda locale'),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_partner == null) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: const Text('Modifica scheda locale'),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
        ),
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

    // ✅ QUI il tuo scaffold “moderno” (quello che avevi messo dentro _loading)
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Modifica scheda locale'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _EditSectionCard(
                title: 'Informazioni principali',
                subtitle: 'Nome, indirizzo, descrizione e contatti',
                child: Column(
                  children: [
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

                    TextFormField(
                      controller: _addressCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Indirizzo',
                        hintText: 'Via / Piazza, numero civico, città',
                        border: OutlineInputBorder(),
                        helperText:
                            'Non modificabile da qui. Per aggiornamenti: support@bagdrop.app',
                      ),
                      onTap: () {
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

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descrizione breve',
                        hintText: 'Es. Bar vicino al Duomo, deposito sicuro…',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Telefono',
                        hintText: 'Es. +39 333 1234567',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final digitsOnly = t.replaceAll(RegExp(r'[^0-9]'), '');
                        if (digitsOnly.length < 9 || digitsOnly.length > 15) {
                          return 'Inserisci un numero di telefono valido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _EditSectionCard(
                title: 'Regole del deposito',
                subtitle: 'Cosa è consentito / non consentito',
                child: TextFormField(
                  controller: _rulesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Regole deposito',
                    hintText: 'Es. No oggetti di valore, no liquidi, max 25kg…',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ),

              const SizedBox(height: 14),

              _EditSectionCard(
                title: 'Orari di apertura',
                subtitle: 'Settimana + eccezioni (festività, chiusure)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasFutureBookings)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: _WarningBanner(
                          text:
                              'Ci sono prenotazioni future: non puoi modificare orari, capacità e '
                              'eccezioni calendario finché non saranno concluse.',
                        ),
                      ),

                    IgnorePointer(
                      ignoring: _hasFutureBookings,
                      child: Opacity(
                        opacity: _hasFutureBookings ? 0.6 : 1.0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OpeningHoursEditor(
                              initialValue: _openingHoursStructured,
                              onChanged: (value) {
                                setState(() {
                                  _openingHoursStructured = value;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            OpeningExceptionsEditor(
                              initialValue: _openingExceptions,
                              onChanged: (value) {
                                setState(() {
                                  _openingExceptions = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _EditSectionCard(
                title: 'Capacità massima per taglia',
                subtitle: 'Quanti bagagli puoi gestire contemporaneamente',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Spazio generale (bagagli M)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _baseMCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base M',
                        hintText: 'Es. 10',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_hasFutureBookings,
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      'Extra dedicati (opzionale)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _extraSCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Extra S',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            enabled: !_hasFutureBookings && _acceptS,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _extraMCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Extra M',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            enabled: !_hasFutureBookings && _acceptM,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _extraLCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Extra L',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            enabled: !_hasFutureBookings && _acceptL,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      'Accetto queste taglie',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),

                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('S'),
                          selected: _acceptS,
                          onSelected: _hasFutureBookings
                              ? null
                              : (v) => setState(() {
                                    _acceptS = v;
                                    if (!v) _extraSCtrl.text = '0';
                                  }),
                        ),
                        FilterChip(
                          label: const Text('M'),
                          selected: _acceptM,
                          onSelected: _hasFutureBookings
                              ? null
                              : (v) => setState(() {
                                    _acceptM = v;
                                    if (!v) _extraMCtrl.text = '0';
                                  }),
                        ),
                        FilterChip(
                          label: const Text('L'),
                          selected: _acceptL,
                          onSelected: _hasFutureBookings
                              ? null
                              : (v) => setState(() {
                                    _acceptL = v;
                                    if (!v) _extraLCtrl.text = '0';
                                  }),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Riepilogo calcolato (modello capacità V2 reale)
                    Builder(
                      builder: (_) {
                        int nn(String s) => (int.tryParse(s.trim()) ?? 0).clamp(0, 1000000);

                        final baseM = nn(_baseMCtrl.text);
                        final baseU = baseM * 2;

                        final exS = nn(_extraSCtrl.text);
                        final exM = nn(_extraMCtrl.text);
                        final exL = nn(_extraLCtrl.text);

                        // Capacità massime MOSTRABILI per taglia (extra + base convertito)
                        final maxS = _acceptS ? (exS + baseU) : 0;
                        final maxM = _acceptM ? (exM + (baseU ~/ 2)) : 0;
                        final maxL = _acceptL ? (exL + (baseU ~/ 4)) : 0;

                        // Totale in unità (solo informativo)
                        final totalU =
                            baseU + (exS * 1) + (exM * 2) + (exL * 4);

                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withOpacity(0.6),
                            ),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.35),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Riepilogo capacità',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '• Spazio generale: $baseM bagagli M',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (_acceptS)
                                Text('• Extra S dedicati: $exS'),
                              if (_acceptM)
                                Text('• Extra M dedicati: $exM'),
                              if (_acceptL)
                                Text('• Extra L dedicati: $exL'),
                              const SizedBox(height: 6),
                              Text(
                                'Capacità massima utilizzabile:',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'S $maxS  •  M $maxM  •  L $maxL',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _EditSectionCard(
                title: 'Prezzi',
                subtitle: 'Gestiti centralmente da BagDrop',
                child: const _InfoBanner(
                  text:
                      'I prezzi di deposito sono uguali per tutti i partner e vengono gestiti direttamente da BagDrop.',
                ),
              ),

              const SizedBox(height: 14),

              _EditSectionCard(
                title: 'Stato del locale',
                subtitle: 'Visibilità e disponibilità su BagDrop',
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Locale attivo su BagDrop'),
                  subtitle: const Text(
                    'Disattiva per sospendere temporaneamente le prenotazioni.',
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
            ],
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
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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

class _EditSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _EditSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6), width: 1),
      ),

      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: cs.onSurface.withOpacity(0.7),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withOpacity(0.35), width: 1),
      ),

      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
