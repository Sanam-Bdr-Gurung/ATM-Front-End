import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const ChordAssistApp());
}

class ChordAssistApp extends StatelessWidget {
  const ChordAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Dark "stage" look with a warm amber accent. Colors stay derived
    // from the Material color scheme so text contrast keeps passing
    // the accessibility guideline tests.
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFA726),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF1C1723),
          onSurface: const Color(0xFFF2EDF7),
        );

    return MaterialApp(
      title: 'Chord Assist',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF120E18),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF120E18),
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: colorScheme.primary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1C1723),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          margin: EdgeInsets.zero,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
