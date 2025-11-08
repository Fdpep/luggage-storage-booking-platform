/////DA IMPLEMENTARE BENE, PER ORA MALE


import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/validators.dart';
import '../../utils/last_email_store.dart';

/// Chiede l’e-mail e invia il link di reset password.
/// NB: su mobile/web puoi specificare redirect/deep link.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrlEmail = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LastEmailStore.load().then((v) {
      if (!mounted) return;
      if (v != null) _ctrlEmail.text = v;
    });
  }

  @override
  void dispose() {
    _ctrlEmail.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    try {
      await supabase.auth.resetPasswordForEmail(
        _ctrlEmail.text.trim(),
        // TODO: se usi deep link mobile, imposta qui l'URI della tua app
        // redirectTo: 'io.bagdrop.app://password-reset',
      );

      await LastEmailStore.save(_ctrlEmail.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail inviata. Controlla la posta.')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: ${e.message}')),
      );
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
        title: const Text('Reset password'),
        backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _ctrlEmail,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'nome@esempio.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  enabled: !_busy,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _sendReset,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Invia link di reset'),
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
