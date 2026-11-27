import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/models/post.dart';
import 'package:saenggak/screens/admin_growth.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/screens/profile_setup_screen.dart';
import 'package:saenggak/screens/settings_screen.dart';
import 'package:saenggak/widgets/post_actions.dart';
import 'package:saenggak/widgets/share_card.dart';

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('sharing is off until the writer turns it on, and can leave the name out', (tester) async {
    tall(tester);
    final backend = DemoBackend();
    final state = AppState(backend: backend);
    await state.start();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(state: state)));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byKey(const Key('share-ok'))).value, isFalse);
    expect(find.byKey(const Key('share-anonymous')), findsNothing);

    await tester.tap(find.byKey(const Key('share-ok')));
    await tester.pumpAndSettle();
    expect((await backend.sharing()).shareOk, isTrue);

    await tester.tap(find.byKey(const Key('share-anonymous')));
    await tester.pumpAndSettle();
    final saved = await backend.sharing();
    expect(saved.shareOk, isTrue);
    expect(saved.anonymous, isTrue);
  });

  testWidgets('a new profile takes an invite code, and says so when the code does not exist', (tester) async {
    final backend = DemoBackend();
    final state = AppState(backend: backend, deviceTimeZone: () async => 'Asia/Seoul');
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSetupScreen(state: state, firstTime: true, onDone: () => done = true),
      ),
    );
    await tester.enterText(find.byKey(const Key('name')), '새사람');
    await tester.enterText(find.byKey(const Key('handle')), 'newbie');
    await tester.enterText(find.byKey(const Key('invite-code')), 'NOPE123');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('없는 초대 코드예요. 다시 확인하거나 비워 두세요.'), findsOneWidget);
    expect(done, isFalse);

    await tester.enterText(find.byKey(const Key('invite-code')), 'SAENG2K7');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(backend.recordedSource, 'SAENG2K7');
  });

  testWidgets('a code from the link is filled in for a new profile', (tester) async {
    final state = AppState(backend: DemoBackend())..pendingCode = 'disquiet';
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSetupScreen(state: state, firstTime: true, onDone: () {}),
      ),
    );
    expect(find.text('disquiet'), findsOneWidget);
  });

  testWidgets("the editor shows today's question in place of the usual prompt", (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    await tester.pumpWidget(MaterialApp(home: ComposeScreen(state: state)));
    await tester.pump();
    await tester.pump();
    expect(find.text('오늘 가장 오래 생각한 사람은 누구인가요?'), findsOneWidget);
  });

  testWidgets('without a question the editor keeps the usual prompt', (tester) async {
    final state = AppState(backend: DemoBackend()..question = null);
    await state.start();
    await tester.pumpWidget(MaterialApp(home: ComposeScreen(state: state)));
    await tester.pump();
    await tester.pump();
    expect(find.text('지금 어떤 생각을 하고 있나요?'), findsOneWidget);
  });

  testWidgets('own posts offer a share card, and to stay out of sharing once it is on', (tester) async {
    tall(tester);
    final post = Post(
      id: 'mine-1',
      authorId: DemoBackend().myId,
      authorName: '나',
      authorHandle: 'me',
      body: '내가 쓴 생각',
      lang: 'ko',
      createdAt: DateTime(2026, 11, 27),
      typingTime: const Duration(minutes: 2),
      empathyCount: 0,
      isMine: true,
    );
    final backend = DemoBackend(posts: [post]);
    final state = AppState(backend: backend);
    await state.start();
    Widget tile() => MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (_, _) => ConnectedPostTile(state: state, post: post),
        ),
      ),
    );

    await tester.pumpWidget(tile());
    await tester.tap(find.byKey(const ValueKey('menu-mine-1')));
    await tester.pumpAndSettle();
    expect(find.text('공유 카드 만들기'), findsOneWidget);
    expect(find.text('생각 공식 계정 소개에서 빼기'), findsNothing);
    await tester.tap(find.text('공유 카드 만들기'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareCard), findsOneWidget);
    expect(find.text('나님의 생각 · 직접 타이핑 2분'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-card-name')));
    await tester.pumpAndSettle();
    expect(find.text('어느 생각러의 생각 · 직접 타이핑 2분'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ShareCard))).pop();
    await tester.pumpAndSettle();

    await state.setSharing(shareOk: true, anonymous: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-mine-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('생각 공식 계정 소개에서 빼기'));
    await tester.pumpAndSettle();
    expect(backend.excludedPosts, contains('mine-1'));
  });

  testWidgets('an admin approves a picked post with its card image', (tester) async {
    tall(tester);
    final backend = DemoBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminPromoTab(backend: backend)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShareCard), findsWidgets);

    await tester.tap(find.byKey(const Key('promo-approve')).first);
    // The card is drawn into a PNG off the test clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(backend.lastCard, isNotNull);
    expect(backend.lastCard!.sublist(1, 4), 'PNG'.codeUnits);
    expect(find.text('승인했어요. 저녁 9시에 올라가요.'), findsOneWidget);
  });

  testWidgets('the other admin tabs load', (tester) async {
    tall(tester);
    final backend = DemoBackend();
    for (final tab in [
      AdminDashboardTab(backend: backend),
      AdminQuestionsTab(backend: backend),
      AdminLinksTab(backend: backend),
      AdminAuditTab(backend: backend),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: tab)));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('기록이 없어요.'), findsOneWidget);
  });
}
