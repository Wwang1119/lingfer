import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared with the native-panel handoff. Colour names describe roles.
abstract final class LingferColors {
  static const background = Color(0xFFF6F6F3);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF222828);
  static const muted = Color(0xFF667073);
  static const accent = Color(0xFF365F70);
  static const tint = Color(0xFFEAF0F1);
  static const line = Color(0xFFE5E5EA);
  static const warning = Color(0xFF9B4525);
  static const warningSurface = Color(0xFFFFF1E9);

  // Compatibility for callers of the original presentation theme.
  static const green = accent;
  static const lightGreen = tint;
  static const lime = Color(0xFFF0E5CB);
  static const peach = warningSurface;
}

abstract final class LingferType {
  // The bundled display face is a small, fixed glyph subset. Dynamic book
  // titles and controls must use the platform's complete CJK interface fonts.
  // This is Flutter CupertinoTextThemeData's system text alias, not a font
  // asset name; non-Apple platforms use their complete system fallbacks.
  static const interfaceFontFamily = 'CupertinoSystemText';
  static const interfaceFontFallback = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];
  static const interfaceText = TextStyle(
    inherit: false,
    fontFamily: interfaceFontFamily,
    fontFamilyFallback: interfaceFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: LingferColors.ink,
    decoration: TextDecoration.none,
  );
  static const interfaceHeading = TextStyle(
    inherit: false,
    fontFamily: interfaceFontFamily,
    fontFamilyFallback: interfaceFontFallback,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: LingferColors.ink,
    decoration: TextDecoration.none,
  );
  static const heading = interfaceHeading;
  static const brandHeading = TextStyle(
    fontFamily: 'LingferDisplay',
    fontFamilyFallback: ['Songti SC', 'Noto Serif CJK SC', 'serif'],
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: LingferColors.ink,
  );
  static const reading = TextStyle(
    fontFamily: 'Georgia',
    fontFamilyFallback: ['Noto Serif', 'serif'],
    fontSize: 20,
    height: 1.85,
    letterSpacing: .1,
    color: LingferColors.ink,
  );
  static const word = TextStyle(
    fontFamily: 'Georgia',
    fontFamilyFallback: ['Noto Serif', 'serif'],
    fontSize: 27,
    height: 1.25,
    color: LingferColors.ink,
  );
}

ThemeData lingferTheme() {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(18)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: LingferColors.accent,
      onPrimary: Colors.white,
      secondary: LingferColors.accent,
      secondaryContainer: LingferColors.tint,
      onSecondaryContainer: LingferColors.accent,
      surface: LingferColors.paper,
      onSurface: LingferColors.ink,
      onSurfaceVariant: LingferColors.muted,
      outline: LingferColors.muted,
      outlineVariant: LingferColors.line,
      error: LingferColors.warning,
    ),
    scaffoldBackgroundColor: LingferColors.background,
    fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'sans-serif'],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: LingferType.interfaceFontFamily,
        fontSize: 32,
        height: 1.2,
        letterSpacing: -.8,
        fontWeight: FontWeight.w600,
        color: LingferColors.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: LingferType.interfaceFontFamily,
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: LingferColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: LingferColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: LingferColors.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.65,
        color: LingferColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.6,
        color: LingferColors.ink,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: LingferColors.muted,
      ),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: LingferColors.background,
      foregroundColor: LingferColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: LingferColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Color(0xDDE9EDF4),
      height: 66,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? LingferColors.accent
              : LingferColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? LingferColors.accent
              : LingferColors.muted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: LingferColors.paper,
      indicatorColor: LingferColors.tint,
      selectedIconTheme: IconThemeData(color: LingferColors.accent),
      selectedLabelTextStyle: TextStyle(
        color: LingferColors.accent,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: LingferColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LingferColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LingferColors.accent,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: LingferColors.line),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: LingferColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: LingferColors.accent,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LingferColors.paper,
      contentPadding: const EdgeInsets.all(16),
      hintStyle: const TextStyle(color: LingferColors.muted, fontSize: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: LingferColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: LingferColors.accent, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LingferColors.paper,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x401C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      showDragHandle: false,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: LingferColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: LingferColors.ink,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: LingferColors.accent,
      unselectedLabelColor: LingferColors.muted,
      indicatorColor: LingferColors.accent,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: LingferColors.tint,
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: LingferColors.line,
      thickness: .5,
      space: .5,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: LingferColors.accent,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: LingferColors.accent,
      selectionColor: Color(0x330066CC),
      selectionHandleColor: LingferColors.accent,
    ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      primaryColor: LingferColors.accent,
      brightness: Brightness.light,
    ),
  );
}
