import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'registrazione.dart';
import 'verify_otp.dart';

//import 'auth_actions.dart';

class AccessoScreen extends StatefulWidget {
  const AccessoScreen({super.key});

  @override
  State<AccessoScreen> createState() => _AccessoScreenState();
}

class _AccessoScreenState extends State<AccessoScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _showPwd = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    final supabase = Supabase.instance.client;

    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;

      final resp = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = resp.session;
      final user = resp.user;

      if (session == null || user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credenziali non valide.')),
        );
        return;
      }

      // 👇 Leggiamo il flag otp_verified dai metadati
      final meta = user.userMetadata ?? {};
      final otpVerified = meta['otp_verified'] == true;

      // Se NON ha ancora verificato l'OTP → portalo alla schermata di verifica
      if (!otpVerified) {
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SchermataVerifyOtp(
              email: email,
              // postSignup: false (default)
              // isPartnerFlow: false (default)
            ),
          ),
        );
        return; // importantissimo: non continuare oltre
      }

      // Se è verificato → comportamento normale: torni alla root (AuthGate si occupa del resto)
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore di accesso: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imprevisto: $e')));
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accedi al tuo account BagDrop.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'nome@esempio.com',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Inserisci un’e-mail';
                    if (!t.contains('@')) return 'E-mail non valida';
                    return null;
                  },
                  enabled: !_busy,
                ),
                const SizedBox(height: 12),

                // Password
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_showPwd,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _showPwd = !_showPwd),
                      icon: Icon(
                        _showPwd ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Inserisci la password';
                    return null;
                  },
                  enabled: !_busy,
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accedi'),
                  ),
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Non hai un account?'),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegistrazioneScreen(),
                                ),
                              );
                            },
                      child: const Text('Registrati'),
                    ),
                  ],
                ),
                /*const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Oppure esplora senza registrarti',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy
                         ? null
    : () async {
        await AuthActions.enterAsGuest(context);
      },

                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Esplora come ospite'),
                  ),
                ),            */
              ],
            ),
          ),
        ),
      ),
    );
  }
}
