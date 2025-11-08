import 'package:flutter/material.dart';

/// Tema dell’app BagDrop (Stowee)
/// - Colori brand: viola #4E40CA, giallo #F9CC21
/// - Fornisce un ThemeData coerente (Material 3 ok)
class AppTheme {
  // Colori brand
  static const Color brandPurple = Color(0xFF4E40CA);
  static const Color brandYellow = Color(0xFFF9CC21);

  /// ColorScheme di base (chiaro)
  static const ColorScheme _scheme = ColorScheme(
    brightness: Brightness.light,
    primary: brandPurple,
    onPrimary: Colors.white,
    secondary: brandYellow,
    onSecondary: Colors.black,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    background: Color(0xFFF7F7FB),
    onBackground: Color(0xFF111111),
    surface: Colors.white,
    onSurface: Color(0xFF222222),
    // Non usati direttamente ma richiesti da ColorScheme completo:
    tertiary: Color(0xFF3D3B4E),
    onTertiary: Colors.white,
    surfaceVariant: Color(0xFFE6E6F2),
    outline: Color(0xFFB7B7C8),
    outlineVariant: Color(0xFFDADBE7),
    shadow: Colors.black26,
    scrim: Colors.black54,
    inverseSurface: Color(0xFF2B2B34),
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFB6AEFF),
  );

  /// ThemeData principale
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _scheme,
      scaffoldBackgroundColor: _scheme.background,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _scheme.primary,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
