import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/core/typing_session.dart';

void main() {
  late DateTime now;
  late TypingSession session;

  setUp(() {
    now = DateTime(2026, 11, 22, 20);
    session = TypingSession(clock: () => now);
  });

  void typeAt(int ms, {int inserted = 1, InputSource source = InputSource.keyboard}) {
    now = DateTime(2026, 11, 22, 20).add(Duration(milliseconds: ms));
    session.record(inserted: inserted, deleted: 0, source: source);
  }

  test('active duration adds gaps between changes', () {
    typeAt(0);
    typeAt(200);
    typeAt(500);
    expect(session.activeDuration, const Duration(milliseconds: 500));
  });

  test('pauses over 30 seconds do not count as typing time', () {
    typeAt(0);
    typeAt(1000);
    typeAt(61000);
    typeAt(62000);
    expect(session.activeDuration, const Duration(seconds: 2));
  });

  test('empty changes are ignored', () {
    session.record(inserted: 0, deleted: 0);
    expect(session.events, isEmpty);
  });

  test('keyboard intervals skip voice input', () {
    typeAt(0);
    typeAt(100);
    typeAt(300, inserted: 12, source: InputSource.voice);
    typeAt(500);
    typeAt(650);
    expect(session.keyboardIntervals(), [100, 150]);
  });

  test('json keeps timings and counts, never the text', () {
    typeAt(0);
    session.recordRejectedPaste();
    final json = session.toJson();
    expect(json['rejectedPastes'], 1);
    expect((json['events'] as List).single, {'t': 0, 'i': 1, 'd': 0, 's': 'keyboard'});
  });

  test('formatTypingDuration', () {
    expect(formatTypingDuration(const Duration(seconds: 42)), '42초');
    expect(formatTypingDuration(const Duration(minutes: 2, seconds: 8)), '2분 08초');
  });
}
