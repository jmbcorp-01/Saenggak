import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/links.dart';
import 'package:saenggak/core/typing_session.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/publish_outcome.dart';
import 'package:saenggak/screens/post_screen.dart';
import 'package:saenggak/screens/saved_screen.dart';

import '../helpers.dart';

Future<void> openHome(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(SaenggakApp(state: state));
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a typing check appears when asked for, and the 공감 goes through after it', (tester) async {
    final backend = DemoBackend()..wantsHumanCheck = true;
    await openHome(tester, AppState(backend: backend));

    await tester.tap(find.byKey(const ValueKey('empathy-p1')));
    await tester.pumpAndSettle();
    expect(find.text('사람인지 확인할게요'), findsOneWidget);
    expect(find.text(DemoBackend.demoCheckPhrase), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-input')));
    await typeLikeAPerson(tester, DemoBackend.demoCheckPhrase, (_) {});
    await tester.tap(find.byKey(const Key('check-submit')));
    await tester.pumpAndSettle();

    expect(find.text('사람인지 확인할게요'), findsNothing);
    expect(backend.wantsHumanCheck, isFalse);
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('closing the typing check leaves the 공감 as it was', (tester) async {
    final backend = DemoBackend()..wantsHumanCheck = true;
    await openHome(tester, AppState(backend: backend));
    await tester.tap(find.byKey(const ValueKey('empathy-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기').last);
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
  });

  test('a post held for a typing check is sent again once it passes', () async {
    final backend = DemoBackend()..wantsHumanCheck = true;
    final state = AppState(backend: backend);
    await state.start();
    var asked = 0;
    state.askHumanCheck = () async {
      asked++;
      backend.wantsHumanCheck = false;
      return true;
    };
    final session = TypingSession()..record(inserted: 1, deleted: 0);
    final outcome = await state.publish('비가 오면 약속을 미루고 싶어진다. 사실 비 때문이 아니라 핑계가 필요했다.', session);
    expect(asked, 1);
    expect(outcome, isA<Published>());
  });

  test('without a passed check the post stays refused', () async {
    final state = AppState(backend: DemoBackend()..wantsHumanCheck = true);
    await state.start();
    state.askHumanCheck = () async => false;
    final outcome = await state.publish('글', TypingSession()..record(inserted: 1, deleted: 0));
    expect((outcome as Rejected).reason, RejectReason.humanCheck);
  });

  testWidgets('search finds people and similar thoughts', (tester) async {
    await openHome(tester, AppState(backend: DemoBackend()));
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-input')), '시간');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('비슷한 생각'), findsOneWidget);
  });

  test('saving a post puts it on the saved list, and unsaving takes it off', () async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    final post = state.feed.first;
    await state.toggleBookmark(post);
    expect(state.feed.first.bookmarked, isTrue);
    await state.loadSaved();
    expect(state.saved.map((p) => p.id), [post.id]);
    await state.toggleBookmark(state.feed.first);
    await state.loadSaved();
    expect(state.saved, isEmpty);
  });

  testWidgets('the saved page lists saved posts', (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    await state.toggleBookmark(state.feed.first);
    await tester.pumpWidget(MaterialApp(home: SavedScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('empathy-${state.feed.first.id}')), findsOneWidget);
  });

  testWidgets('a shared post opens on its own page, or says it is gone', (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    await tester.pumpWidget(
      MaterialApp(
        home: PostScreen(state: state, postId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('empathy-p1')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: PostScreen(key: const ValueKey('gone'), state: state, postId: 'gone'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('글을 찾을 수 없어요. 이미 삭제됐을 수 있어요.'), findsOneWidget);
  });

  test('post links carry the id, and only real ids are opened', () {
    expect(postLink('abc').queryParameters['post'], 'abc');
    const id = '0f8fad5b-d9cb-469f-a165-70867728950e';
    expect(linkedPostId(Uri.parse('https://saenggak.app/?post=$id')), id);
    expect(linkedPostId(Uri.parse('https://saenggak.app/?post=<script>')), isNull);
    expect(linkedPostId(Uri.parse('https://saenggak.app/')), isNull);
  });
}
