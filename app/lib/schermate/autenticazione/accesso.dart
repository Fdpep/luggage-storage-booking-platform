import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/validators.dart';
import '../../utils/last_email_store.dart';
import '../../services/supabase/user_repo.dart';
import '../home_shell.dart';

/// Schermata di **accesso con e-mail + password**
/// - Prefill e-mail (se presente)
/// - Validazione, gestione errori, focus
/// - Pulsante "Password dimenticata?"
class AccessoScreen extends StatefulWidget {
  const AccessoScreen({super.key});

  @override
  State<AccessoScreen> createState() => _AccessoScreenState();
}

class _AccessoScreenState extends State<AccessoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrlEmail = TextEditingController();
  final _ctrlPassword = TextEditingController();
  final _focusPwd = FocusNode();

  bool _showPwd = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Prefill e-mail se salvata
    LastEmailStore.load().then((v) {
      if (!mounted) return;
      if (v != null) _ctrlEmail.text = v;
    });
  }

  @override
  void dispose() {
    _ctrlEmail.dispose();
    _ctrlPassword.dispose();
    _focusPwd.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Chiudi tastiera per evitare glitch UI
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    try {
      await supabase.auth.signInWithPassword(
        email: _ctrlEmail.text.trim(),
        password: _ctrlPassword.text,
      );

      // Salva e-mail e upsert profilo
      await LastEmailStore.save(_ctrlEmail.text);
      if (supabase.auth.currentSession != null) {
        await UserRepo().upsertMe();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accesso effettuato!')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      // Messaggi più chiari su alcuni casi comuni
      final msg = e.message.toLowerCase();
      String readable = 'Errore: ${e.message}';
      if (msg.contains('invalid login') || msg.contains('invalid email or password')) {
        readable = 'Credenziali non valide. Controlla e riprova.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(readable)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imprevisto: $e')),
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
        title: const Text('Accedi'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Inserisci le tue credenziali per accedere.',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),

                  // E-mail
                  TextFormField(
                    controller: _ctrlEmail,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _focusPwd.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      hintText: 'nome@esempio.com',
                    ),
                    validator: Validators.email,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 12),

                  // Password
                  TextFormField(
                    controller: _ctrlPassword,
                    focusNode: _focusPwd,
                    autofillHints: const [AutofillHints.password],
                    obscureText: !_showPwd,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: _busy ? null : () => setState(() => _showPwd = !_showPwd),
                        icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility),
                        tooltip: _showPwd ? 'Nascondi' : 'Mostra',
                      ),
                    ),
                    validator: Validators.password,
                    enabled: !_busy,
                    onFieldSubmitted: (_) => _login(),
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pushNamed('/reset'),
                      child: const Text('Password dimenticata?'),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Accedi'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Non hai un account?'),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                .pushReplacementNamed('/registrazione'),
                        child: const Text('Registrati'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
