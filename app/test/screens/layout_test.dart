import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/backend.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/appearance.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/post.dart';
import 'package:saenggak/theme/tokens.dart';
import 'package:saenggak/widgets/right_panel.dart';
import 'package:saenggak/widgets/side_nav.dart';
import 'package:saenggak/widgets/skeleton.dart';

/// A demo server where someone else posts after the feed first loads.
class LaterPostBackend extends DemoBackend {
  bool posted = false;

  @override
  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before}) async {
    final page = await super.feed(lang: lang, following: following, authorId: authorId, before: before);
    if (!posted || authorId != null || following) return page;
    final newer = Post(
      id: 'later',
      authorId: 'u-later',
      authorName: '새벽',
      authorHandle: 'dawn',
      body: '방금 떠오른 생각을 손으로 적어 본다. 금방 사라질 것 같아서.',
      lang: 'ko',
      createdAt: DateTime.now().add(const Duration(minutes: 1)),
      typingTime: const Duration(seconds: 40),
      empathyCount: 0,
    );
    return FeedPage([newer, ...page.items], page.next);
  }
}

/// A demo server that takes a while to send the feed.
class SlowBackend extends DemoBackend {
  @override
  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before}) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return super.feed(lang: lang, following: following, authorId: authorId, before: before);
  }
}

Future<AppState> openAt(WidgetTester tester, Size size, {DemoBackend? backend}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(backend: backend ?? DemoBackend());
  await tester.pumpWidget(SaenggakApp(state: state));
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('a phone has the bottom menu and no side panels', (tester) async {
    await openAt(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(SideNav), findsNothing);
    expect(find.byType(RightPanel), findsNothing);
  });

  testWidgets('a tablet has the icon menu on the left', (tester) async {
    await openAt(tester, const Size(820, 1000));
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<SideNav>(find.byType(SideNav)).expanded, isFalse);
    expect(find.byType(RightPanel), findsNothing);
  });

  testWidgets('a computer has the named menu, the column and the right panel', (tester) async {
    await openAt(tester, const Size(1440, 900));
    expect(tester.widget<SideNav>(find.byType(SideNav)).expanded, isTrue);
    expect(find.byType(RightPanel), findsOneWidget);
    expect(find.text('많이 공감받은 생각'), findsOneWidget);
  });

  testWidgets('a profile opens inside the column and keeps the menu', (tester) async {
    await openAt(tester, const Size(1440, 900));
    await tester.tap(find.textContaining('@haru', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(find.byType(SideNav), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    // Home again goes back to the timeline.
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('newer posts wait behind a pill until tapped', (tester) async {
    final backend = LaterPostBackend();
    final state = await openAt(tester, const Size(390, 844), backend: backend);
    expect(find.text('새 생각 1개'), findsNothing);

    backend.posted = true;
    await state.checkForNew();
    await tester.pumpAndSettle();
    expect(find.text('새 생각 1개'), findsOneWidget);
    expect(state.feed.any((p) => p.id == 'later'), isFalse);

    await tester.tap(find.byKey(const Key('new-posts')));
    await tester.pumpAndSettle();
    expect(state.feed.first.id, 'later');
    expect(find.textContaining('방금 떠오른 생각'), findsOneWidget);
  });

  testWidgets('the first load shows placeholder rows', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(backend: SlowBackend());
    await tester.pumpWidget(SaenggakApp(state: state));
    await tester.tap(find.text('로그인'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PostSkeletonList), findsOneWidget);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byType(PostSkeletonList), findsNothing);
  });

  testWidgets('the screen mode setting switches to dark and back', (tester) async {
    addTearDown(() => Appearance.instance.value = ThemeMode.system);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SaenggakApp(state: AppState(backend: DemoBackend())));
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('프로필').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('어둡게'));
    await tester.pumpAndSettle();
    expect(SgColors.isDark, isTrue);
    expect(Theme.of(tester.element(find.text('화면 모드'))).brightness, Brightness.dark);

    await tester.tap(find.text('밝게'));
    await tester.pumpAndSettle();
    expect(SgColors.isDark, isFalse);
  });
}
