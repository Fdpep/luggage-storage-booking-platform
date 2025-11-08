import 'package:shared_preferences/shared_preferences.dart';

/// Memorizza e recupera l’ultima e-mail usata (prefill automatico).
class LastEmailStore {
  static const _k = 'bagdrop_last_email';

  static Future<void> save(String email) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, email.trim());
  }

  static Future<String?> load() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_k);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
