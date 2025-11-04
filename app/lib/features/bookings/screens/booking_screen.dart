import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../venues/models/venue.dart';

class BookingScreen extends StatefulWidget {
  final Venue venue;
  const BookingScreen({super.key, required this.venue});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();

  int _daysInclusive(DateTime s, DateTime e) {
    final ss = DateTime(s.year, s.month, s.day);
    final ee = DateTime(e.year, e.month, e.day);
    return ee.difference(ss).inDays + 1;
  }

  double get _daily => widget.venue.minPrice < 5 ? 5.0 : widget.venue.minPrice;
  double get _total => _daily * _daysInclusive(_start, _end);

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _end = d);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: Text('Prenota • ${widget.venue.name}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Data deposito'),
              subtitle: Text(df.format(_start)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickStart,
            ),
            ListTile(
              title: const Text('Data ritiro'),
              subtitle: Text(df.format(_end)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickEnd,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Tariffa giornaliera')),
                Text('€ ${_daily.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: Text('Giorni (inclusivi)')),
                Text('${_daysInclusive(_start, _end)}'),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Totale',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Text('€ ${_total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.backpack),
                label: const Text('Conferma prenotazione'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Prenotazione creata: €${_total.toStringAsFixed(2)}')),
                  );
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
