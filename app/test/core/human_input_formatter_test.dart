import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/core/human_input_formatter.dart';
import 'package:saenggak/core/typing_session.dart';

TextEditingValue v(String s) => TextEditingValue(text: s);

void main() {
  late TypingSession session;
  late bool voice;
  late int rejected;
  late HumanInputFormatter f;

  setUp(() {
    session = TypingSession();
    voice = false;
    rejected = 0;
    f = HumanInputFormatter(session: session, isVoiceActive: () => voice, onRejected: () => rejected++);
  });

  test('accepts single typed characters and records them', () {
    expect(f.formatEditUpdate(v('생'), v('생각')).text, '생각');
    expect(session.events.single.inserted, 1);
  });

  test('accepts Korean composition that replaces the composing character', () {
    // ㅎ -> 하 -> 한 arrives as replacements of the last character.
    f.formatEditUpdate(v(''), v('ㅎ'));
    f.formatEditUpdate(v('ㅎ'), v('하'));
    expect(f.formatEditUpdate(v('하'), v('한')).text, '한');
    expect(session.events.length, 3);
    expect(session.events.last.deleted, 1);
  });

  test('rejects a pasted sentence and keeps the old text', () {
    final out = f.formatEditUpdate(v('나는 '), v('나는 붙여넣은 문장입니다'));
    expect(out.text, '나는 ');
    expect(rejected, 1);
    expect(session.rejectedPastes, 1);
    expect(session.events, isEmpty);
  });

  test('allows a long chunk while voice input is on, marked as voice', () {
    voice = true;
    final out = f.formatEditUpdate(v(''), v('음성으로 들어온 긴 문장'));
    expect(out.text, '음성으로 들어온 긴 문장');
    expect(session.events.single.source, InputSource.voice);
  });

  test('deleting a selection is always allowed', () {
    expect(f.formatEditUpdate(v('지울 문장입니다'), v('지울')).text, '지울');
    expect(session.events.single.deleted, 6);
  });

  test('diff finds a change in the middle of the text', () {
    final d = HumanInputFormatter.diff('abcdef', 'abXYdef');
    expect(d.inserted, 2);
    expect(d.deleted, 1);
  });
}
