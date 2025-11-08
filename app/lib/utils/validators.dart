import 'package:flutter/material.dart';

/// Validator riutilizzabili (semplici e chiari).
class Validators {
  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Inserisci un’e-mail';
    if (!s.contains('@') || !s.contains('.')) return 'E-mail non valida';
    return null;
  }

  static String? password(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 6) return 'La password deve avere almeno 6 caratteri';
    return null;
  }

  static String? confermaPassword(String? v, TextEditingController ref) {
    final s = (v ?? '').trim();
    if (s != ref.text.trim()) return 'Le password non coincidono';
    return null;
  }
}
