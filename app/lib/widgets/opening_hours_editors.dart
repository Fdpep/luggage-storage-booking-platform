import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class OpeningInterval {
  final TimeOfDay open;
  final TimeOfDay close;

  OpeningInterval({required this.open, required this.close});

  OpeningInterval copyWith({TimeOfDay? open, TimeOfDay? close}) {
    return OpeningInterval(open: open ?? this.open, close: close ?? this.close);
  }

  Map<String, dynamic> toJson() => {
    "open":
        "${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}",
    "close":
        "${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}",
  };

  static OpeningInterval? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    TimeOfDay parse(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return OpeningInterval(
      open: parse((json['open'] ?? '') as String),
      close: parse((json['close'] ?? '') as String),
    );
  }
}

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

  late Map<String, List<OpeningInterval>> _dayIntervals;
  bool _actionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _initFromInitialValue();
  }

  void _initFromInitialValue() {
    _dayIntervals = {for (final d in days) d: <OpeningInterval>[]};

    final raw = widget.initialValue;
    if (raw == null) return;

    for (final d in days) {
      final list = raw[d] as List<dynamic>? ?? [];
      _dayIntervals[d] = list
          .map(
            (e) => OpeningInterval.fromJson((e as Map).cast<String, dynamic>()),
          )
          .whereType<OpeningInterval>()
          .toList();
    }
  }

  // -----------------------
  // UI helpers (iOS-like)
  // -----------------------
  Widget _thinDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.35),
    );
  }

  Widget _iosSection(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String text,
    required bool active,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bg = danger
        ? cs.errorContainer.withOpacity(0.35)
        : (active
              ? cs.primary.withOpacity(0.12)
              : cs.surfaceVariant.withOpacity(0.35));
    final fg = danger
        ? cs.error
        : (active ? cs.primary : cs.onSurface.withOpacity(0.6));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: tt.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _iconSquare(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = danger ? cs.error : cs.onSurface.withOpacity(0.85);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
          ),
          child: Center(child: Icon(icon, size: 18, color: fg)),
        ),
      ),
    );
  }

  Widget _rowAction(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final ic = danger ? cs.error : cs.onSurface.withOpacity(0.85);
    final st = subtitle == null
        ? null
        : tt.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.7),
            height: 1.25,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ic),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: danger ? cs.error : cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: st),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineError(BuildContext context, String msg) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg, style: tt.bodySmall?.copyWith(height: 1.25)),
          ),
        ],
      ),
    );
  }

  String _timeToString(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool _isH24Interval(OpeningInterval i) {
    final a = _toMinutes(i.open);
    final b = _toMinutes(i.close);
    // ✅ accetto sia 00:00–23:59 che 23:59–00:00 (poi normalizzo)
    final isA = (a == 0 && b == (23 * 60 + 59));
    final isB = (a == (23 * 60 + 59) && b == 0);
    return isA || isB;
  }

  OpeningInterval _normalizeH24(OpeningInterval i) {
    // sempre salvato come 00:00–23:59
    if (_isH24Interval(i)) {
      return OpeningInterval(
        open: const TimeOfDay(hour: 0, minute: 0),
        close: const TimeOfDay(hour: 23, minute: 59),
      );
    }
    return i;
  }

  bool _isH24Day(List<OpeningInterval> intervals) =>
      intervals.length == 1 && _isH24Interval(intervals.first);

  // -----------------------
  // Notify parent (logica invariata)
  // -----------------------
  void _emit() {
    final hasAny = _dayIntervals.values.any((l) => l.isNotEmpty);
    if (!hasAny) {
      widget.onChanged(null);
      return;
    }

    widget.onChanged({
      for (final d in days)
        d: (_dayIntervals[d] ?? const <OpeningInterval>[])
            .map((e) => _normalizeH24(e).toJson())
            .toList(),
    });
  }

  void _copyDayToTargets(String source, List<String> targets) {
    final src = List<OpeningInterval>.from(
      _dayIntervals[source] ?? const <OpeningInterval>[],
    ).map((e) => _normalizeH24(e)).toList();

    setState(() {
      for (final t in targets) {
        _dayIntervals[t] = src.map((e) => e.copyWith()).toList();
      }
    });
    _emit();
  }

  void _closeAllDays() {
    setState(() {
      for (final d in days) {
        _dayIntervals[d] = <OpeningInterval>[];
      }
    });
    _emit();
  }

  void _setAllDaysH24() {
    setState(() {
      for (final d in days) {
        _dayIntervals[d] = [
          OpeningInterval(
            open: const TimeOfDay(hour: 0, minute: 0),
            close: const TimeOfDay(hour: 23, minute: 59),
          ),
        ];
      }
    });
    _emit();
  }

  void _setClosed(String day) {
    setState(() => _dayIntervals[day] = <OpeningInterval>[]);
    _emit();
  }

  void _setDayH24(String day) {
    setState(() {
      _dayIntervals[day] = [
        OpeningInterval(
          open: const TimeOfDay(hour: 0, minute: 0),
          close: const TimeOfDay(hour: 23, minute: 59),
        ),
      ];
    });
    _emit();
  }

  void _removeInterval(String day, int idx) {
    setState(() {
      final list = _dayIntervals[day] ?? <OpeningInterval>[];
      if (idx >= 0 && idx < list.length) list.removeAt(idx);
      _dayIntervals[day] = list;
    });
    _emit();
  }

  // -----------------------
  // Validation (smart)
  // -----------------------
  String? _validateCandidate({
    required String day,
    required OpeningInterval candidate,
    int? editingIndex,
  }) {
    final list = List<OpeningInterval>.from(
      _dayIntervals[day] ?? const <OpeningInterval>[],
    ).map(_normalizeH24).toList();

    final normalized = _normalizeH24(candidate);

    // H24 compatibilità: deve essere unica fascia
    if (_isH24Interval(normalized)) {
      final others = list
          .asMap()
          .entries
          .where((e) => e.key != (editingIndex ?? -1))
          .toList();
      if (others.isNotEmpty) {
        return '“Aperto H24” non può coesistere con altre fasce nello stesso giorno.';
      }
      return null;
    }

    final a = _toMinutes(normalized.open);
    final b = _toMinutes(normalized.close);

    if (b <= a) {
      return 'La chiusura deve essere dopo l’apertura (stesso giorno).';
    }

    // Se l'altro intervallo è H24 => impossibile
    for (final e in list.asMap().entries) {
      if (e.key == (editingIndex ?? -1)) continue;
      if (_isH24Interval(e.value)) {
        return 'Questo giorno è “Aperto H24”: rimuovi H24 prima di aggiungere fasce.';
      }
    }

    // Overlap: (start < otherEnd) && (otherStart < end)
    for (final e in list.asMap().entries) {
      if (e.key == (editingIndex ?? -1)) continue;
      final other = _normalizeH24(e.value);
      final os = _toMinutes(other.open);
      final oe = _toMinutes(other.close);

      // altre fasce non-H24 dovrebbero avere oe > os; se non, ignoriamo
      if (oe <= os) continue;

      final overlaps = a < oe && os < b;
      if (overlaps) {
        return 'La fascia si sovrappone con ${_timeToString(other.open)}–${_timeToString(other.close)}.';
      }
    }

    return null;
  }

  // -----------------------
  // iOS wheel time picker
  // -----------------------
  Future<TimeOfDay?> pickTimeIosSheet({
    required BuildContext context,
    required String title,
    required TimeOfDay initial,
  }) async {
    TimeOfDay temp = initial;

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        DateTime toDate(TimeOfDay t) => DateTime(2020, 1, 1, t.hour, t.minute);

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(temp),
                      child: const Text('Fatto'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: toDate(initial),
                    onDateTimeChanged: (d) {
                      temp = TimeOfDay(hour: d.hour, minute: d.minute);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------
  // Smart sheets: copy + day actions
  // -----------------------
  Future<void> _openCopySheet({String? fixedSourceDay}) async {
    final sourceInitial = fixedSourceDay ?? 'mon';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        String source = sourceInitial;
        final srcHasIntervals = () =>
            (_dayIntervals[source] ?? const <OpeningInterval>[]).isNotEmpty;

        List<String> targets = <String>[];

        String? err;

        void setPreset(String preset) {
          if (preset == 'Tutti') {
            targets = days.where((d) => d != source).toList();
          } else if (preset == 'Lun–Ven') {
            targets = [
              'mon',
              'tue',
              'wed',
              'thu',
              'fri',
            ].where((d) => d != source).toList();
          } else if (preset == 'Weekend') {
            targets = ['sat', 'sun'].where((d) => d != source).toList();
          }
        }

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Widget chip(String key, bool selected, VoidCallback onTap) {
                return FilterChip(
                  label: Text(labels[key] ?? key),
                  selected: selected,
                  onSelected: (_) => onTap(),
                  showCheckmark: false,
                );
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Copia orari',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Chiudi',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // SOURCE (se non fissato)
                    if (fixedSourceDay == null) ...[
                      _iosSection(
                        ctx,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Sorgente',
                                    style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: source,
                                  underline: const SizedBox.shrink(),
                                  items: days
                                      .map(
                                        (d) => DropdownMenuItem(
                                          value: d,
                                          child: Text(labels[d]!),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setLocal(() {
                                      source = v;
                                      // ricalcolo “Tutti escluso sorgente”
                                      targets = <String>[]; //

                                      err = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // TARGETS
                    _iosSection(
                      ctx,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Destinazioni',
                                  style: tt.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  InkWell(
                                    onTap: () => setLocal(() {
                                      setPreset('Tutti');
                                      err = null;
                                    }),
                                    borderRadius: BorderRadius.circular(999),
                                    child: _pill(
                                      ctx,
                                      text: 'Tutti',
                                      active: false,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setLocal(() {
                                      setPreset('Lun–Ven');
                                      err = null;
                                    }),
                                    borderRadius: BorderRadius.circular(999),
                                    child: _pill(
                                      ctx,
                                      text: 'Lun–Ven',
                                      active: false,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setLocal(() {
                                      setPreset('Weekend');
                                      err = null;
                                    }),
                                    borderRadius: BorderRadius.circular(999),
                                    child: _pill(
                                      ctx,
                                      text: 'Weekend',
                                      active: false,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: days.map((d) {
                              final disabled = d == source;
                              final selected = targets.contains(d);

                              return Opacity(
                                opacity: disabled ? 0.35 : 1.0,
                                child: IgnorePointer(
                                  ignoring: disabled,
                                  child: chip(
                                    d,
                                    selected,
                                    () => setLocal(() {
                                      if (selected) {
                                        targets.remove(d);
                                      } else {
                                        targets.add(d);
                                      }
                                      err = null;
                                    }),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),

                    if (err != null) _inlineError(ctx, err!),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!srcHasIntervals()) {
                            setLocal(
                              () => err =
                                  'Il giorno sorgente non ha fasce da copiare.',
                            );
                            return;
                          }
                          if (targets.isEmpty) {
                            setLocal(
                              () => err =
                                  'Seleziona almeno un giorno destinazione.',
                            );
                            return;
                          }
                          _copyDayToTargets(source, targets);
                          Navigator.of(ctx).pop();
                        },
                        style:
                            ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary, // ✅
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ).copyWith(
                              foregroundColor: MaterialStatePropertyAll(
                                cs.onPrimary,
                              ), // ✅ forza bianco
                            ),
                        child: const Text('Applica'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openDayActionsSheet(String day) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        labels[day]!,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        'Chiudi',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _iosSection(
                  ctx,
                  children: [
                    _rowAction(
                      ctx,
                      icon: Icons.copy_all_rounded,
                      title: 'Copia orari',
                      subtitle: 'Seleziona i giorni destinazione',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await _openCopySheet(fixedSourceDay: day);
                      },
                    ),
                    _thinDivider(ctx),
                    _rowAction(
                      ctx,
                      icon: Icons.schedule_rounded,
                      title: 'Imposta “Aperto H24”',
                      subtitle: '00:00 – 23:59',
                      onTap: () {
                        _setDayH24(day);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    _thinDivider(ctx),
                    _rowAction(
                      ctx,
                      icon: Icons.block_rounded,
                      title: 'Imposta chiuso',
                      subtitle: 'Rimuove tutte le fasce',
                      danger: true,
                      onTap: () {
                        _setClosed(day);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------
  // Modern add/edit sheet (smart validation)
  // -----------------------
  Future<void> _addOrEditInterval(String day, {int? index}) async {
    final list = _dayIntervals[day] ?? <OpeningInterval>[];

    // max 2 intervalli (mattina/pomeriggio)
    if (index == null && list.length >= 2) {
      // UX: non snack “brutto”, ma sheet? qui resto semplice
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Puoi impostare massimo 2 fasce (mattina/pomeriggio).',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    final isEdit = index != null;
    final current = isEdit
        ? list[index!]
        : OpeningInterval(
            open: const TimeOfDay(hour: 9, minute: 0),
            close: const TimeOfDay(hour: 18, minute: 0),
          );

    TimeOfDay open = current.open;
    TimeOfDay close = current.close;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        String? error;
        bool h24 = _isH24Interval(_normalizeH24(current));

        if (h24) {
          open = const TimeOfDay(hour: 0, minute: 0);
          close = const TimeOfDay(hour: 23, minute: 59);
        }

        Widget rowPick(String k, String v, VoidCallback? onTap) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    v,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface.withOpacity(0.8),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          );
        }

        Widget rowToggleH24(VoidCallback onToggle) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Aperto H24',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Switch.adaptive(value: h24, onChanged: (_) => onToggle()),
              ],
            ),
          );
        }

        void trySave(StateSetter setLocal) {
          final cand = _normalizeH24(OpeningInterval(open: open, close: close));

          final msg = _validateCandidate(
            day: day,
            candidate: cand,
            editingIndex: index,
          );

          if (msg != null) {
            setLocal(() => error = msg);
            return;
          }

          Navigator.of(ctx).pop(true);
        }

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final preview = h24
                  ? '00:00 – 23:59'
                  : '${_timeToString(open)} – ${_timeToString(close)}';

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit ? 'Modifica fascia' : 'Aggiungi fascia',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(
                            'Annulla',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => trySave(setLocal),
                          child: const Text('Salva'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    _iosSection(
                      ctx,
                      children: [
                        rowToggleH24(() {
                          setLocal(() {
                            h24 = !h24;
                            error = null;
                            if (h24) {
                              open = const TimeOfDay(hour: 0, minute: 0);
                              close = const TimeOfDay(hour: 23, minute: 59);
                            } else {
                              // fallback “pulito”
                              open = const TimeOfDay(hour: 9, minute: 0);
                              close = const TimeOfDay(hour: 18, minute: 0);
                            }
                          });
                        }),
                        _thinDivider(ctx),
                        rowPick(
                          'Apre',
                          _timeToString(open),
                          h24
                              ? null
                              : () async {
                                  final picked = await pickTimeIosSheet(
                                    context: ctx,
                                    title: 'Orario di apertura',
                                    initial: open,
                                  );
                                  if (picked != null) {
                                    setLocal(() {
                                      open = picked;
                                      error = null;
                                    });
                                  }
                                },
                        ),
                        _thinDivider(ctx),
                        rowPick(
                          'Chiude',
                          _timeToString(close),
                          h24
                              ? null
                              : () async {
                                  final picked = await pickTimeIosSheet(
                                    context: ctx,
                                    title: 'Orario di chiusura',
                                    initial: close,
                                  );
                                  if (picked != null) {
                                    setLocal(() {
                                      close = picked;
                                      error = null;
                                    });
                                  }
                                },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Anteprima: $preview',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                        height: 1.25,
                      ),
                    ),

                    if (error != null) _inlineError(ctx, error!),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (saved != true) return;

    setState(() {
      final updated = _normalizeH24(OpeningInterval(open: open, close: close));
      final curr = List<OpeningInterval>.from(
        _dayIntervals[day] ?? <OpeningInterval>[],
      );

      if (isEdit) {
        curr[index!] = updated;
      } else {
        curr.add(updated);
      }

      // ordina per open per UI più chiara
      curr.sort(
        (a, b) => _toMinutes(
          _normalizeH24(a).open,
        ).compareTo(_toMinutes(_normalizeH24(b).open)),
      );

      // se uno è H24 => deve restare unico
      if (curr.any(_isH24Interval)) {
        _dayIntervals[day] = [
          OpeningInterval(
            open: const TimeOfDay(hour: 0, minute: 0),
            close: const TimeOfDay(hour: 23, minute: 59),
          ),
        ];
      } else {
        _dayIntervals[day] = curr;
      }
    });

    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ Azioni rapide collassabili
        _iosSection(
          context,
          children: [
            InkWell(
              onTap: () => setState(() => _actionsExpanded = !_actionsExpanded),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Azioni rapide',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      _actionsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ],
                ),
              ),
            ),
            if (_actionsExpanded) ...[
              _thinDivider(context),
              _rowAction(
                context,
                icon: Icons.copy_all_rounded,
                title: 'Copia orari tra giorni',
                subtitle: 'Scegli sorgente e destinazioni',
                onTap: () => _openCopySheet(),
              ),
              _thinDivider(context),
              _rowAction(
                context,
                icon: Icons.schedule_rounded,
                title: 'Imposta Aperto H24 (24/7) per tutti',
                subtitle: '00:00 – 23:59 su ogni giorno',
                onTap: _setAllDaysH24,
              ),
              _thinDivider(context),
              _rowAction(
                context,
                icon: Icons.block_rounded,
                title: 'Imposta tutti chiusi',
                subtitle: 'Rimuove tutte le fasce',
                danger: true,
                onTap: _closeAllDays,
              ),
            ],
          ],
        ),

        const SizedBox(height: 14),

        ...days.map((day) {
          final intervals = (_dayIntervals[day] ?? <OpeningInterval>[])
              .map(_normalizeH24)
              .toList();
          final isClosed = intervals.isEmpty;
          final isH24 = _isH24Day(intervals);

          final status = isClosed
              ? 'Chiuso'
              : (isH24
                    ? 'Aperto H24'
                    : (intervals.length == 1
                          ? 'Orario continuato'
                          : 'Mattina + Pomeriggio'));

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _iosSection(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[day]!,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _pill(
                        context,
                        text: status,
                        active: !isClosed,
                        danger: false,
                      ),
                      const SizedBox(width: 10),
                      _iconSquare(
                        context,
                        icon: Icons.more_horiz_rounded,
                        tooltip: 'Azioni giorno',
                        onTap: () => _openDayActionsSheet(day),
                      ),
                    ],
                  ),
                ),
                _thinDivider(context),

                if (isClosed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Text(
                      'Nessuna fascia impostata: il locale risulta chiuso in questo giorno.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                        height: 1.25,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      children: [
                        if (isH24)
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceVariant.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: cs.outlineVariant.withOpacity(
                                        0.35,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Aperto H24 • 00:00 – 23:59',
                                    style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _iconSquare(
                                context,
                                icon: Icons.edit_rounded,
                                tooltip: 'Modifica (toglie H24)',
                                onTap: () => _addOrEditInterval(day, index: 0),
                              ),
                              const SizedBox(width: 8),
                              _iconSquare(
                                context,
                                icon: Icons.delete_outline_rounded,
                                tooltip: 'Rimuovi H24 (chiudi)',
                                danger: true,
                                onTap: () => _setClosed(day),
                              ),
                            ],
                          )
                        else
                          ...intervals.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final interval = entry.value;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: idx == intervals.length - 1 ? 0 : 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.surfaceVariant.withOpacity(
                                          0.18,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: cs.outlineVariant.withOpacity(
                                            0.35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '${_timeToString(interval.open)} – ${_timeToString(interval.close)}',
                                        style: tt.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _iconSquare(
                                    context,
                                    icon: Icons.edit_rounded,
                                    tooltip: 'Modifica fascia',
                                    onTap: () =>
                                        _addOrEditInterval(day, index: idx),
                                  ),
                                  const SizedBox(width: 8),
                                  _iconSquare(
                                    context,
                                    icon: Icons.delete_outline_rounded,
                                    tooltip: 'Rimuovi fascia',
                                    danger: true,
                                    onTap: () => _removeInterval(day, idx),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                _thinDivider(context),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isH24
                              ? null
                              : () => _addOrEditInterval(day),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Aggiungi fascia'),
                          style: OutlinedButton.styleFrom(
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withOpacity(0.35),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            foregroundColor: cs.onSurface,
                            backgroundColor: cs.surfaceVariant.withOpacity(
                              0.18,
                            ),
                            textStyle: tt.bodySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: isClosed ? null : () => _setClosed(day),
                        style: OutlinedButton.styleFrom(
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          side: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          foregroundColor: isClosed
                              ? cs.onSurface.withOpacity(0.4)
                              : cs.error,
                          backgroundColor: cs.surfaceVariant.withOpacity(0.18),
                          textStyle: tt.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: const Text('Chiuso'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ------------------------------------------------------------
// Exceptions (restyle + iOS date picker bottom sheet)
// ------------------------------------------------------------
class OpeningExceptionsEditor extends StatefulWidget {
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const OpeningExceptionsEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<OpeningExceptionsEditor> createState() =>
      _OpeningExceptionsEditorState();
}

class _OpeningExceptionsEditorState extends State<OpeningExceptionsEditor> {
  late List<DateTime> _closedDates;
  late List<DateTime> _forcedOpenDates;

  @override
  void initState() {
    super.initState();
    _closedDates = _parseDateList(widget.initialValue?['closed_dates']);
    _forcedOpenDates = _parseDateList(
      widget.initialValue?['forced_open_dates'],
    );
  }

  List<DateTime> _parseDateList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => DateTime.tryParse(e as String? ?? ''))
          .whereType<DateTime>()
          .toList()
        ..sort();
    }
    return [];
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString().padLeft(4, '0');
    return '$dd/$mm/$yyyy';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _notify() {
    if (_closedDates.isEmpty && _forcedOpenDates.isEmpty) {
      widget.onChanged(null);
    } else {
      widget.onChanged({
        'closed_dates': _closedDates
            .map((d) => d.toIso8601String().substring(0, 10))
            .toList(),
        'forced_open_dates': _forcedOpenDates
            .map((d) => d.toIso8601String().substring(0, 10))
            .toList(),
      });
    }
  }

  Widget _thinDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.35),
    );
  }

  Widget _iosSection(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Future<DateTime?> _pickDateIosSheet({
    required BuildContext context,
    required String title,
    required DateTime initial,
    required DateTime min,
    required DateTime max,
  }) async {
    DateTime temp = DateTime(initial.year, initial.month, initial.day);

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(temp),
                      child: const Text('Fatto'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: temp,
                    minimumDate: min,
                    maximumDate: max,
                    onDateTimeChanged: (d) {
                      temp = DateTime(d.year, d.month, d.day);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate({required bool closed}) async {
    final now = DateTime.now();
    final min = DateTime(now.year, now.month, now.day);
    final max = DateTime(now.year + 2, 12, 31);

    final picked = await _pickDateIosSheet(
      context: context,
      title: closed ? 'Aggiungi chiusura' : 'Aggiungi apertura',
      initial: min,
      min: min,
      max: max,
    );

    if (picked == null) return;

    setState(() {
      final list = closed ? _closedDates : _forcedOpenDates;
      if (!list.any((d) => _sameDay(d, picked))) {
        list.add(picked);
        list.sort();
      }
    });

    _notify();
  }

  void _removeDate({required bool closed, required DateTime date}) {
    setState(() {
      final list = closed ? _closedDates : _forcedOpenDates;
      list.removeWhere((d) => _sameDay(d, date));
    });
    _notify();
  }

  Widget _headerRow(
    BuildContext context, {
    required String title,
    required VoidCallback onAdd,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.85),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Aggiungi',
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(
    BuildContext context,
    DateTime d, {
    required VoidCallback onRemove,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _formatDate(d),
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Center(
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: cs.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Eccezioni calendario',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Puoi impostare giorni di chiusura straordinaria (es. festività) e giorni di apertura straordinaria (quando normalmente saresti chiuso).',
          style: tt.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.7),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),

        _iosSection(
          context,
          children: [
            _headerRow(
              context,
              title: 'Giorni di chiusura straordinaria',
              onAdd: () => _pickDate(closed: true),
            ),
            _thinDivider(context),
            if (_closedDates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Text(
                  'Nessuna chiusura straordinaria impostata.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              )
            else
              ..._closedDates.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value;
                return Column(
                  children: [
                    _dateRow(
                      context,
                      d,
                      onRemove: () => _removeDate(closed: true, date: d),
                    ),
                    if (i != _closedDates.length - 1) _thinDivider(context),
                  ],
                );
              }),
          ],
        ),

        const SizedBox(height: 12),

        _iosSection(
          context,
          children: [
            _headerRow(
              context,
              title: 'Giorni di apertura straordinaria',
              onAdd: () => _pickDate(closed: false),
            ),
            _thinDivider(context),
            if (_forcedOpenDates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Text(
                  'Nessuna apertura straordinaria impostata.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
              )
            else
              ..._forcedOpenDates.asMap().entries.map((e) {
                final i = e.key;
                final d = e.value;
                return Column(
                  children: [
                    _dateRow(
                      context,
                      d,
                      onRemove: () => _removeDate(closed: false, date: d),
                    ),
                    if (i != _forcedOpenDates.length - 1) _thinDivider(context),
                  ],
                );
              }),
          ],
        ),
      ],
    );
  }
}
