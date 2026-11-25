import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/admin.dart';
import 'package:saenggak/models/social.dart';

Future<AppState> openSettings(WidgetTester tester, {DemoBackend? backend}) async {
  // Tall enough that the whole settings list is built.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(backend: backend ?? DemoBackend(), deviceTimeZone: () async => 'Europe/Paris');
  await tester.pumpWidget(SaenggakApp(state: state));
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('프로필').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('설정'));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('settings change the feed language and time zone', (tester) async {
    final state = await openSettings(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(state.me!.locale, 'en');

    await tester.tap(find.text('시간대'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/Paris (이 기기)'));
    await tester.pumpAndSettle();
    expect(state.me!.timeZone, 'Europe/Paris');
  });

  testWidgets('sign-out returns to the start screen with nothing left behind', (tester) async {
    final state = await openSettings(tester);
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('로그인'), findsOneWidget);
    expect(state.me, isNull);
    expect(state.feed, isEmpty);
  });

  testWidgets('account deletion asks first, then signs out', (tester) async {
    final state = await openSettings(tester);
    await tester.ensureVisible(find.text('계정 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계정 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('계정을 삭제할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(state.me, isNotNull);

    await tester.tap(find.text('계정 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(state.me, isNull);
    expect(find.text('계정을 삭제했어요.'), findsOneWidget);
  });

  testWidgets('admins review held posts and suspend people', (tester) async {
    final backend = DemoBackend()
      ..hold(
        ReviewItem(
          id: 'held-1',
          authorHandle: 'minjun',
          authorName: '민준',
          body: '판단을 보류한 글',
          blockedReason: 'classifier_declined',
          createdAt: DateTime.now(),
        ),
      );
    await openSettings(tester, backend: backend);
    await tester.ensureVisible(find.text('관리자 페이지'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('관리자 페이지'));
    await tester.pumpAndSettle();

    expect(find.text('판단을 보류한 글'), findsOneWidget);
    expect(find.text('필터가 판단 보류'), findsOneWidget);
    await tester.tap(find.text('피드에 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('검토할 글이 없어요.'), findsOneWidget);

    await tester.tap(find.text('사람'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('관리').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('정지'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '반복 광고');
    await tester.tap(find.widgetWithText(TextButton, '정지'));
    await tester.pumpAndSettle();
    expect(find.textContaining('정지됨'), findsOneWidget);

    await tester.tap(find.text('통계'));
    await tester.pumpAndSettle();
    expect(find.text('정지된 사람'), findsOneWidget);
  });

  testWidgets('a post can be reported, its author blocked, and the report handled by an admin', (tester) async {
    final backend = DemoBackend();
    final state = await openSettings(tester, backend: backend);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈').last);
    await tester.pumpAndSettle();

    final author = state.feed.firstWhere((p) => !p.isMine);
    await tester.tap(find.byKey(ValueKey('menu-${author.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(reportReasons['spam']!));
    await tester.pumpAndSettle();
    expect(find.text('신고했어요'), findsOneWidget);
    await tester.tap(find.text('차단하기'));
    await tester.pumpAndSettle();
    expect(state.feed.any((p) => p.authorId == author.authorId), isFalse);
    expect((await backend.blockedUsers()).single.id, author.authorId);

    final reports = await backend.openReports();
    expect(reports.single.reason, 'spam');
    expect(reports.single.postId, author.id);
  });

  testWidgets('the notifications tab shows 공감 and follows and clears the badge', (tester) async {
    final backend = DemoBackend()
      ..notificationItems.add(
        AppNotification(
          kind: 'empathy',
          at: DateTime.now(),
          actorId: 'u-9',
          actorHandle: 'haneul',
          actorName: '하늘',
          excerpt: '비가 오면',
        ),
      );
    final state = AppState(backend: backend);
    await tester.pumpWidget(SaenggakApp(state: state));
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(state.unreadNotifications, 1);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('알림').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('님이 내 생각에 공감했어요.'), findsOneWidget);
    expect(state.unreadNotifications, 0);
  });

  testWidgets('admins see open reports and can dismiss one', (tester) async {
    final backend = DemoBackend();
    final state = AppState(backend: backend);
    await state.start();
    final post = state.feed.firstWhere((p) => !p.isMine);
    await backend.report(postId: post.id, reason: 'abuse');
    await openSettings(tester, backend: backend);
    await tester.tap(find.text('관리자 페이지'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고').first);
    await tester.pumpAndSettle();
    expect(find.text(reportReasons['abuse']!), findsOneWidget);
    await tester.tap(find.text('문제 없음'));
    await tester.pumpAndSettle();
    expect(find.text('처리할 신고가 없어요.'), findsOneWidget);
  });
}
