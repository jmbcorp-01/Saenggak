// Flutter's accessibility guidelines on each screen. Run with:
//   flutter test test_screens/a11y_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/models/profile.dart';
import 'package:saenggak/models/publish_outcome.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/screens/home_shell.dart';
import 'package:saenggak/screens/profile_screen.dart';
import 'package:saenggak/screens/publish_result_screen.dart';
import 'package:saenggak/screens/start_screen.dart';
import 'package:saenggak/theme/tokens.dart';

Future<void> check(WidgetTester tester, String name, Widget screen) async {
  final handle = tester.ensureSemantics();
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: screen));
  await tester.pumpAndSettle();
  for (final (label, g) in [
    ('android tap target 48', androidTapTargetGuideline),
    ('ios tap target 44', iOSTapTargetGuideline),
    ('labeled tap target', labeledTapTargetGuideline),
    ('text contrast', textContrastGuideline),
  ]) {
    final result = await g.evaluate(tester);
    // ignore: avoid_print
    print('[$name] $label: ${result.passed ? 'pass' : 'FAIL\n${result.reason}'}');
  }
  handle.dispose();
}

void main() {
  final now = DateTime(2026, 11, 25, 21);
  testWidgets('start', (t) => check(t, 'start', StartScreen(onSignUp: () {}, onSignIn: () {})));
  testWidgets('feed', (t) async {
    final s = AppState(
      backend: DemoBackend(clock: () => now),
      clock: () => now,
    );
    await s.start();
    await check(t, 'feed', HomeShell(state: s));
  });
  testWidgets('compose', (t) async {
    final s = AppState(backend: DemoBackend());
    await s.start();
    await check(t, 'compose', ComposeScreen(state: s));
  });
  testWidgets(
    'result',
    (t) => check(
      t,
      'result',
      const PublishResultScreen(
        body: '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다.',
        outcome: Published(
          postId: 'x',
          typingTime: Duration(minutes: 3),
          similarPeople: 12,
          showSimilar: true,
          firstPhrases: ['어깨에 기대 잠들었다'],
          writingDays: 8,
          followUnlocked: false,
        ),
      ),
    ),
  );
  testWidgets('profile', (t) async {
    final s = AppState(backend: DemoBackend());
    await s.start();
    await check(t, 'profile', Scaffold(body: ProfileScreen(state: s)));
  });
  testWidgets('other-profile', (t) async {
    const me = Profile(id: 'me', handle: 'me', displayName: '나', followUnlocked: true, isMe: true);
    final s = AppState(backend: DemoBackend(me: me));
    await s.start();
    await check(
      t,
      'other',
      Scaffold(
        appBar: AppBar(),
        body: ProfileScreen(state: s, userId: 'u-haru'),
      ),
    );
  });
}
