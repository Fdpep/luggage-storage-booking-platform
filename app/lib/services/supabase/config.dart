// Legge URL e ANON KEY passati via --dart-define  dal runtime (VS Code launch.json o riga di comando)
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get ok => url.isNotEmpty && anonKey.isNotEmpty;
}
