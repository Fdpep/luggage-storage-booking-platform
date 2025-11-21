import 'package:flutter_dotenv/flutter_dotenv.dart';
// Legge URL e ANON KEY passati via --dart-define  dal runtime (VS Code launch.json o riga di comando)
class SupabaseConfig {
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static bool get ok => url.isNotEmpty && anonKey.isNotEmpty;
}
