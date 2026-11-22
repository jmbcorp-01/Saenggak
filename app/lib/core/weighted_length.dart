/// Post length rules.
///
/// Length is counted in weighted units instead of words, because word counts
/// break down for Korean (spacing varies by writer) and for Chinese and
/// Japanese (no spaces at all). Hangul, Han characters and kana count as 2,
/// everything else counts as 1. A post must be between [minUnits] and
/// [maxUnits]: roughly 40 to 200 Korean characters, or 15 to 70 English words.
class WeightedLength {
  WeightedLength._();

  static const int minUnits = 80;
  static const int maxUnits = 400;

  /// Weighted length of [text].
  static int of(String text) {
    var total = 0;
    for (final rune in text.runes) {
      total += isWide(rune) ? 2 : 1;
    }
    return total;
  }

  /// Whether [rune] belongs to a script that counts double.
  static bool isWide(int rune) {
    return _inRange(rune, 0x1100, 0x11FF) || // Hangul Jamo
        _inRange(rune, 0x3130, 0x318F) || // Hangul Compatibility Jamo
        _inRange(rune, 0xA960, 0xA97F) || // Hangul Jamo Extended-A
        _inRange(rune, 0xAC00, 0xD7A3) || // Hangul Syllables
        _inRange(rune, 0xD7B0, 0xD7FF) || // Hangul Jamo Extended-B
        _inRange(rune, 0x3040, 0x309F) || // Hiragana
        _inRange(rune, 0x30A0, 0x30FF) || // Katakana
        _inRange(rune, 0x31F0, 0x31FF) || // Katakana Phonetic Extensions
        _inRange(rune, 0x3400, 0x4DBF) || // CJK Extension A
        _inRange(rune, 0x4E00, 0x9FFF) || // CJK Unified Ideographs
        _inRange(rune, 0xF900, 0xFAFF) || // CJK Compatibility Ideographs
        _inRange(rune, 0x20000, 0x2FA1F); // CJK Extensions B and later
  }

  static bool _inRange(int v, int lo, int hi) => v >= lo && v <= hi;

  /// How a post of [text] stands against the length rules.
  static LengthStatus status(String text) => LengthStatus(of(text));
}

/// The weighted length of a draft and what it means for posting.
class LengthStatus {
  const LengthStatus(this.units);

  final int units;

  bool get tooShort => units < WeightedLength.minUnits;
  bool get tooLong => units > WeightedLength.maxUnits;
  bool get postable => !tooShort && !tooLong;

  /// Fill of the length ring, from 0.0 to 1.0.
  double get progress => (units / WeightedLength.maxUnits).clamp(0.0, 1.0);

  /// Units left before the maximum. Negative when over.
  int get remaining => WeightedLength.maxUnits - units;
}
