import 'package:flutter/material.dart';

/// "Warm Paper Recall" design tokens.
///
/// Cream paper canvas, one terracotta accent, serif assistant voice / sans
/// chrome, warm dark mode. No gradients, no glass, no glow. The ColorScheme
/// is built BY HAND from [SiftColors] — `ColorScheme.fromSeed` is banned
/// because tonal tinting breaks flat paper.
///
/// Screen code reads colors via `AppTheme.of(context)` (the [SiftColors]
/// ThemeExtension) and type via [SiftType], avoiding M3 defaults entirely.

/// Radius lock: 0 nav/hairlines, 4 inline code, 12 thumbs/OCR/banners,
/// 16 fields/buttons, 20 cards/dialogs, 24 sheet top, full pills/chips.
abstract final class SiftRadii {
  SiftRadii._();

  static const double r0 = 0;
  static const double rInline = 4;
  static const double rThumb = 12;
  static const double rField = 16;
  static const double rCard = 20;
  static const double rSheet = 24;
}

/// 4pt base spacing rhythm. 20pt gutters, 32–48pt sections.
abstract final class SiftSpacing {
  SiftSpacing._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
  static const double s96 = 96;

  static const double gutter = 20;
  static const double gutterChat = 16;

  static const double btnH = 48;
  static const double navH = 64;
  static const double chipH = 32;
  static const double thumb = 48;
  static const double sendBtn = 40;
}

/// Warm shadows rgba(40,30,20,x). Light uses L1–L2 on cards; dark mode
/// eliminates shadows below L4 — hairlines separate layers instead.
abstract final class SiftElevation {
  SiftElevation._();

