import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/backend.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/typing_session.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/profile.dart';
import 'package:saenggak/models/publish_outcome.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/screens/photo_capture_screen.dart';
import 'package:saenggak/screens/publish_result_screen.dart';

import '../helpers.dart';

const text = '비가 오면 약속을 미루고 싶어진다. 사실 비 때문이 아니라, 미룰 핑계가 필요했던 것 같다.';

/// A backend whose content filter blocks everything.
class BlockingBackend extends DemoBackend {
  @override
  Future<PublishOutcome> publish({
    required String text,
    required TypingSession session,
    required String localDate,
  }) async => const Rejected(RejectReason.blocked, blockedFor: 'spam');
}

Future<void> openHome(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(SaenggakApp(state: state));
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();
}

/// Opens the compose screen over a blank page and returns the clock control.
Future<void Function(Duration)> openCompose(WidgetTester tester, AppState state, {Widget? screen}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen!)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (_) {};
}

void main() {
  testWidgets('start screen leads to the feed with typing times and translations', (tester) async {
    await openHome(tester, AppState(backend: DemoBackend()));
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('2분 18초'), findsOneWidget);
    expect(find.textContaining('영어에서 번역됨'), findsOneWidget);

    await tester.tap(find.text('원문 보기'));
    await tester.pump();
    expect(find.textContaining("We don't move because we are sure"), findsOneWidget);
  });

  testWidgets('tapping empathy updates the count', (tester) async {
    final semantics = tester.ensureSemantics();
    await openHome(tester, AppState(backend: DemoBackend()));
    expect(find.bySemanticsLabel('공감 24'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empathy-p1')));
    await tester.pumpAndSettle();
    expect(find.text('25'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('compose blocks a pasted sentence', (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    await tester.pumpWidget(MaterialApp(home: ComposeScreen(state: state)));
    await tester.enterText(find.byKey(const Key('thought')), '붙여넣은 아주 긴 문장입니다');
    await tester.pump();
    expect(find.text('붙여넣은 아주 긴 문장입니다'), findsNothing);
    expect(find.text('붙여넣기는 할 수 없어요. 한 글자씩 직접 써주세요.'), findsOneWidget);
  });

  testWidgets('a hand-typed post opens the result with similar people and first phrases', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 11, 22, 20);
    final state = AppState(
      backend: DemoBackend(clock: () => now),
      clock: () => now,
    );
    await state.start();
    await openCompose(
      tester,
      state,
      screen: ComposeScreen(state: state, clock: () => now),
    );
    await tester.showKeyboard(find.byKey(const Key('thought')));
    await typeLikeAPerson(tester, text, (d) => now = now.add(d));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('올렸어요'), findsOneWidget);
    expect(find.text('비슷한 생각을 한 사람이 있어요'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('similar-card')), matching: find.text('4 명', findRichText: true)),
      findsOneWidget,
    );
    expect(find.text('처음 쓴 표현'), findsOneWidget);
    expect(find.text('“비가 오면 약속을”'), findsOneWidget);
    expect(find.text('8 / 10'), findsOneWidget);

    expect(state.mine, hasLength(1));
    expect(state.mine.single.body, text);
    expect(state.mine.single.typingTime.inSeconds, greaterThan(10));
    expect(state.me!.writingDays, 8);
    semantics.dispose();
  });

  testWidgets('a blocked post keeps the draft and says why', (tester) async {
    var now = DateTime(2026, 11, 22, 20);
    final state = AppState(backend: BlockingBackend(), clock: () => now);
    await state.start();
    await openCompose(
      tester,
      state,
      screen: ComposeScreen(state: state, clock: () => now),
    );
    await tester.showKeyboard(find.byKey(const Key('thought')));
    await typeLikeAPerson(tester, text, (d) => now = now.add(d));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('광고나 홍보로 보여 올리지 않았어요.'), findsOneWidget);
    expect(find.text(text), findsOneWidget);
    expect(find.byType(PublishResultScreen), findsNothing);
  });

  testWidgets('own posts can be edited before any 공감, then deleted', (tester) async {
    var now = DateTime(2026, 11, 22, 20);
    final backend = DemoBackend(clock: () => now);
    final state = AppState(backend: backend, clock: () => now);
    await state.start();
    final session = TypingSession(clock: () => now);
    await state.publish(text, session..record(inserted: text.length, deleted: 0));

    await tester.pumpWidget(SaenggakApp(state: state));
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    final id = state.mine.single.id;

    await tester.tap(find.byKey(ValueKey('menu-$id')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(find.text('수정하기'), findsOneWidget);
    // On a wide screen the editor opens over the timeline, which shows the post too.
    expect(find.descendant(of: find.byType(ComposeScreen), matching: find.text(text)), findsOneWidget);

    await tester.showKeyboard(find.byKey(const Key('thought')));
    await typeLikeAPerson(tester, ' 오늘도 그랬다.', (d) => now = now.add(d), start: text);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('고쳐서 올렸어요'), findsOneWidget);
    expect(state.mine.single.body, '$text 오늘도 그랬다.');
    expect(state.mine.single.editedAt, isNotNull);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('menu-$id')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(state.mine, isEmpty);
  });

  testWidgets('follow is disabled until writing days unlock it', (tester) async {
    final state = AppState(backend: DemoBackend());
    await openHome(tester, state);
    await tester.tap(find.textContaining('@haru', findRichText: true).first);
    await tester.pumpAndSettle();
    final follow = find.byKey(const Key('follow'));
    expect(tester.widget<OutlinedButton>(follow).onPressed, isNull);
  });

  testWidgets('follow works when both people have permission', (tester) async {
    const unlocked = Profile(
      id: 'me',
      handle: 'me',
      displayName: '나',
      writingDays: 12,
      followUnlocked: true,
      isMe: true,
    );
    final state = AppState(backend: DemoBackend(me: unlocked));
    await openHome(tester, state);
    await tester.tap(find.textContaining('@haru', findRichText: true).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('follow')));
    await tester.pumpAndSettle();
    expect(find.text('팔로잉'), findsWidgets);
    expect(state.following.map((p) => p.authorName), contains('하루'));
  });

  testWidgets('result screen hides counts under three people', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PublishResultScreen(
          body: '그냥 오늘의 생각.',
          outcome: Published(
            postId: 'x',
            typingTime: Duration(seconds: 40),
            similarPeople: 2,
            showSimilar: false,
            firstPhrases: [],
            writingDays: 10,
            followUnlocked: true,
          ),
        ),
      ),
    );
    expect(find.text('아직 비슷한 생각이 없어요'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('처음 쓴 표현'), findsNothing);
  });

  test('first phrases are underlined where they appear', () {
    final spans = highlightPhrases('The quiet morning is mine.', ['quiet morning', 'not here']);
    final marked = spans.whereType<TextSpan>().where((s) => s.style?.decoration == TextDecoration.underline);
    expect(marked.map((s) => s.text), ['quiet morning']);
  });

  test('local date is the writer\'s calendar day', () {
    expect(localDateOf(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });

  testWidgets('the photo screen only offers the camera, and says so when there is none', (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoCaptureScreen(state: state, cameras: () async => []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('카메라를 찾지 못했어요'), findsOneWidget);
    expect(find.textContaining('앨범'), findsOneWidget); // only in the explanation
    expect(find.text('이 사진 쓰기'), findsNothing);
  });

  testWidgets('my profile has a camera button for the photo', (tester) async {
    final state = AppState(backend: DemoBackend());
    await openHome(tester, state);
    await tester.tap(find.byTooltip('프로필').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('프로필 사진 찍기'), findsOneWidget);
  });
}
