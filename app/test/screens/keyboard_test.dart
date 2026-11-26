import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/widgets/keyboard.dart';

bool hasFocus(WidgetTester tester, Key key) => tester
    .widget<EditableText>(find.descendant(of: find.byKey(key), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

void main() {
  testWidgets('every screen of the app can close the keyboard with a tap', (tester) async {
    final state = AppState(backend: DemoBackend());
    await tester.pumpWidget(SaenggakApp(state: state));
    expect(find.byType(TapToHideKeyboard), findsOneWidget);
  });

  testWidgets('a tap outside a field closes the keyboard, a tap on the field keeps it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapToHideKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('field'), keyboardType: TextInputType.number),
              const SizedBox(key: Key('blank'), height: 300, width: 300),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(hasFocus(tester, const Key('field')), isTrue);

    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(hasFocus(tester, const Key('field')), isTrue);

    await tester.tap(find.byKey(const Key('blank')));
    await tester.pump();
    expect(hasFocus(tester, const Key('field')), isFalse);
  });

  testWidgets('writing has a button that lowers the keyboard while it is up', (tester) async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    Widget app({required double keyboard}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: ComposeScreen(state: state),
        ),
      ),
    );

    await tester.pumpWidget(app(keyboard: 0));
    expect(find.byKey(const Key('hide-keyboard')), findsNothing);

    await tester.pumpWidget(app(keyboard: 300));
    await tester.pump();
    expect(hasFocus(tester, const Key('thought')), isTrue);
    await tester.tap(find.byKey(const Key('hide-keyboard')));
    await tester.pump();
    expect(hasFocus(tester, const Key('thought')), isFalse);
  });

  testWidgets('the lower-keyboard button fits a small phone next to the length hint', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(backend: DemoBackend());
    await state.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: const EdgeInsets.only(bottom: 250)),
            child: ComposeScreen(state: state),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byKey(const Key('thought')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '짧', selection: TextSelection.collapsed(offset: 1)),
    );
    await tester.pump();
    expect(find.text('조금 더 써주세요'), findsOneWidget);
    expect(find.byKey(const Key('hide-keyboard')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
