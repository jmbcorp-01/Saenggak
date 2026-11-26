import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api/cognito_auth.dart';
import 'api/config.dart';
import 'api/demo_backend.dart';
import 'api/http_backend.dart';
import 'api/token_store.dart';
import 'core/appearance.dart';
import 'data/app_state.dart';
import 'l10n/l10n.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/start_screen.dart';
import 'theme/tokens.dart';
import 'widgets/keyboard.dart';
import 'widgets/symbol_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Appearance.instance.load();
  await AppLang.instance.load();
  final config = await ApiConfig.load();
  if (config.isDemo) {
    runApp(SaenggakApp(state: AppState(backend: DemoBackend())));
    return;
  }
  final auth = CognitoAuth(config, store: const SecureTokenStore());
  // Someone who signed in before goes straight to their feed.
  final resumed = await auth.restore();
  runApp(
    SaenggakApp(
      state: AppState(
        backend: HttpBackend(baseUrl: config.apiUrl, auth: auth),
      ),
      auth: auth,
      resumed: resumed,
    ),
  );
}

/// Without [auth] the app runs on the demo backend and skips sign-in.
class SaenggakApp extends StatefulWidget {
  const SaenggakApp({super.key, required this.state, this.auth, this.resumed = false});

  final AppState state;
  final CognitoAuth? auth;

  /// A saved session was restored, so the start screen is skipped.
  final bool resumed;

  @override
  State<SaenggakApp> createState() => _SaenggakAppState();
}

class _SaenggakAppState extends State<SaenggakApp> with WidgetsBindingObserver {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Appearance.instance.addListener(_applyPalette);
    AppLang.instance.addListener(_rebuildAll);
    SgColors.use(_palette());
  }

  @override
  void dispose() {
    Appearance.instance.removeListener(_applyPalette);
    AppLang.instance.removeListener(_rebuildAll);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyPalette();

  @override
  void didChangeLocales(List<Locale>? locales) => AppLang.instance.deviceChanged();

  SgPalette _palette() {
    final dark = switch (Appearance.instance.value) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
    };
    return dark ? SgPalette.dark : SgPalette.light;
  }

  /// Colors are read from [SgColors] during build, so every widget is
  /// rebuilt (keeping its state) when the palette changes.
  void _applyPalette() {
    final next = _palette();
    if (next == SgColors.palette) return;
    SgColors.use(next);
    _rebuildAll();
  }

  /// Text is looked up with [t] during build, like colors, so a new language
  /// rebuilds every widget in place.
  void _rebuildAll() {
    setState(() {});
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }

  /// After sign-in: create the profile if this is a new account, then home.
  Future<void> _enter(NavigatorState nav) async {
    // Home opens as soon as the profile is known; the timeline fills in there.
    await state.loadMe();
    if (state.me != null) unawaited(state.loadLists());
    if (state.me == null) {
      await nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => ProfileSetupScreen(
            state: state,
            firstTime: true,
            onDone: () {
              state.loadLists();
              nav.pushNamedAndRemoveUntil('/home', (_) => false);
            },
          ),
        ),
        (_) => false,
      );
      return;
    }
    await nav.pushNamedAndRemoveUntil('/home', (_) => false);
  }

  void _openAuth(BuildContext context, {required bool signUp}) {
    final nav = Navigator.of(context);
    final auth = widget.auth;
    if (auth == null) {
      _enter(nav);
      return;
    }
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(auth: auth, signUp: signUp, onSignedIn: () => _enter(nav)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SgColors.palette;
    return MaterialApp(
      title: t('생각'),
      locale: Locale(AppLang.instance.value),
      supportedLocales: [for (final l in supportedLangs) Locale(l)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette),
      // Widgets take their colors straight from the palette, so the theme
      // switches at once rather than fading under them.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SgColors.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: TapToHideKeyboard(child: child!),
      ),
      initialRoute: widget.resumed ? '/resume' : '/',
      routes: {
        '/': (context) => StartScreen(
          onSignUp: () => _openAuth(context, signUp: true),
          onSignIn: () => _openAuth(context, signUp: false),
        ),
        '/home': (_) => HomeShell(state: state),
        '/resume': (context) => _Resume(
          enter: () => _enter(Navigator.of(context)),
          onFailed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
        ),
      },
    );
  }
}

/// Loads a restored session's profile, then opens home (or profile setup).
class _Resume extends StatefulWidget {
  const _Resume({required this.enter, required this.onFailed});

  final Future<void> Function() enter;
  final VoidCallback onFailed;

  @override
  State<_Resume> createState() => _ResumeState();
}

class _ResumeState extends State<_Resume> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.enter();
      } catch (_) {
        if (mounted) widget.onFailed();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: SymbolMark(size: 48)));
}
