import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Types [text] one character at a time with uneven, human-like gaps,
/// advancing [advance] by each gap so the typing session sees real timings.
Future<void> typeLikeAPerson(
  WidgetTester tester,
  String text,
  void Function(Duration) advance, {
  String start = '',
}) async {
  var typed = start;
  var i = 0;
  for (final ch in text.characters) {
    typed += ch;
    advance(Duration(milliseconds: 180 + (i * 97) % 260));
    i++;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    );
    await tester.pump();
  }
}
