import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/widgets/post_body.dart';

Future<void> show(WidgetTester tester, String text) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: PostBody(text, style: const TextStyle(fontSize: 16, height: 1.5))),
  ),
);

void main() {
  testWidgets('keeps a post without blank lines as one text', (tester) async {
    await show(tester, '첫 줄\n둘째 줄');
    expect(find.text('첫 줄\n둘째 줄'), findsOneWidget);
    expect(find.byType(SizedBox), findsNothing);
  });

  testWidgets('draws blank lines half a line high, and many as one', (tester) async {
    await show(tester, '첫 문단\n\n\n\n\n둘째 문단\n\n셋째');
    expect(find.text('첫 문단'), findsOneWidget);
    expect(find.text('둘째 문단'), findsOneWidget);
    expect(find.text('셋째'), findsOneWidget);
    final gaps = tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
    expect(gaps, hasLength(2));
    expect(gaps.first.height, 12);
  });
}
