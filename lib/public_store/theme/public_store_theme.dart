import 'package:flutter/material.dart';

/// Professional light theme for the public-facing store
/// Inspired by vinabike.cl - clean, trustworthy, modern
class PublicStoreTheme {
  // Brand Colors (Professional Blues & Grays)
  static const Color primaryBlue = Color(0xFF2563EB); // Professional blue
  static const Color secondaryGray = Color(0xFF64748B); // Elegant gray
  static const Color accentGreen = Color(0xFF25D366); // WhatsApp green
  
  // Background Colors (Light & Clean)
  static const Color background = Color(0xFFFFFFFF); // Pure white
  static const Color surface = Color(0xFFF8FAFC); // Subtle off-white
  static const Color cardBackground = Colors.white;
  
  // Text Colors (Easy to Read)
  static const Color textPrimary = Color(0xFF1E293B); // Dark gray
  static const Color textSecondary = Color(0xFF64748B); // Medium gray
  static const Color textMuted = Color(0xFF94A3B8); // Light gray
  
  // Accent Colors
  static const Color success = Color(0xFF10B981); // Green for success
  static const Color successGreen = Color(0xFF10B981); // Alias for compatibility
  static const Color warning = Color(0xFFF59E0B); // Orange for warnings
  static const Color warningYellow = Color(0xFFF59E0B); // Alias for compatibility
  static const Color error = Color(0xFFEF4444); // Red for errors
  static const Color errorRed = Color(0xFFEF4444); // Alias for compatibility
  static const Color info = Color(0xFF3B82F6); // Blue for info
  
  // UI Elements
  static const Color divider = Color(0xFFE2E8F0);
  static const Color border = Color(0xFFCBD5E1);
  static const Color shadow = Color(0x1A000000); // 10% black
  
  // Hero Overlay
  static const Color heroOverlay = Color(0x99000000); // 60% black overlay for hero text
  
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      
      // Color Scheme
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: secondaryGray,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      
      // Scaffold
      scaffoldBackgroundColor: background,
      
      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      
      // Card
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 2,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(8),
      ),
      
      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: const BorderSide(color: primaryBlue, width: 2),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: textMuted),
      ),
      
      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        deleteIconColor: textSecondary,
        disabledColor: divider,
        selectedColor: primaryBlue.withOpacity(0.2),
        secondarySelectedColor: secondaryGray.withOpacity(0.2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(color: textPrimary),
        secondaryLabelStyle: const TextStyle(color: textSecondary),
        brightness: Brightness.light,
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      
      // Icon
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),
      
      // Text Theme
      textTheme: const TextTheme(
        // Display (Hero Text)
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -1,
        ),
        displayMedium: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        
        // Headlines
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        
        // Titles
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        
        // Body
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textSecondary,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: textMuted,
          height: 1.5,
        ),
        
        // Labels
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textMuted,
        ),
      ),
    );
  }
  
  // Shadow for Cards
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadow,
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
  
  // Shadow for Floating Elements
  static List<BoxShadow> get floatingShadow => [
    BoxShadow(
      color: shadow,
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
