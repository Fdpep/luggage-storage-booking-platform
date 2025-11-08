import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/validators.dart';
import '../../utils/last_email_store.dart';
import 'verify_otp.dart';

/// Registrazione con e-mail + password **confermata via OTP**
/// Flusso:
/// 1) signUp(email, password)
/// 2) (se session attiva la chiudiamo per forzare verifica)
/// 3) inviamo OTP sull’e-mail (signInWithOtp shouldCreateUser:false)
/// 4) navighiamo alla schermata verifica OTP
class RegistrazioneScreen extends StatefulWidget {
  const RegistrazioneScreen({super.key});

  @override
  State<RegistrazioneScreen> createState() => _RegistrazioneScreenState();
}

class _RegistrazioneScreenState extends State<RegistrazioneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrlEmail = TextEditingController();
  final _ctrlPassword = TextEditingController();
  final _ctrlConferma = TextEditingController();

  bool _accetto = false;
  bool _showPwd = false;
  bool _showPwd2 = false;
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
    _ctrlPassword.dispose();
    _ctrlConferma.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_accetto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi accettare i termini per continuare')),
      );
      return;
    }

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;
    final email = _ctrlEmail.text.trim();
    final password = _ctrlPassword.text;

    try {
      // 1) Creazione account con password
      final resp = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'source': 'bagdrop-app'},
      );

      // 2) Se ha creato una sessione subito, la chiudiamo:
      // vogliamo che l'accesso vada avanti SOLO dopo verifica OTP.
      if (resp.session != null) {
        await supabase.auth.signOut();
      }

      // 3) Invio OTP per verifica e-mail (non ricreare l'utente)
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );

      await LastEmailStore.save(email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Codice inviato. Controlla la tua e-mail.')),
      );

      // 4) Vai alla verifica OTP (postSignup = true solo per messaggistica/telemetria)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SchermataVerifyOtp(email: email, postSignup: true),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      var msg = e.message;
      if (msg.toLowerCase().contains('user already registered')) {
        msg = 'Esiste già un account con questa e-mail.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $msg')));
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
        title: const Text('Registrati'),
        backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
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
                  Text('Crea il tuo account BagDrop (verifica via OTP).',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),

                  // E-mail
                  TextFormField(
                    controller: _ctrlEmail,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
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
                    autofillHints: const [AutofillHints.newPassword],
                    obscureText: !_showPwd,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: _busy ? null : () => setState(() => _showPwd = !_showPwd),
                        icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    validator: Validators.password,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

                  // Conferma password
                  TextFormField(
                    controller: _ctrlConferma,
                    autofillHints: const [AutofillHints.newPassword],
                    obscureText: !_showPwd2,
                    decoration: InputDecoration(
                      labelText: 'Conferma password',
                      suffixIcon: IconButton(
                        onPressed: _busy ? null : () => setState(() => _showPwd2 = !_showPwd2),
                        icon: Icon(_showPwd2 ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    validator: (v) => Validators.confermaPassword(v, _ctrlPassword),
                    enabled: !_busy,
                    onFieldSubmitted: (_) => _register(),
                  ),

                  const SizedBox(height: 12),

                  // Consenso
                  Row(
                    children: [
                      Checkbox(
                        value: _accetto,
                        onChanged: _busy ? null : (v) => setState(() => _accetto = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Ho letto e accetto i Documenti contrattuali & Privacy.',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _register,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Registrati'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Hai già un account?'),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pushReplacementNamed('/accesso'),
                        child: const Text('Accedi'),
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
