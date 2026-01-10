import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class BookingQrScreen extends StatelessWidget {
  final String bookingId;
  final String bookingCode;

  const BookingQrScreen({
    super.key,
    required this.bookingId,
    required this.bookingCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR prenotazione'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  QrImageView(
                    data: bookingCode, // per ora SOLO BDXXXXXXXXXX
                    size: 240,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    bookingCode,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mostra questo codice al partner per check-in e check-out.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: bookingCode),
                            );
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Codice copiato')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copia codice'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nota: il QR è statico. Al check-out, se hai sforato oltre la tolleranza (15 min), verrà richiesto un supplemento (pulsante “Paga ora”).',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.65)),
          ),
        ],
      ),
    );
  }
}
