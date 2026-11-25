import 'package:material_ui/material_ui.dart';

import 'api/cognito_auth.dart';
import 'api/config.dart';
import 'api/demo_backend.dart';
import 'api/http_backend.dart';
import 'data/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/start_screen.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await ApiConfig.load();
  if (config.isDemo) {
    runApp(SaenggakApp(state: AppState(backend: DemoBackend())));
    return;
  }
  final auth = CognitoAuth(config);
  runApp(
    SaenggakApp(
      state: AppState(
        backend: HttpBackend(baseUrl: config.apiUrl, auth: auth),
      ),
      auth: auth,
    ),
  );
}

/// Without [auth] the app runs on the demo backend and skips sign-in.
class SaenggakApp extends StatelessWidget {
  const SaenggakApp({super.key, required this.state, this.auth});

  final AppState state;
  final CognitoAuth? auth;

  /// After sign-in: create the profile if this is a new account, then home.
  Future<void> _enter(NavigatorState nav) async {
    await state.start();
    if (state.me == null) {
      await nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => ProfileSetupScreen(
            state: state,
            firstTime: true,
            onDone: () {
              state.refresh();
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
    final auth = this.auth;
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
    return MaterialApp(
      title: '생각',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => StartScreen(
          onSignUp: () => _openAuth(context, signUp: true),
          onSignIn: () => _openAuth(context, signUp: false),
        ),
        '/home': (_) => HomeShell(state: state),
      },
    );
  }
}
