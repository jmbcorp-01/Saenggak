import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/post.dart';
import 'package:saenggak/models/profile.dart';
import 'package:saenggak/screens/profile_screen.dart';

const me = Profile(id: 'me', handle: 'yoonseo', displayName: '윤서', writingDays: 12, followUnlocked: true, isMe: true);

Post fresh(String id, {String author = 'u-daniel'}) => Post(
  id: id,
  authorId: author,
  authorName: 'Daniel',
  authorHandle: 'daniel',
  body: '오늘 처음으로 아무 계획 없이 걸었다. 길을 잃어도 괜찮다는 걸 알았다.',
  lang: 'ko',
  createdAt: DateTime.now().add(const Duration(minutes: 1)),
  typingTime: const Duration(minutes: 1),
  empathyCount: 0,
);

Future<(DemoBackend, AppState)> followingDaniel() async {
  final backend = DemoBackend(me: me);
  final state = AppState(backend: backend);
  await state.start();
  await backend.follow('u-daniel');
  await state.refresh();
  return (backend, state);
}

void main() {
  test('new posts from followed people wait for the 팔로잉 tab', () async {
    final (backend, state) = await followingDaniel();
    expect(state.following, isNotEmpty);
    backend.arrive(fresh('n1'));
    await state.checkForNew();
    expect(state.incomingFollowing.map((p) => p.id), ['n1']);
    expect(state.hasIncoming, isTrue);
    expect(state.following.any((p) => p.id == 'n1'), isFalse);

    state.showIncomingFollowing();
    expect(state.following.first.id, 'n1');
    expect(state.incomingFollowing, isEmpty);
  });

  test('posts from people not followed do not reach the 팔로잉 tab', () async {
    final (backend, state) = await followingDaniel();
    backend.arrive(fresh('n2', author: 'u-haru'));
    await state.checkForNew();
    expect(state.incomingFollowing, isEmpty);
    expect(state.incoming.map((p) => p.id), ['n2']);
  });

  testWidgets('the 팔로잉 tab shows a dot, then the new-thoughts button there', (tester) async {
    final (backend, state) = await followingDaniel();
    await tester.pumpWidget(SaenggakApp(state: state));
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();

    backend.arrive(fresh('n3'));
    await state.checkForNew();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('following-dot')), findsOneWidget);

    await tester.tap(find.text('팔로잉'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('following-dot')), findsNothing);
    await tester.tap(find.byKey(const Key('new-posts')));
    await tester.pumpAndSettle();
    expect(state.following.first.id, 'n3');
  });

  testWidgets('the bell on a followed profile turns on alerts for new posts', (tester) async {
    final (backend, state) = await followingDaniel();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(state: state, userId: 'u-daniel'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('post-alerts')));
    await tester.pumpAndSettle();
    expect(find.text('@daniel.k 님이 새 생각을 남기면 알림으로 알려드릴게요.'), findsOneWidget);
    expect((await backend.user('u-daniel')).alertsOn, isTrue);

    backend.arrive(fresh('n4'));
    await state.loadNotifications();
    expect(state.notifications.first.kind, 'post');
    expect(state.notifications.first.postId, 'n4');
  });

  testWidgets('no bell for someone the reader does not follow', (tester) async {
    final state = AppState(backend: DemoBackend(me: me));
    await state.start();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(state: state, userId: 'u-haru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-alerts')), findsNothing);
  });
}
