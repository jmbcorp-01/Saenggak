import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

/// One set of colors. The app has a light and a dark one; [SgColors] reads
/// whichever is in use.
class SgPalette {
  const SgPalette({
    required this.brightness,
    required this.ink,
    required this.muted,
    required this.line,
    required this.outline,
    required this.surface,
    required this.raised,
    required this.band,
    required this.bandMark,
    required this.accent,
    required this.accentText,
    required this.hover,
    required this.pressed,
    required this.skeleton,
    required this.scrim,
  });

  final Brightness brightness;
  final Color ink;
  final Color muted;
  final Color line;
  final Color outline;
  final Color surface;

  /// Cards, sheets and the side panels' boxes: a step off the background.
  final Color raised;
  final Color band;
  final Color bandMark;
  final Color accent;
  final Color accentText;

  /// Row background under the mouse, and while a finger is down.
  final Color hover;
  final Color pressed;
  final Color skeleton;

  /// Behind the sticky header's blur.
  final Color scrim;

  /// From the approved third design round.
  static const light = SgPalette(
    brightness: Brightness.light,
    ink: Color(0xFF151515),
    muted: Color(0xFF6B6B6B),
    line: Color(0xFFEBEBEB),
    outline: Color(0xFFCFCFCF),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF7F5F2),
    band: Color(0xFFF3EFE9),
    bandMark: Color(0xFFE5DED3),
    accent: Color(0xFFD2452C),
    // Darker so it passes 4.5:1 on white.
    accentText: Color(0xFFB8361F),
    hover: Color(0x08151515),
    pressed: Color(0x12151515),
    skeleton: Color(0xFFEFECE8),
    scrim: Color(0xD9FFFFFF),
  );

  /// Warm near-black rather than pure black, so the paper feel carries over.
  static const dark = SgPalette(
    brightness: Brightness.dark,
    ink: Color(0xFFEDEAE5),
    muted: Color(0xFF9C978F),
    line: Color(0xFF2B2926),
    outline: Color(0xFF45413C),
    surface: Color(0xFF121110),
    raised: Color(0xFF1C1A18),
    band: Color(0xFF221F1C),
    bandMark: Color(0xFF2F2B27),
    accent: Color(0xFFE2573D),
    // Lighter so it passes 4.5:1 on the dark surface.
    accentText: Color(0xFFF08A73),
    hover: Color(0x0AFFFFFF),
    pressed: Color(0x14FFFFFF),
    skeleton: Color(0xFF242220),
    scrim: Color(0xD9121110),
  );
}

/// Colors for the palette in use. They are getters, not constants, so a
/// widget picks up the new palette when the app switches between light and
/// dark (the app rebuilds every widget when that happens).
class SgColors {
  SgColors._();

  static SgPalette _p = SgPalette.light;
  static SgPalette get palette => _p;
  static void use(SgPalette p) => _p = p;
  static bool get isDark => _p.brightness == Brightness.dark;

  static Color get ink => _p.ink;
  static Color get muted => _p.muted;
  static Color get line => _p.line;
  static Color get outline => _p.outline;
  static Color get surface => _p.surface;
  static Color get raised => _p.raised;
  static Color get band => _p.band;
  static Color get bandMark => _p.bandMark;

  /// Symbol, write button, active empathy, progress.
  static Color get accent => _p.accent;

  /// Accent used for text.
  static Color get accentText => _p.accentText;
  static Color get hover => _p.hover;
  static Color get pressed => _p.pressed;
  static Color get skeleton => _p.skeleton;
  static Color get scrim => _p.scrim;

  /// Text and icons on [accent] or on an [ink] fill.
  static const onAccent = Color(0xFFFFFFFF);
  static Color get onInk => _p.surface;
}

/// Spacing on a 4px grid.
class SgSpace {
  SgSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class SgRadius {
  SgRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// How long things move and how. Short and soft: the app should feel quick,
/// never bouncy.
class SgMotion {
  SgMotion._();

  /// Hover and press highlights.
  static const fast = Duration(milliseconds: 120);

  /// Buttons, counters, small state changes.
  static const medium = Duration(milliseconds: 220);

  /// Panels, sheets, headers sliding away.
  static const slow = Duration(milliseconds: 320);

  static const ease = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutQuart;
  static const spring = Curves.easeOutBack;
}

/// Widths where the layout changes.
class SgBreakpoints {
  SgBreakpoints._();

  /// Below this: phone layout with the bottom menu.
  static const rail = 600.0;

  /// From here the left menu shows its labels.
  static const wide = 1000.0;

  /// From here the right panel appears.
  static const full = 1240.0;

  /// The timeline column on tablets and computers.
  static const column = 600.0;
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

  static TextStyle get body => TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15.5,
    height: 1.6,
    letterSpacing: -0.1,
    color: SgColors.ink,
  );

  static TextStyle get name => TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: SgColors.ink,
  );

