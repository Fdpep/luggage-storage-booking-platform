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
      open: parse(json['open']),
      close: parse(json['close']),
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
  // Chiavi dei giorni in ordine
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

  /// Per ogni giorno, lista di max 2 intervalli (mattina / pomeriggio)
  late Map<String, List<OpeningInterval>> _dayIntervals;

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

  String _timeToString(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool _isStrictBefore(TimeOfDay a, TimeOfDay b) =>
      _toMinutes(a) < _toMinutes(b);

  bool _overlaps(
    TimeOfDay aOpen,
    TimeOfDay aClose,
    TimeOfDay bOpen,
    TimeOfDay bClose,
  ) {
    final aStart = _toMinutes(aOpen);
    final aEnd = _toMinutes(aClose);
    final bStart = _toMinutes(bOpen);
    final bEnd = _toMinutes(bClose);
    return aStart < bEnd && bStart < aEnd;
  }

  /// Serializza nel formato:
  /// { "mon": [ {open:"HH:MM", close:"HH:MM"}, ... ], ... }
  Map<String, dynamic> _serialize() {
    final map = <String, dynamic>{};
    for (final d in days) {
      map[d] = _dayIntervals[d]!.map((interval) => interval.toJson()).toList();
    }
    return map;
  }

  void _notifyChange() {
    widget.onChanged(_serialize());
  }

  Future<void> _addOrEditInterval(String day, {int? index}) async {
    final intervals = _dayIntervals[day] ?? <OpeningInterval>[];

    // Max 2 fasce per giorno
    if (index == null && intervals.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Puoi impostare al massimo due fasce orarie per giorno.',
          ),
        ),
      );
      return;
    }

    OpeningInterval? existing;
    if (index != null && index >= 0 && index < intervals.length) {
      existing = intervals[index];
    }

    // 1) Seleziona orario di apertura
    final initialOpen = existing?.open ?? const TimeOfDay(hour: 9, minute: 0);
    final pickedOpen = await showTimePicker(
      context: context,
      initialTime: initialOpen,
    );
    if (pickedOpen == null) return;

    // 2) Seleziona orario di chiusura
    final suggestedCloseHour = (pickedOpen.hour + 4).clamp(0, 23);
    final initialClose =
        existing?.close ??
        TimeOfDay(hour: suggestedCloseHour, minute: pickedOpen.minute);

    final pickedClose = await showTimePicker(
      context: context,
      initialTime: initialClose,
    );
    if (pickedClose == null) return;

    if (!_isStrictBefore(pickedOpen, pickedClose)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "L'orario di chiusura deve essere successivo a quello di apertura.",
          ),
        ),
      );
      return;
    }

    // Controllo sovrapposizione con altre fasce dello stesso giorno
    for (int i = 0; i < intervals.length; i++) {
      if (i == index) continue;
      final other = intervals[i];
      if (_overlaps(pickedOpen, pickedClose, other.open, other.close)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gli orari inseriti si sovrappongono ad un’altra fascia di ${labels[day]}.',
            ),
          ),
        );
        return;
      }
    }

    // Aggiorna lista
    setState(() {
      if (index == null) {
        intervals.add(OpeningInterval(open: pickedOpen, close: pickedClose));
      } else {
        intervals[index] = OpeningInterval(
          open: pickedOpen,
          close: pickedClose,
        );
      }
      // Ordiniamo per orario di apertura
      intervals.sort(
        (a, b) => _toMinutes(a.open).compareTo(_toMinutes(b.open)),
      );
      _dayIntervals[day] = intervals;
    });

    _notifyChange();
  }

  void _removeInterval(String day, int index) {
    setState(() {
      _dayIntervals[day]?.removeAt(index);
    });
    _notifyChange();
  }

  void _setClosed(String day) {
    setState(() {
      _dayIntervals[day] = <OpeningInterval>[];
    });
    _notifyChange();
  }

  void _copyDayToTargets(String fromDay, List<String> targets) {
    final source = _dayIntervals[fromDay] ?? <OpeningInterval>[];
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imposta prima gli orari di ${labels[fromDay]} per poterli copiare.',
          ),
        ),
      );
      return;
    }

    setState(() {
      for (final d in targets) {
        _dayIntervals[d] = source
            .map((i) => OpeningInterval(open: i.open, close: i.close))
            .toList();
      }
    });
    _notifyChange();
  }

  void _closeAllDays() {
    setState(() {
      for (final d in days) {
        _dayIntervals[d] = <OpeningInterval>[];
      }
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔹 RIGA AZIONI RAPIDE
        Text(
          'Azioni rapide',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copia Lunedì su Lun–Ven'),
              onPressed: () =>
                  _copyDayToTargets('mon', ['mon', 'tue', 'wed', 'thu', 'fri']),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Copia Lunedì su tutti'),
              onPressed: () => _copyDayToTargets('mon', days),
            ),
            TextButton.icon(
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Imposta tutti chiusi'),
              onPressed: _closeAllDays,
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 🔹 RIGHE GIORNO PER GIORNO
        ...days.map((day) {
          final intervals = _dayIntervals[day] ?? <OpeningInterval>[];
          final isClosed = intervals.isEmpty;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: nome giorno + stato + azioni
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          labels[day]!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isClosed
                              ? cs.surfaceVariant
                              : cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isClosed
                              ? 'Chiuso'
                              : (intervals.length == 1
                                    ? 'Orario continuato'
                                    : 'Mattina + Pomeriggio'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isClosed ? cs.outline : cs.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_copy),
                        tooltip: 'Copia questi orari su tutti i giorni',
                        onPressed: intervals.isEmpty
                            ? null
                            : () => _copyDayToTargets(day, days),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (isClosed)
                    Text(
                      'Nessuna fascia impostata: il locale risulta chiuso in questo giorno.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...intervals.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final interval = entry.value;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: cs.surfaceVariant,
                                    ),
                                    child: Text(
                                      '${_timeToString(interval.open)} – ${_timeToString(interval.close)}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: 'Modifica fascia',
                                  onPressed: () =>
                                      _addOrEditInterval(day, index: idx),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  tooltip: 'Rimuovi fascia',
                                  onPressed: () => _removeInterval(day, idx),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Aggiungi fascia'),
                        onPressed: () => _addOrEditInterval(day),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: isClosed ? null : () => _setClosed(day),
                        child: Text(
                          'Imposta chiuso',
                          style: TextStyle(
                            color: isClosed ? cs.outline : cs.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

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

  Future<void> _pickDate({required bool closed}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Eccezioni calendario', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Puoi impostare giorni di chiusura straordinaria (es. festività) '
          'e giorni di apertura straordinaria (quando normalmente saresti chiuso).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),

        // CHIUSURE STRAORDINARIE
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Giorni di chiusura straordinaria',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickDate(closed: true),
                      icon: const Icon(Icons.add),
                      label: const Text('Aggiungi'),
                    ),
                  ],
                ),
                if (_closedDates.isEmpty)
                  Text(
                    'Nessuna chiusura straordinaria impostata.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ..._closedDates.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_formatDate(d)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeDate(closed: true, date: d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // APERTURE STRAORDINARIE
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Giorni di apertura straordinaria',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickDate(closed: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Aggiungi'),
                    ),
                  ],
                ),
                if (_forcedOpenDates.isEmpty)
                  Text(
                    'Nessuna apertura straordinaria impostata.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ..._forcedOpenDates.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_formatDate(d)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeDate(closed: false, date: d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
