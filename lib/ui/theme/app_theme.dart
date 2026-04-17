import 'package:flutter/material.dart';

/// Woosoo brand colours and Material 3 colour scheme.
///
/// Primary warm gold  : #F6B56D
/// Dark background    : #121212
class WoosooTheme {
  WoosooTheme._();

  static const Color brandGold = Color(0xFFF6B56D);
  static const Color brandDark = Color(0xFF1A1A1A);

  static final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: brandGold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: brandGold,
    onPrimary: brandDark,
    secondary: const Color(0xFFFFCC99),
    tertiary: const Color(0xFF66BB6A),   // success / connected
    error: const Color(0xFFEF5350),      // error / disconnected
    surface: const Color(0xFF1E1E1E),
    onSurface: const Color(0xFFE5E5E5),
    surfaceContainerHighest: const Color(0xFF2A2A2A),
    outline: const Color(0xFF616161),
  );

  static ThemeData get themeData => ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1E1E1E),
          indicatorColor: brandGold.withAlpha(51),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: brandGold);
            }
            return const IconThemeData(color: Color(0xFF9E9E9E));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: brandGold, fontWeight: FontWeight.w600, fontSize: 11);
            }
            return const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11);
          }),
        ),
      );
}
