import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePwd = true;

  Future<void> _login() async {
    // Validazione form base
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (authResponse.session != null) {
        // LOGIN OK → vai alla mappa
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, "/map");
      } else {
        _showError("Credenziali non valide");
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showError("Inserisci l'email per reimpostare la password");
      return;
    }
    try {
      // TODO: imposta la redirect URL corretta nelle impostazioni di Supabase (Auth → URL)
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email inviata (se l'account esiste).")),
      );
    } on AuthException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // AppBar volutamente minimale (come nel mock: logo visibile sotto)
      appBar: AppBar(centerTitle: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  // --- HEADER con LOGO
                  Image.asset('assets/images/brand/logo.png', height: 56),
                  const SizedBox(height: 20),

                  // --- FORM
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: "Email address",
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return "Inserisci l'email";
                            }
                            if (!v.contains('@')) return "Email non valida";
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePwd,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePwd ? "Mostra password" : "Nascondi password",
                              icon: Icon(_obscurePwd ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                            ),
                          ),
                          onFieldSubmitted: (_) => _login(),
                          validator: (v) {
                            if (v == null || v.isEmpty) return "Inserisci la password";
                            return null;
                          },
                        ),

                        // --- "Password dimenticata?"
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _resetPassword,
                            child: const Text("Password dimenticata?"),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // --- CTA Login
                        SizedBox(
                          width: double.infinity,
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : FilledButton(
                                  onPressed: _login,
                                  child: const Text("Accedi"),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // --- Link a Signup
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Non hai un account?", style: theme.textTheme.bodyMedium),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/signup'),
                              child: const Text("Registrati"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Nota brand
                  Text(
                    "BagDrop — deposito bagagli semplice e sicuro",
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
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
