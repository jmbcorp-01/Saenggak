import 'package:material_ui/material_ui.dart';

/// Design tokens from the approved third design round.
class SgColors {
  SgColors._();

  static const ink = Color(0xFF151515);
  static const muted = Color(0xFF6B6B6B);
  static const line = Color(0xFFEBEBEB);
  static const outline = Color(0xFFCFCFCF);
  static const surface = Color(0xFFFFFFFF);
  static const band = Color(0xFFF3EFE9);
  static const bandMark = Color(0xFFE5DED3);

  /// Symbol, write button, active empathy, progress.
  static const accent = Color(0xFFD2452C);

  /// Accent used for text, darker so it passes 4.5:1 on white.
  static const accentText = Color(0xFFB8361F);
}

class SgFonts {
  SgFonts._();

  /// Body and interface. Bundled in assets/fonts with Hangul and Latin; other
  /// scripts (for example Han characters) fall back to the platform font.
  static const sans = 'Noto Sans KR';

  /// Typing time and timer.
  static const mono = 'IBM Plex Mono';

  static const sansFallback = ['Apple SD Gothic Neo', 'Roboto', 'sans-serif'];

  /// Plex Mono has no Hangul, so "2분 18초" takes its Hangul from Noto Sans KR
  /// on every platform instead of whatever the system picks.
  static const monoFallback = [sans, 'Menlo', 'Roboto Mono', 'monospace'];
}

class SgText {
  SgText._();

  static const body = TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15.5,
    height: 1.6,
    color: SgColors.ink,
  );

  static const name = TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: SgColors.ink,
  );

  static const meta = TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15,
    color: SgColors.muted,
  );

  static const small = TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 13,
    color: SgColors.muted,
  );

  /// Button labels. Buttons do not inherit the theme font when given their own
  /// text style, so every button uses this.
  static TextStyle label({double size = 15, FontWeight weight = FontWeight.w700}) =>
      TextStyle(fontFamily: SgFonts.sans, fontFamilyFallback: SgFonts.sansFallback, fontSize: size, fontWeight: weight);

  static const mono = TextStyle(
    fontFamily: SgFonts.mono,
    fontFamilyFallback: SgFonts.monoFallback,
    fontSize: 11.5,
    color: SgColors.muted,
  );
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: SgColors.surface,
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    colorScheme: ColorScheme.fromSeed(seedColor: SgColors.accent, primary: SgColors.ink, surface: SgColors.surface),
    dividerColor: SgColors.line,
    dividerTheme: const DividerThemeData(color: SgColors.line, thickness: 1, space: 1),
    splashFactory: NoSplash.splashFactory,
    navigationBarTheme: NavigationBarThemeData(
      iconTheme: WidgetStateProperty.resolveWith(
        (states) =>
            IconThemeData(size: 26, color: states.contains(WidgetState.selected) ? SgColors.ink : SgColors.muted),
      ),
    ),
    // Buttons resolve their own text style, so the font is set here too.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: SgText.label(weight: FontWeight.w500)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(textStyle: SgText.label())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(textStyle: SgText.label())),
    appBarTheme: const AppBarTheme(
      backgroundColor: SgColors.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: SgColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    tooltipTheme: const TooltipThemeData(
      textStyle: TextStyle(fontFamily: SgFonts.sans, color: Colors.white, fontSize: 13),
    ),
  );
}
