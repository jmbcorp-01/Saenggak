import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/data/post_store.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/screens/compose_screen.dart';

void main() {
  testWidgets('start screen leads to the feed with typing times', (tester) async {
    await tester.pumpWidget(SaenggakApp(store: PostStore()));
    expect(find.text('계정 만들기'), findsOneWidget);
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('2분 18초'), findsOneWidget);
    expect(find.textContaining('영어에서 번역됨'), findsOneWidget);
  });

  testWidgets('tapping empathy updates the count', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(SaenggakApp(store: PostStore()));
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('공감 24'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empathy-p1')));
    await tester.pump();
    expect(find.text('25'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('compose blocks a pasted sentence', (tester) async {
    final store = PostStore();
    await tester.pumpWidget(MaterialApp(home: ComposeScreen(store: store)));
    final field = find.byKey(const Key('thought'));
    await tester.enterText(field, '붙여넣은 아주 긴 문장입니다');
    await tester.pump();
    expect(find.text('붙여넣은 아주 긴 문장입니다'), findsNothing);
    expect(find.text('붙여넣기는 할 수 없어요. 한 글자씩 직접 써주세요.'), findsOneWidget);
  });

  testWidgets('hand-typed post of enough length is published with its typing time',
      (tester) async {
    var now = DateTime(2026, 11, 22, 20);
    final store = PostStore([]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ComposeScreen(store: store, clock: () => now))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    const text = '비가 오면 약속을 미루고 싶어진다. 사실 비 때문이 아니라, 미룰 핑계가 필요했던 것 같다.';
    final field = find.byKey(const Key('thought'));
    var typed = '';
    var i = 0;
    for (final ch in text.characters) {
      typed += ch;
      now = now.add(Duration(milliseconds: 180 + (i * 97) % 260));
      i++;
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ));
      await tester.pump();
    }
    await tester.showKeyboard(field);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(store.mine, hasLength(1));
    expect(store.mine.single.body, text);
    expect(store.mine.single.typingTime.inSeconds, greaterThan(10));
  });
}
