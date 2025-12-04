import 'dart:math';

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
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
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
      const SnackBar(
        content: Text('Il tuo account è stato eliminato.'),
      ),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Elimina account'),
        backgroundColor: cs.error,
        foregroundColor: cs.onError,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attenzione',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.error,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stai per richiedere l\'eliminazione definitiva del tuo account BagDrop.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cosa succede se confermi:',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const _BulletPoint(
                  'Il tuo account verrà rimosso da BagDrop.',
                ),
                const _BulletPoint(
                  'Le prenotazioni collegate potranno essere anonimizzate o eliminate (in base alla policy).',
                ),
                const _BulletPoint(
                  'Perderai l\'accesso a tutte le funzionalità dell\'app.',
                ),
                const _BulletPoint(
                  'Riceverai una e-mail di conferma all\'indirizzo associato all\'account.',
                ),

                const SizedBox(height: 24),
                Text(
                  'Per confermare, genera un codice casuale e riscrivilo nel campo sottostante.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),

                // Bottone "Genera codice"
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _onGenerateCode,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Genera codice di conferma'),
                  ),
                ),

                const SizedBox(height: 12),

                if (_generatedCode != null) ...[
                  Text(
                    'Codice generato (copialo e riscrivilo sotto):',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _generatedCode!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _codeCtrl,
                  enabled: _generatedCode != null && !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Inserisci qui il codice generato',
                    border: OutlineInputBorder(),
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
                ),

                const SizedBox(height: 24),

                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    onPressed: _busy
                        ? null
                        : () {
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            _confirmDelete();
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.delete_forever),
                    label: Text(_busy ? 'Eliminazione...' : 'Conferma eliminazione'),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'Questa operazione è irreversibile. Se hai dubbi, torna indietro.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
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

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ],
    );
  }
}
