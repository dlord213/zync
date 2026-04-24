import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zync/router/app_router.dart';
import 'package:zync/providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for desktop platforms
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ProviderScope(child: ZyncApp()));
}

// --- Design System Constants ---
class ZyncTheme {
  static const Color amoledBlack = Color(0xFF000000);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceVariant = Color(0xFF232323);
  static const Color orange = Color(0xFFFF6B35);
  static const Color orangeDim = Color(0xFF3D2B1F);
  static const Color green = Color(0xFF34C759);
  static const Color greenDim = Color(0xFF1A3022);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const double radius = 28.0;
  static const double radiusSm = 18.0;
}

class ZyncApp extends ConsumerWidget {
  const ZyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: ZyncTheme.orange,
      brightness: Brightness.dark,
    ).copyWith(
      surface: ZyncTheme.amoledBlack,
      onSurface: ZyncTheme.textPrimary,
    );

    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: ZyncTheme.orange,
      brightness: Brightness.light,
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: darkColorScheme,
      scaffoldBackgroundColor: ZyncTheme.amoledBlack,
      appBarTheme: const AppBarTheme(
        backgroundColor: ZyncTheme.amoledBlack,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ZyncTheme.textPrimary,
        titleTextStyle: TextStyle(
          color: ZyncTheme.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: ZyncTheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZyncTheme.radius),
        ),
      ),
      iconTheme: const IconThemeData(color: ZyncTheme.textPrimary),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: ZyncTheme.textPrimary,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        titleLarge: TextStyle(
          color: ZyncTheme.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: ZyncTheme.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: ZyncTheme.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: ZyncTheme.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2C2E),
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ZyncTheme.surface,
        contentTextStyle: const TextStyle(color: ZyncTheme.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZyncTheme.radiusSm),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: lightColorScheme,
    );

    return MaterialApp.router(
      title: 'Zync',
      themeMode: themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
