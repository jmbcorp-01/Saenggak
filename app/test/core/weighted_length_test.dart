import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/core/weighted_length.dart';

void main() {
  group('WeightedLength.of', () {
    test('counts Hangul as 2 and Latin, digits and spaces as 1', () {
      expect(WeightedLength.of('생각'), 4);
      expect(WeightedLength.of('think'), 5);
      expect(WeightedLength.of('a 1'), 3);
      expect(WeightedLength.of('나는 I'), 6);
    });

    test('counts kana and Han characters as 2', () {
      expect(WeightedLength.of('ひらがな'), 8);
      expect(WeightedLength.of('カタカナ'), 8);
      expect(WeightedLength.of('思考'), 4);
    });

    test('counts characters outside the BMP once each', () {
      expect(WeightedLength.of('😀'), 1);
      expect(WeightedLength.of('𠀀'), 2);
    });
  });

  group('LengthStatus', () {
    test('40 Korean characters is exactly the minimum', () {
      final s = WeightedLength.status('가' * 40);
      expect(s.units, 80);
      expect(s.tooShort, isFalse);
      expect(s.postable, isTrue);
    });

    test('39 Korean characters is too short', () {
      expect(WeightedLength.status('가' * 39).tooShort, isTrue);
    });

    test('200 Korean characters is the maximum, 201 is over', () {
      expect(WeightedLength.status('가' * 200).postable, isTrue);
      final over = WeightedLength.status('가' * 201);
      expect(over.tooLong, isTrue);
      expect(over.remaining, -2);
      expect(over.progress, 1.0);
    });

    test('English is measured in the same units', () {
      expect(WeightedLength.status('a' * 79).tooShort, isTrue);
      expect(WeightedLength.status('a' * 400).postable, isTrue);
      expect(WeightedLength.status('a' * 401).tooLong, isTrue);
    });
  });

  test('tidies like the server: one blank line at most, no stray spaces', () {
    expect(WeightedLength.tidy('\n\n첫 줄   \r\n\n\n\n\n둘째 줄\t\n\n'), '첫 줄\n\n둘째 줄');
    expect(WeightedLength.tidy('한 줄\n다음 줄'), '한 줄\n다음 줄');
  });

  test('allows twelve lines, blank ones included', () {
    String lines(int n) => List.filled(n, '가나다라마바').join('\n');
    expect(WeightedLength.status(lines(12)).postable, isTrue);
    final over = WeightedLength.status(lines(13));
    expect(over.tooManyLines, isTrue);
    expect(over.postable, isFalse);
    // Blank lines beyond one are dropped before counting.
    expect(WeightedLength.status('${lines(6)}\n\n\n\n\n${lines(6)}').lines, 13);
  });
}
