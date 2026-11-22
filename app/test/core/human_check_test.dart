import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/core/human_check.dart';
import 'package:saenggak/core/typing_session.dart';

TypingSession sessionWithGaps(List<int> gaps, {int perEvent = 1}) {
  var t = DateTime(2026, 11, 22);
  final s = TypingSession(clock: () => t);
  s.record(inserted: perEvent, deleted: 0);
  for (final g in gaps) {
    t = t.add(Duration(milliseconds: g));
    s.record(inserted: perEvent, deleted: 0);
  }
  return s;
}

void main() {
  test('passes human-like typing with uneven gaps', () {
    final rnd = Random(7);
    final gaps = List.generate(80, (_) => 120 + rnd.nextInt(380));
    expect(HumanCheck.evaluate(sessionWithGaps(gaps)).passed, isTrue);
  });

  test('flags perfectly even gaps as too regular', () {
    final result = HumanCheck.evaluate(sessionWithGaps(List.filled(80, 150)));
    expect(result.issues, contains(HumanCheckIssue.tooRegular));
  });

  test('flags typing faster than a person can', () {
    final rnd = Random(3);
    final gaps = List.generate(80, (_) => 20 + rnd.nextInt(30));
    expect(HumanCheck.evaluate(sessionWithGaps(gaps)).issues,
        contains(HumanCheckIssue.tooFast));
  });

  test('flags text that arrived in few large chunks', () {
    final rnd = Random(5);
    final gaps = List.generate(10, (_) => 400 + rnd.nextInt(600));
    expect(HumanCheck.evaluate(sessionWithGaps(gaps, perEvent: 4)).issues,
        contains(HumanCheckIssue.tooFewEvents));
  });

  test('voice input is left out of the keyboard checks', () {
    var t = DateTime(2026, 11, 22);
    final s = TypingSession(clock: () => t);
    s.record(inserted: 60, deleted: 0, source: InputSource.voice);
    t = t.add(const Duration(milliseconds: 10));
    s.record(inserted: 60, deleted: 0, source: InputSource.voice);
    expect(HumanCheck.evaluate(s).passed, isTrue);
  });
}