  static const List<BoxShadow> l1 = [
    BoxShadow(color: Color(0x0A281E14), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<BoxShadow> l2 = [
    BoxShadow(color: Color(0x0F281E14), offset: Offset(0, 2), blurRadius: 8),
  ];
  static const List<BoxShadow> l3 = [
    BoxShadow(color: Color(0x1A281E14), offset: Offset(0, 4), blurRadius: 16),
  ];
  static const List<BoxShadow> l4 = [
    BoxShadow(color: Color(0x24281E14), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const List<BoxShadow> l5 = [
    BoxShadow(color: Color(0x2E281E14), offset: Offset(0, -12), blurRadius: 32),
  ];
  static const List<BoxShadow> l4Dark = [
    BoxShadow(color: Color(0x15281E14), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// Cards: L1 in light, none in dark.
  static List<BoxShadow> card(bool isDark) => isDark ? const [] : l1;

  /// Sheets and dialogs: L4 in light, L4Dark in dark.
  static List<BoxShadow> sheet(bool isDark) => isDark ? l4Dark : l4;
}

/// Typographic roles. Serif (Source Serif 4) is the assistant voice and the
/// essayist headlines; sans is the system stack (never 'Inter'); mono is
/// JetBrains Mono and appears ONLY in the OCR block. Tabular figures on all
/// numeric/meta roles.
abstract final class SiftType {
  SiftType._();

  static const String serifFamily = 'SourceSerif4';
  static const String monoFamily = 'JetBrainsMono';

  // Serif — assistant voice + essayist headlines.
  static TextStyle get serifDisplay => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.4,
    fontVariations: [FontVariation('opsz', 30)],
  );

  static TextStyle get serifTitle => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.3,
    fontVariations: [FontVariation('opsz', 30)],
  );

  static TextStyle get serifHeadline => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
  );

  static TextStyle get serifSubhead => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  static TextStyle get serifSubhead2 => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static TextStyle get serifBody => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static TextStyle get serifSummary => const TextStyle(
    fontFamily: serifFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // Sans — system stack (no family override), all chrome.
  static TextStyle get bodySans => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static TextStyle get bodySansMd => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static TextStyle get chromeTitle => const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.1,
  );

  static TextStyle get buttonLabel => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  static TextStyle get chipLabel => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static TextStyle get metaLabel => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get microLabel => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get tabLabel => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Mono — OCR block only.
  static TextStyle get ocrMono => const TextStyle(
    fontFamily: monoFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  /// Add tabular figures for dates/numerals.
  static TextStyle tabular(TextStyle style) => style.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Full token palette as a ThemeExtension so every screen can read the whole
/// warm-paper ramp with one lookup. [SiftColors.light] and [SiftColors.dark]
/// are the two canonical instances; lerp exists for theme transitions.
class SiftColors extends ThemeExtension<SiftColors> {
  final Color canvas;
  final Color paper;
  final Color surfaceWarm1;
  final Color surfaceWarm2;
  final Color divider;
  final Color ink;
  final Color graphite;
  final Color stone;
  final Color bone;
  final Color accent;
  final Color accentDeep;
  final Color accentPressed;
  final Color accentSoft;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color codeBg;
  final Color codeText;
  final Color codeBorder;
  final Color badgeBg;
  final Color badgeText;
  final Color tagBorder;
  final Color tagText;
  final Color scrimPhoto;
  final Color barrier;

  const SiftColors({
    required this.canvas,
    required this.paper,
    required this.surfaceWarm1,
    required this.surfaceWarm2,
    required this.divider,
    required this.ink,
    required this.graphite,
    required this.stone,
    required this.bone,
    required this.accent,
    required this.accentDeep,
    required this.accentPressed,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.codeBg,
    required this.codeText,
    required this.codeBorder,
    required this.badgeBg,
    required this.badgeText,
    required this.tagBorder,
    required this.tagText,
    required this.scrimPhoto,
    required this.barrier,
  });

  static const SiftColors light = SiftColors(
    canvas: Color(0xFFF8F4ED),
    paper: Color(0xFFFBF9F4),
    surfaceWarm1: Color(0xFFF0EAE0),
    surfaceWarm2: Color(0xFFE8E0D2),
    divider: Color(0xFFDDD2BD),
    ink: Color(0xFF2D2520),
    graphite: Color(0xFF5A4F44),
    stone: Color(0xFF7A6E61),
    bone: Color(0xFFB5AB9E),
    accent: Color(0xFFD97757),
    accentDeep: Color(0xFFB04F2B),
    accentPressed: Color(0xFFBE6242),
    accentSoft: Color(0xFFF2DDD0),
    onAccent: Color(0xFFFBF9F4),
    success: Color(0xFF4E7C43),
    warning: Color(0xFF96600F),
    error: Color(0xFFA64A33),
    errorSoft: Color(0xFFF3E0DC),
    info: Color(0xFF6E6A62),
    codeBg: Color(0xFF1F1B16),
    codeText: Color(0xFFE8E0D2),
    codeBorder: Color(0xFFDDD2BD),
    badgeBg: Color(0xFFE8E0D2),
    badgeText: Color(0xFF5A4F44),
    tagBorder: Color(0xFFDDD2BD),
    tagText: Color(0xFF7A6E61),
    scrimPhoto: Color(0xAA1F1B16),
    barrier: Color(0x662D2520),
  );

  static const SiftColors dark = SiftColors(
    canvas: Color(0xFF1F1B16),
    paper: Color(0xFF2A2520),
    surfaceWarm1: Color(0xFF2A2520),
    surfaceWarm2: Color(0xFF3A332C),
    divider: Color(0xFF3A332C),
    ink: Color(0xFFE8E0D2),
    graphite: Color(0xFFB5AB9E),
    stone: Color(0xFF998D80),
    bone: Color(0xFF5A4F44),
    accent: Color(0xFFD97757),
    accentDeep: Color(0xFFB04F2B),
    accentPressed: Color(0xFFBE6242),
    accentSoft: Color(0xFF4A352A),
    onAccent: Color(0xFFFBF9F4),
    success: Color(0xFF7FB069),
    warning: Color(0xFFD49952),
    error: Color(0xFFD9846F),
    errorSoft: Color(0xFF4A2E28),
    info: Color(0xFFA49E93),
    codeBg: Color(0xFF161210),
    codeText: Color(0xFFE8E0D2),
    codeBorder: Color(0xFF3A332C),
    badgeBg: Color(0xFF3A332C),
    badgeText: Color(0xFFB5AB9E),
    tagBorder: Color(0xFF3A332C),
    tagText: Color(0xFF998D80),
    scrimPhoto: Color(0xAA1F1B16),
    barrier: Color(0x662D2520),
  );

  @override
  SiftColors copyWith({
    Color? canvas,
    Color? paper,
    Color? surfaceWarm1,
    Color? surfaceWarm2,
    Color? divider,
    Color? ink,
    Color? graphite,
    Color? stone,
    Color? bone,
    Color? accent,
    Color? accentDeep,
    Color? accentPressed,
    Color? accentSoft,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? error,
    Color? errorSoft,
    Color? info,
    Color? codeBg,
    Color? codeText,
    Color? codeBorder,
    Color? badgeBg,
    Color? badgeText,
    Color? tagBorder,
    Color? tagText,
    Color? scrimPhoto,
    Color? barrier,
  }) {
    return SiftColors(
      canvas: canvas ?? this.canvas,
      paper: paper ?? this.paper,
      surfaceWarm1: surfaceWarm1 ?? this.surfaceWarm1,
      surfaceWarm2: surfaceWarm2 ?? this.surfaceWarm2,
      divider: divider ?? this.divider,
      ink: ink ?? this.ink,
      graphite: graphite ?? this.graphite,
      stone: stone ?? this.stone,
      bone: bone ?? this.bone,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      info: info ?? this.info,
      codeBg: codeBg ?? this.codeBg,
      codeText: codeText ?? this.codeText,
      codeBorder: codeBorder ?? this.codeBorder,
      badgeBg: badgeBg ?? this.badgeBg,
      badgeText: badgeText ?? this.badgeText,
      tagBorder: tagBorder ?? this.tagBorder,
      tagText: tagText ?? this.tagText,
      scrimPhoto: scrimPhoto ?? this.scrimPhoto,
      barrier: barrier ?? this.barrier,
    );
  }

  @override
  SiftColors lerp(ThemeExtension<SiftColors>? other, double t) {
    if (other is! SiftColors) return this;
    return SiftColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      surfaceWarm1: Color.lerp(surfaceWarm1, other.surfaceWarm1, t)!,
      surfaceWarm2: Color.lerp(surfaceWarm2, other.surfaceWarm2, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      graphite: Color.lerp(graphite, other.graphite, t)!,
      stone: Color.lerp(stone, other.stone, t)!,
      bone: Color.lerp(bone, other.bone, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      codeBorder: Color.lerp(codeBorder, other.codeBorder, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      tagBorder: Color.lerp(tagBorder, other.tagBorder, t)!,
      tagText: Color.lerp(tagText, other.tagText, t)!,
      scrimPhoto: Color.lerp(scrimPhoto, other.scrimPhoto, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
    );
  }
}

/// App theme factory. Builds the hand-crafted ColorScheme, warm component
/// themes, and the essayist typography for both modes. `AppTheme.lightTheme`
/// and `AppTheme.darkTheme` keep their signatures so ThemeController is
/// untouched.
class AppTheme {
  AppTheme._();

  /// Convenience access to the active palette.
  static SiftColors of(BuildContext context) =>
      Theme.of(context).extension<SiftColors>() ?? SiftColors.light;

  /// Hairline width: 0.5pt in light, 1pt in dark.
  static double hairline(bool isDark) => isDark ? 1.0 : 0.5;

  static ThemeData get lightTheme => _build(Brightness.light, SiftColors.light);

  static ThemeData get darkTheme => _build(Brightness.dark, SiftColors.dark);

  static ThemeData _build(Brightness brightness, SiftColors s) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: s.accent,
      onPrimary: s.onAccent,
      primaryContainer: s.accentSoft,
      onPrimaryContainer: s.ink,
      secondary: s.accent,
      onSecondary: s.onAccent,
      secondaryContainer: s.accentSoft,
      onSecondaryContainer: s.ink,
      tertiary: s.accent,
      onTertiary: s.onAccent,
      tertiaryContainer: s.accentSoft,
      onTertiaryContainer: s.ink,
      error: s.error,
      onError: isDark ? s.canvas : s.paper,
      errorContainer: s.errorSoft,
      onErrorContainer: s.error,
      surface: s.canvas,
      onSurface: s.ink,
      surfaceDim: isDark ? s.canvas : s.surfaceWarm1,
      surfaceBright: s.paper,
      surfaceContainerLowest: s.canvas,
      surfaceContainerLow: s.paper,
      surfaceContainer: s.surfaceWarm1,
      surfaceContainerHigh: s.surfaceWarm2,
      surfaceContainerHighest: s.surfaceWarm2,
      onSurfaceVariant: s.graphite,
      outline: s.divider,
      outlineVariant: s.divider,
      shadow: const Color(0xFF281E14),
      scrim: s.barrier,
      inverseSurface: s.ink,
      onInverseSurface: s.paper,
      inversePrimary: s.accent,
      surfaceTint: Colors.transparent,
    );

    final textTheme = const TextTheme(
      displayLarge: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.4,
        fontVariations: [FontVariation('opsz', 30)],
      ),
      displayMedium: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.3,
        fontVariations: [FontVariation('opsz', 30)],
      ),
      headlineLarge: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.2,
      ),
      headlineMedium: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.1,
      ),
      headlineSmall: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.1,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        fontFamily: SiftType.serifFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
      bodySmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.0),
      labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.2),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ).apply(bodyColor: s.ink, displayColor: s.ink);

    final borderColor = s.divider;
    final borderWidth = hairline(isDark);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: s.canvas,
      canvasColor: s.canvas,
      textTheme: textTheme,
      extensions: [s],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: s.accent.withValues(alpha: 0.18),
      dividerColor: s.divider,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: s.ink,
        iconTheme: IconThemeData(color: s.ink),
        titleTextStyle: SiftType.chromeTitle.copyWith(color: s.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: s.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadii.rCard),
          side: BorderSide(color: borderColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.ink,
        contentTextStyle: TextStyle(
          color: isDark ? s.canvas : s.paper,
          fontSize: 14,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadii.rThumb),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.paper,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: s.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SiftRadii.rSheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SiftRadii.rCard),
        ),
        titleTextStyle: SiftType.serifHeadline.copyWith(color: s.ink),
        contentTextStyle: SiftType.bodySansMd.copyWith(color: s.graphite),
      ),
      dividerTheme: DividerThemeData(
        color: s.divider,
        thickness: borderWidth,
        space: borderWidth,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? s.paper : s.paper,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? s.accentDeep
              : s.surfaceWarm2,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, SiftSpacing.btnH)),
          maximumSize: const WidgetStatePropertyAll(Size.fromHeight(SiftSpacing.btnH)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SiftRadii.rField),
            ),
          ),
          textStyle: WidgetStatePropertyAll(SiftType.buttonLabel),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return s.surfaceWarm2;
            if (isDark) {
              return states.contains(WidgetState.pressed)
                  ? const Color(0xFFC9BFA9)
                  : s.ink;
            }
            return states.contains(WidgetState.pressed)
                ? s.accentPressed
                : s.accentDeep;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return s.stone;
            return isDark ? const Color(0xFF1F1B16) : s.onAccent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: s.accent, width: 1.5);
            }
            return BorderSide.none;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, SiftSpacing.btnH)),
          maximumSize: const WidgetStatePropertyAll(Size.fromHeight(SiftSpacing.btnH)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SiftRadii.rField),
            ),
          ),
          textStyle: WidgetStatePropertyAll(SiftType.buttonLabel),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? s.stone : s.ink,
          ),
          backgroundColor: WidgetStatePropertyAll(s.paper),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused) ? s.accent : s.divider,
              width: states.contains(WidgetState.focused) ? 1.5 : 1,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SiftRadii.rField),
            ),
          ),
          textStyle: WidgetStatePropertyAll(SiftType.buttonLabel),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? s.stone : s.ink,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      iconTheme: IconThemeData(color: s.graphite, size: 22),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: s.accent,
        selectionColor: s.accentSoft,
        selectionHandleColor: s.accent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.accent,
        linearTrackColor: s.surfaceWarm2,
        circularTrackColor: s.surfaceWarm2,
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
