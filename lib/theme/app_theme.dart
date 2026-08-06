import 'package:flutter/material.dart';

/// Motion tokens — all durations settle under 500ms and collapse to zero
/// when the system requests reduced motion.
class Motion {
  Motion._();

  /// Set from the MaterialApp builder when a reduced-motion preference is active.
  static bool reduced = false;

  static bool get enabled => !reduced;

  static Duration get standard =>
      reduced ? Duration.zero : const Duration(milliseconds: 200);
  static Duration get emphasis =>
      reduced ? Duration.zero : const Duration(milliseconds: 300);
  static Duration get press =>
      reduced ? Duration.zero : const Duration(milliseconds: 60);
}

/// "Ember & Porcelain" design tokens. Cool porcelain light / warm charcoal dark,
/// one warm "ember" accent used as solid ink, and a single neutral tag system.
class AppTheme {
  AppTheme._();

  // Radius / control tokens
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rXl = 20;
  static const double r2xl = 24;

  static const double btnH = 52;
  static const double navH = 68;
  static const double chipH = 32;
  static const double thumb = 48;
  static const double sendBtn = 44;

  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;
  static const double space64 = 64;

  static const double gutter = 20;
  static const double gutterChat = 16;

  // Ember accent family
  static const Color emberDeep = Color(0xFFC13A12);
  static const Color emberMain = Color(0xFFE14E1C);
  static const Color emberBright = Color(0xFFFF7043);
  static const Color emberInk = Color(0xFFF2EFE9);

  // Semantic (light / dark)
  static const Color successLight = Color(0xFF167A44);
  static const Color successDark = Color(0xFF4CD787);
  static const Color warningLight = Color(0xFFA66A00);
  static const Color warningDark = Color(0xFFF0B429);
  static const Color errorLight = Color(0xFFC62F2F);
  static const Color errorDark = Color(0xFFF26060);
  static const Color infoLight = Color(0xFF3366CC);
  static const Color infoDark = Color(0xFF6BA3F5);

  // Tag system (single neutral tag)
  static const Color tagTextLight = Color(0xFF5A626C);
  static const Color tagTextDark = Color(0xFFBDB8AF);
  static const Color tagFillLight = Color(0xFFEEF0F3);
  static const Color tagFillDark = Color(0xFF2B2923);

  // Neutral stacks
  static const Color inkLight = Color(0xFF17191D);
  static const Color inkDark = Color(0xFFF2EFE9);
  static const Color slateLight = Color(0xFF5B626B);
  static const Color slateDark = Color(0xFFB9B3A9);
  static const Color ashLight = Color(0xFF8A9199);
  static const Color ashDark = Color(0xFF8D887E);
  static const Color bgLight = Color(0xFFF6F7F9);
  static const Color bgDark = Color(0xFF181715);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF211F1B);
  static const Color raisedLight = Color(0xFFFFFFFF);
  static const Color raisedDark = Color(0xFF282520);
  static const Color hairLight = Color(0xFFE7EAEE);
  static const Color hairDark = Color(0xFF3A372F);
  static const Color surfaceContainerLight = Color(0xFFF1F2F4);
  static const Color surfaceContainerDark = Color(0xFF282520);

  /// The single raised-layer shadow token.
  static List<BoxShadow> raisedShadow(bool isDark) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.4)
            : const Color(0xFF17191D).withValues(alpha: 0.06),
        blurRadius: isDark ? 32 : 24,
        offset: isDark ? const Offset(0, 12) : const Offset(0, 8),
      ),
    ];
  }

  /// Add tabular figures for dates/numerals (kept OFF the OCR mono block).
  static TextStyle tabular(TextStyle style) {
    return style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: emberDeep,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      primary: emberDeep,
      onPrimary: emberInk,
      secondary: emberMain,
      secondaryContainer: const Color(0xFFFFFFFF),
      onSecondaryContainer: inkLight,
      surface: const Color(0xFFFFFFFF),
      onSurface: inkLight,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF6F7F9),
      surfaceContainer: const Color(0xFFF1F2F4),
      surfaceContainerHigh: const Color(0xFFE9ECEF),
      surfaceContainerHighest: const Color(0xFFE9ECEF),
      onSurfaceVariant: const Color(0xFF5C6270),
      outline: const Color(0xFFD9DEE4),
      outlineVariant: const Color(0xFFE7EAEE),
      error: const Color(0xFFB3261E),
      onError: const Color(0xFFFFFFFF),
      inverseSurface: inkLight,
      onInverseSurface: const Color(0xFFF6F7F9),
      surfaceTint: Colors.transparent,
    );

    return _buildTheme(Brightness.light, scheme, bgLight);
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: emberDeep,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      primary: emberBright,
      onPrimary: const Color(0xFF181715),
      secondary: emberBright,
      secondaryContainer: const Color(0xFF211F1B),
      onSecondaryContainer: emberInk,
      surface: const Color(0xFF211F1B),
      onSurface: emberInk,
      surfaceContainerLowest: const Color(0xFF181715),
      surfaceContainerLow: const Color(0xFF211F1B),
      surfaceContainer: const Color(0xFF282520),
      surfaceContainerHigh: const Color(0xFF282520),
      surfaceContainerHighest: const Color(0xFF302C26),
      onSurfaceVariant: const Color(0xFFB9B3A9),
      outline: const Color(0xFF3A372F),
      outlineVariant: const Color(0xFF3A372F),
      error: const Color(0xFFF26060),
      onError: const Color(0xFF181715),
      inverseSurface: emberInk,
      onInverseSurface: const Color(0xFF211F1B),
      surfaceTint: Colors.transparent,
    );

    return _buildTheme(Brightness.dark, scheme, bgDark);
  }

  static ThemeData _buildTheme(
    Brightness brightness,
    ColorScheme scheme,
    Color scaffoldColor,
  ) {
    final ink = brightness == Brightness.dark ? inkDark : inkLight;
    final isDark = brightness == Brightness.dark;

    final textTheme = const TextTheme(
      displayLarge: TextStyle(
          fontSize: 40, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1.0),
      displayMedium: TextStyle(
          fontSize: 34, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.8),
      headlineLarge: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.6),
      headlineMedium: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.3),
      headlineSmall: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.2),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.55),
      bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.55),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    ).apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldColor,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? surfaceDark : surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rXl),
          side: BorderSide(color: isDark ? hairDark : hairLight),
        ),
        margin: EdgeInsets.zero,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? surfaceDark : surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(r2xl)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, btnH),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? raisedDark : raisedLight;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return ink;
            return isDark ? slateDark : slateLight;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: isDark ? hairDark : hairLight),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          ),
        ),
      ),
    );
  }

  /// Neutral human-readable label for a screenshot type. Not a color map.
  static String typeLabel(String? type) {
    switch (type) {
      case 'flight':
        return 'Flight';
      case 'recipe':
        return 'Recipe';
      case 'deadline':
        return 'Deadline';
      case 'product':
        return 'Product';
      case 'meeting':
        return 'Meeting';
      case 'shopping':
        return 'Shopping';
      case 'document':
        return 'Document';
      default:
        return 'Other';
    }
  }
}