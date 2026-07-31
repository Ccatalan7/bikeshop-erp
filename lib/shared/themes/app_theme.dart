import 'package:flutter/material.dart';

import 'appearance_preset.dart';
import 'vinabike_theme_resolver.dart';

class AppTheme {
  // Chilean-inspired color palette
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryRed = Color(0xFFD32F2F);
  static const Color primaryWhite = Color(0xFFFFFFFF);

  static const Color secondarySteel = Color(0xFF40566B);
  static const Color accentOrange = Color(0xFFFF9800);

  static const Color backgroundLight = Color(0xFFEEF1F5);
  static const Color backgroundDark = Color(0xFF0E1216);

  // Dark mode specific colors (professional, minimal)
  static const Color surfaceDark = Color(0xFF14181D);
  static const Color cardDark = Color(0xFF1F252C);
  static const Color borderDark = Color(0xFF3D4753);
  static const Color textPrimaryDark = Color(0xFFE4E8EE);
  static const Color textSecondaryDark = Color(0xFFA6B0BE);

  // Neutral surface ladder.
  //
  // Material 3 falls back to `surface` for every container role that a scheme
  // leaves unset, and to `onSurface` for `onSurfaceVariant`. A scheme that
  // declares only primary/secondary/surface therefore renders every panel as
  // pure white and every secondary label at full text weight, which removes
  // depth and typographic hierarchy from the entire application. These roles
  // are declared explicitly so grouping, elevation and secondary text read as
  // one coherent system.
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceDim = Color(0xFFCDD5DE);
  static const Color _lightSurfaceContainerLow = Color(0xFFF7F8FA);
  static const Color _lightSurfaceContainer = Color(0xFFEEF1F5);
  static const Color _lightSurfaceContainerHigh = Color(0xFFEEF1F4);
  static const Color _lightSurfaceContainerHighest = Color(0xFFE2E7ED);
  static const Color _lightOnSurface = Color(0xFF10243A);
  static const Color _lightOnSurfaceVariant = Color(0xFF4A5B6B);
  static const Color _lightOutline = Color(0xFFCDD5DE);

  // Calibrated so a hairline still reads after feature code dilutes it.
  //
  // Roughly 160 call sites draw boundaries as
  // `outlineVariant.withValues(alpha: 0.2..0.6)`. Those alphas were chosen
  // while the role was undeclared and resolved to near-black, so a correct but
  // pale hairline makes every one of them disappear — a table of rows collapses
  // into one undivided block. The role therefore carries enough weight to
  // survive that dilution while still reading as a hairline at full strength.
  static const Color _lightOutlineVariant = Color(0xFFE2E7ED);

  static const Color _darkSurfaceContainerLow = Color(0xFF1A1F25);
  static const Color _darkSurfaceContainerHigh = Color(0xFF262D36);
  static const Color _darkSurfaceContainerHighest = Color(0xFF2E3742);
  static const Color _darkOutline = Color(0xFF6B7684);

  /// Resolves the canonical ERP theme for one persisted preset and brightness.
  ///
  /// [lightTheme] and [darkTheme] remain compatibility defaults for secondary
  /// app hosts. The authenticated ERP root must use this resolver so changing
  /// the appearance preset updates the complete mounted theme.
  static ThemeData resolve({
    required AppearancePreset preset,
    required Brightness brightness,
  }) {
    return VinabikeThemeResolver.resolve(
      baseTheme: brightness == Brightness.dark ? darkTheme : lightTheme,
      preset: preset,
      brightness: brightness,
    );
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: backgroundLight,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      onPrimary: primaryWhite,
      primaryContainer: Color(0xFFD9E7F8),
      onPrimaryContainer: Color(0xFF0B3D6E),
      secondary: secondarySteel,
      onSecondary: primaryWhite,
      secondaryContainer: Color(0xFFE1E7EE),
      onSecondaryContainer: Color(0xFF26333F),
      tertiary: Color(0xFFB26A00),
      onTertiary: primaryWhite,
      tertiaryContainer: Color(0xFFFDECD2),
      onTertiaryContainer: Color(0xFF4A2C00),
      error: primaryRed,
      onError: primaryWhite,
      errorContainer: Color(0xFFFBE3E3),
      onErrorContainer: Color(0xFF6B1414),
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightOnSurfaceVariant,
      surfaceDim: _lightSurfaceDim,
      surfaceBright: _lightSurface,
      surfaceContainerLowest: _lightSurface,
      surfaceContainerLow: _lightSurfaceContainerLow,
      surfaceContainer: _lightSurfaceContainer,
      surfaceContainerHigh: _lightSurfaceContainerHigh,
      surfaceContainerHighest: _lightSurfaceContainerHighest,
      outline: _lightOutline,
      outlineVariant: _lightOutlineVariant,
      surfaceTint: primaryBlue,
      inverseSurface: Color(0xFF283039),
      onInverseSurface: Color(0xFFF1F3F7),
      inversePrimary: Color(0xFF9CC7F4),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryBlue,
      foregroundColor: primaryWhite,
      elevation: 2,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primaryWhite,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: primaryWhite,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: primaryWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      color: primaryWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade300,
      thickness: 1,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryBlue.withValues(alpha: 0.1);
        }
        return null;
      }),
      dividerThickness: 1,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: backgroundDark,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      onPrimary: primaryWhite,
      primaryContainer: Color(0xFF10365C),
      onPrimaryContainer: Color(0xFFCFE3FA),
      secondary: Color(0xFF8FA6BC),
      onSecondary: Color(0xFF17222D),
      secondaryContainer: Color(0xFF2C3B4A),
      onSecondaryContainer: Color(0xFFD5E0EB),
      tertiary: Color(0xFFE0A040),
      onTertiary: Color(0xFF2E1B00),
      tertiaryContainer: Color(0xFF4A3007),
      onTertiaryContainer: Color(0xFFFAE3BE),
      error: Color(0xFFEF5350),
      onError: Color(0xFF2B0505),
      errorContainer: Color(0xFF5A1414),
      onErrorContainer: Color(0xFFFBD9D9),
      surface: surfaceDark,
      onSurface: textPrimaryDark,
      onSurfaceVariant: textSecondaryDark,
      surfaceDim: backgroundDark,
      surfaceBright: Color(0xFF343C46),
      surfaceContainerLowest: backgroundDark,
      surfaceContainerLow: _darkSurfaceContainerLow,
      surfaceContainer: cardDark,
      surfaceContainerHigh: _darkSurfaceContainerHigh,
      surfaceContainerHighest: _darkSurfaceContainerHighest,
      outline: _darkOutline,
      outlineVariant: borderDark,
      surfaceTint: primaryBlue,
      inverseSurface: Color(0xFFE4E8EE),
      onInverseSurface: Color(0xFF1A1F25),
      inversePrimary: Color(0xFF1565C0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceDark,
      foregroundColor: textPrimaryDark,
      elevation: 2,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimaryDark,
      ),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: surfaceDark,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: primaryWhite,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: cardDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      color: cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: borderDark,
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: textPrimaryDark,
      iconColor: textSecondaryDark,
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(cardDark),
      dataRowColor: WidgetStatePropertyAll(surfaceDark),
      dividerThickness: 1,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textPrimaryDark),
      bodyMedium: TextStyle(color: textPrimaryDark),
      bodySmall: TextStyle(color: textSecondaryDark),
      labelLarge: TextStyle(color: textPrimaryDark),
      labelMedium: TextStyle(color: textSecondaryDark),
      labelSmall: TextStyle(color: textSecondaryDark),
    ),
  );
}
