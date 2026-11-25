import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/admin.dart';

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
}
