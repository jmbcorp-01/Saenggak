import 'package:material_ui/material_ui.dart';

import 'data/post_store.dart';
import 'screens/home_shell.dart';
import 'screens/start_screen.dart';
import 'theme/tokens.dart';

void main() {
  runApp(SaenggakApp(store: PostStore()));
}

class SaenggakApp extends StatelessWidget {
  const SaenggakApp({super.key, required this.store});

  final PostStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '생각',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const StartScreen(),
        '/home': (_) => HomeShell(store: store),
      },
    );
  }
}
