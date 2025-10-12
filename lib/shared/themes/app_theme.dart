import 'package:flutter/material.dart';

class AppTheme {
  // Chilean-inspired color palette
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryRed = Color(0xFFD32F2F);
  static const Color primaryWhite = Color(0xFFFFFFFF);
  
  static const Color accentGreen = Color(0xFF388E3C);
  static const Color accentOrange = Color(0xFFFF9800);
  
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundDark = Color(0xFF121212);
  
  // Mobile-optimized dimensions
  static const double mobileMinTouchTarget = 48.0;
  static const double mobilePaddingSmall = 8.0;
  static const double mobilePaddingMedium = 16.0;
  static const double mobilePaddingLarge = 24.0;
  static const double mobileAppBarHeight = 56.0;
  static const double mobileBottomNavHeight = 56.0;
  static const double mobileFABSize = 56.0;
  static const double mobileIconSize = 24.0;
  static const double mobileIconSizeLarge = 32.0;
  
  // Mobile breakpoints
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 900.0;
  static const double desktopBreakpoint = 1200.0;
  
  // Mobile-friendly font sizes
  static const double mobileFontSizeSmall = 12.0;
  static const double mobileFontSizeMedium = 14.0;
  static const double mobileFontSizeLarge = 16.0;
  static const double mobileFontSizeTitle = 20.0;
  static const double mobileFontSizeHeadline = 24.0;
  
  // Responsive helper
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }
  
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }
  
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }
  
  static double responsivePadding(BuildContext context) {
    return isMobile(context) ? mobilePaddingMedium : mobilePaddingLarge;
  }
  
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    primaryColor: primaryBlue,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: accentGreen,
      surface: primaryWhite,
      background: backgroundLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryBlue,
      foregroundColor: primaryWhite,
      elevation: 2,
      toolbarHeight: mobileAppBarHeight,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: primaryWhite,
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.all(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: mobilePaddingMedium, vertical: mobilePaddingSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.symmetric(horizontal: mobilePaddingMedium, vertical: mobilePaddingSmall),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      sizeConstraints: BoxConstraints.tightFor(width: mobileFABSize, height: mobileFABSize),
    ),
  );
  
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    primaryColor: primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: accentGreen,
      surface: Color(0xFF1E1E1E),
      background: backgroundDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: primaryWhite,
      elevation: 2,
      toolbarHeight: mobileAppBarHeight,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: primaryWhite,
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(mobileMinTouchTarget, mobileMinTouchTarget),
        padding: const EdgeInsets.all(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade600),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: mobilePaddingMedium, vertical: mobilePaddingSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.symmetric(horizontal: mobilePaddingMedium, vertical: mobilePaddingSmall),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      sizeConstraints: BoxConstraints.tightFor(width: mobileFABSize, height: mobileFABSize),
    ),
  );
}