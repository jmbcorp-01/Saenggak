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

  /// Body and interface. Bundled font files are a follow-up; until then the
  /// platform's Korean sans-serif is used as the fallback.
  static const sans = 'Noto Sans KR';

  /// Typing time and timer.
  static const mono = 'IBM Plex Mono';

  static const sansFallback = ['Apple SD Gothic Neo', 'Roboto', 'sans-serif'];
  static const monoFallback = ['Menlo', 'Roboto Mono', 'monospace'];
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
    colorScheme: ColorScheme.fromSeed(
      seedColor: SgColors.accent,
      primary: SgColors.ink,
      surface: SgColors.surface,
    ),
    dividerColor: SgColors.line,
    splashFactory: NoSplash.splashFactory,
  );
}
