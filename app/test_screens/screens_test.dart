// Renders each screen to PNG at phone size with the bundled fonts, for design
// review. Not part of `flutter test`; run with:
//   flutter test test_screens --update-goldens
import 'dart:io';

import 'package:flutter/services.dart';
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

import '../test/helpers.dart';

Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> shoot(WidgetTester tester, String name, Widget screen, {Future<void> Function()? then}) async {
  // Tests draw shadows as solid outlines unless told otherwise.
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: screen));
  await tester.pumpAndSettle();
  if (then != null) await then();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}

void main() {
  setUpAll(() async {
    await loadFont('Noto Sans KR', [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Medium.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]);
    await loadFont('IBM Plex Mono', ['assets/fonts/IBMPlexMono-Regular.ttf', 'assets/fonts/IBMPlexMono-Medium.ttf']);
    await loadFont('MaterialIcons', ['/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  final now = DateTime(2026, 11, 25, 21);

  testWidgets('start', (t) => shoot(t, 'start', StartScreen(onSignUp: () {}, onSignIn: () {})));

  testWidgets('feed', (t) async {
    final state = AppState(
      backend: DemoBackend(clock: () => now),
      clock: () => now,
    );
    await state.start();
    await shoot(t, 'feed', HomeShell(state: state));
  });

  testWidgets('compose', (t) async {
    var clock = now;
    final state = AppState(
      backend: DemoBackend(clock: () => now),
      clock: () => now,
    );
    await state.start();
    await shoot(
      t,
      'compose',
      ComposeScreen(state: state, clock: () => clock),
      then: () async {
        await t.showKeyboard(find.byKey(const Key('thought')));
        await typeLikeAPerson(t, '퇴근길에 하늘이 유난히 낮았다. 오늘 하루가 나를 조금 눌러놓은 것 같은데,', (d) => clock = clock.add(d));
        await t.pump();
      },
    );
  });

  testWidgets(
    'result',
    (t) => shoot(
      t,
      'result',
      const PublishResultScreen(
        body: '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다. 깨우지 않았다. 나도 그렇게 기대고 싶었던 날이 있었으니까.',
        outcome: Published(
          postId: 'x',
          typingTime: Duration(minutes: 3, seconds: 41),
          similarPeople: 12,
          showSimilar: true,
          firstPhrases: ['기대고 싶었던 날', '어깨에 기대 잠들었다'],
          writingDays: 8,
          followUnlocked: false,
        ),
      ),
    ),
  );

  testWidgets('profile', (t) async {
    final state = AppState(
      backend: DemoBackend(clock: () => now),
      clock: () => now,
    );
    await state.start();
    await shoot(
      t,
      'profile',
      Scaffold(
        body: SafeArea(child: ProfileScreen(state: state)),
      ),
    );
  });

  testWidgets('other-profile', (t) async {
    const me = Profile(id: 'me', handle: 'me', displayName: '나', writingDays: 12, followUnlocked: true, isMe: true);
    final state = AppState(
      backend: DemoBackend(clock: () => now, me: me),
      clock: () => now,
    );
    await state.start();
    await shoot(
      t,
      'other-profile',
      Scaffold(
        appBar: AppBar(),
        body: ProfileScreen(state: state, userId: 'u-haru'),
      ),
    );
  });
}
