import 'dart:math';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Schermata di conferma eliminazione account.
///
/// Flusso:
/// - Mostra spiegazione di cosa succede.
/// - L'utente genera un codice alfanumerico casuale.
/// - Il codice va inserito esattamente uguale nel campo sottostante (campo disabilitato finché non generi).
/// - Solo quando il codice coincide il bottone "Conferma eliminazione" è abilitato.
/// - Alla conferma viene chiamata una RPC / Edge Function backend che:
///   - elimina (o anonimizza) i dati dell'utente,
///   - elimina l'utente da auth.users,
///   - invia una e-mail di conferma all'utente.
/// - Poi viene fatto signOut lato client.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();

  String? _generatedCode;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _generateCode(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // niente 0/O, 1/I
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> _onGenerateCode() async {
    setState(() {
      _generatedCode = _generateCode(8);
      _codeCtrl.clear();
      _error = null;
    });
  }

  bool get _isCodeValid {
    if (_generatedCode == null) return false;
    return _codeCtrl.text.trim() == _generatedCode;
  }

  Future<void> _confirmDelete() async {
    if (!_isCodeValid) {
      setState(() {
        _error = 'Il codice inserito non è corretto.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('Nessun utente autenticato.');
      }

      // Chiamiamo la RPC lato backend
      await client.rpc('delete_my_account');

      // Se la RPC è andata bene, facciamo logout
      await client.auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il tuo account è stato eliminato.')),
      );

      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // Errore proveniente dalla funzione SQL
      final msg = e.message ?? '';

      String uiMessage;
      if (msg.contains('prenotazioni attive')) {
        uiMessage =
            'Non puoi eliminare l’account perché hai ancora prenotazioni attive.\n'
            'Cancella o attendi la conclusione delle prenotazioni prima di procedere.';
      } else {
        uiMessage = 'Errore durante l’eliminazione dell’account: $msg';
      }

      if (!mounted) return;
      setState(() {
        _error = uiMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Errore durante l\'eliminazione dell\'account: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ---------------------------
  // iOS-like UI helpers
  // ---------------------------

  Widget iosSection(BuildContext context, {required List<Widget> children}) {
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

  Widget sectionDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.35),
    );
  }

  Widget rowKV(BuildContext context, String k, String v, {bool bold = false}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            v,
            style: tt.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: cs.onSurface.withOpacity(bold ? 1.0 : 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return iosSection(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.error.withOpacity(0.25)),
                ),
                child: Icon(Icons.warning_amber_rounded, color: cs.error),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attenzione',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Stai per richiedere l\'eliminazione definitiva del tuo account BagDrop.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        sectionDivider(context),
        rowKV(context, 'Operazione', 'Irreversibile', bold: true),
      ],
    );
  }

  Widget _whatHappensSection(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cosa succede se confermi',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        iosSection(
          context,
          children: const [
            _BulletRow('Il tuo account verrà rimosso da BagDrop.'),

            _ThinDivider(),
            _BulletRow(
              'Perderai l\'accesso a tutte le funzionalità dell\'app.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _codeSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conferma con codice',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        iosSection(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'Genera un codice casuale e riscrivilo nel campo sottostante. '
                'Il pulsante di eliminazione si abilita solo quando il codice coincide.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.75),
                ),
              ),
            ),
            sectionDivider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _onGenerateCode,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Genera codice di conferma'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.45),
                    ),
                  ),
                ),
              ),
            ),
            if (_generatedCode != null) ...[
              sectionDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Codice generato',
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _generatedCode!,
                          style: tt.titleSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Copia',
                        onPressed: () async {
                          // Non cambia la logica: solo UX
                          final data = ClipboardData(text: _generatedCode!);
                          await Clipboard.setData(data);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Codice copiato')),
                          );
                        },
                        icon: Icon(
                          Icons.copy_rounded,
                          color: cs.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            sectionDivider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: TextFormField(
                controller: _codeCtrl,
                enabled: _generatedCode != null && !_busy,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Inserisci qui il codice generato',
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.20),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.55),
                    ),
                  ),
                ),
                validator: (v) {
                  if (_generatedCode == null) {
                    return 'Prima genera il codice.';
                  }
                  final t = (v ?? '').trim();
                  if (t.isEmpty) {
                    return 'Inserisci il codice generato.';
                  }
                  if (t != _generatedCode) {
                    return 'Il codice non corrisponde.';
                  }
                  return null;
                },
                onChanged: (_) {
                  // Solo refresh UI per abilitare/disabilitare CTA (logica invariata)
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorSection(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.error.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.85),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctaSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final canSubmit = !_busy && _generatedCode != null && _isCodeValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canSubmit
                ? () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    _confirmDelete();
                  }
                : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label: Text(_busy ? 'Eliminazione...' : 'Conferma eliminazione'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Questa operazione è irreversibile. Se hai dubbi, torna indietro.',
          style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Elimina account',
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onPrimary,
          ),
        ),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withOpacity(0.35),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dangerHeader(context),
                const SizedBox(height: 16),

                _whatHappensSection(context),
                const SizedBox(height: 16),

                _codeSection(context),
                const SizedBox(height: 16),

                if (_error != null) ...[
                  _errorSection(context, _error!),
                  const SizedBox(height: 16),
                ],

                _ctaSection(context),

                const SizedBox(height: 6),
                Text(
                  'Suggerimento: se hai prenotazioni attive, l’eliminazione potrebbe essere bloccata.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.35),
    );
  }
}

class _BulletRow extends StatelessWidget {
  final String text;
  const _BulletRow(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