  static TextStyle get meta => TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 15,
    color: SgColors.muted,
  );

  static TextStyle get small => TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 13,
    color: SgColors.muted,
  );

  /// Screen and panel headings.
  static TextStyle get title => TextStyle(
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: SgColors.ink,
  );

  /// Button labels. Buttons do not inherit the theme font when given their own
  /// text style, so every button uses this.
  static TextStyle label({double size = 15, FontWeight weight = FontWeight.w700}) =>
      TextStyle(fontFamily: SgFonts.sans, fontFamilyFallback: SgFonts.sansFallback, fontSize: size, fontWeight: weight);

  static TextStyle get mono => TextStyle(
    fontFamily: SgFonts.mono,
    fontFamilyFallback: SgFonts.monoFallback,
    fontSize: 11.5,
    color: SgColors.muted,
  );
}

/// The menu's icons, all from one outlined family with a filled form for the
/// selected tab.
class SgIcons {
  SgIcons._();

  static const home = Icons.home_outlined;
  static const homeActive = Icons.home_rounded;
  static const bell = Icons.notifications_none_rounded;
  static const bellActive = Icons.notifications_rounded;
  static const person = Icons.person_outline_rounded;
  static const personActive = Icons.person_rounded;
  static const write = Icons.edit_outlined;
  static const settings = Icons.settings_outlined;
  static const more = Icons.more_horiz_rounded;
  static const close = Icons.close_rounded;
  static const back = Icons.arrow_back_rounded;
  static const camera = Icons.photo_camera_outlined;
  static const keyboard = Icons.keyboard_outlined;
  static const check = Icons.check_rounded;
  static const up = Icons.arrow_upward_rounded;
}

ThemeData buildTheme([SgPalette p = SgPalette.light]) {
  final dark = p.brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.surface,
    canvasColor: p.surface,
    fontFamily: SgFonts.sans,
    fontFamilyFallback: SgFonts.sansFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: p.brightness,
      primary: p.ink,
      onPrimary: p.surface,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerHighest: p.raised,
      surfaceContainerHigh: p.raised,
      surfaceContainer: p.raised,
      surfaceContainerLow: p.surface,
      outline: p.outline,
      outlineVariant: p.line,
      error: p.accentText,
    ),
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    // No ripples: rows and buttons show a soft highlight instead.
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.pressed,
    hoverColor: p.hover,
    focusColor: p.pressed,
    iconTheme: IconThemeData(color: p.ink),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.25),
      selectionHandleColor: p.accent,
    ),
    // iOS keeps its swipe-back; elsewhere pages fade and slide a little.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(size: 26, color: states.contains(WidgetState.selected) ? p.ink : p.muted),
      ),
    ),
    // Buttons resolve their own text style, so the font is set here too.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        textStyle: SgText.label(weight: FontWeight.w500),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.surface,
        shape: const StadiumBorder(),
        textStyle: SgText.label(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.outline),
        shape: const StadiumBorder(),
        textStyle: SgText.label(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.ink)),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: SgFonts.sans,
        fontFamilyFallback: SgFonts.sansFallback,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
    ),
    listTileTheme: ListTileThemeData(textColor: p.ink, iconColor: p.ink),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SgRadius.md),
        side: BorderSide(color: p.line),
      ),
      textStyle: TextStyle(fontFamily: SgFonts.sans, fontSize: 15, color: p.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SgRadius.lg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SgRadius.lg))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: SgFonts.sans, fontSize: 14, color: p.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SgRadius.sm)),
      width: null,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.outline),
      radius: const Radius.circular(SgRadius.pill),
      thickness: const WidgetStatePropertyAll(6),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A3734) : const Color(0xE6151515),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontFamily: SgFonts.sans, color: Colors.white, fontSize: 13),
    ),
  );
}
