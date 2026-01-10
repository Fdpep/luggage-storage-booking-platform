import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PartnerScanCameraScreen extends StatefulWidget {
  const PartnerScanCameraScreen({super.key});

  @override
  State<PartnerScanCameraScreen> createState() => _PartnerScanCameraScreenState();
}

class _PartnerScanCameraScreenState extends State<PartnerScanCameraScreen> {
  bool _handled = false;

  String? _extractCode(String raw) {
    final m = RegExp(r'BD[0-9A-F]{10}', caseSensitive: false).firstMatch(raw);
    return m?.group(0)?.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scansiona QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;

          final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
          final raw = barcode?.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          final code = _extractCode(raw);
          if (code == null) {
            // QR non valido (non contiene BDXXXXXXXXXX)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('QR non riconosciuto (manca BDXXXXXXXXXX).')),
            );
            return;
          }

          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
