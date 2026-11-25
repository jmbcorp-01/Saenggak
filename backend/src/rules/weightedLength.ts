/**
 * Post length rules, kept identical to app/lib/core/weighted_length.dart.
 * Hangul, kana and Han characters count 2, everything else 1.
 */
export const MIN_UNITS = 80;
export const MAX_UNITS = 400;

const WIDE_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x1100, 0x11ff], // Hangul Jamo
  [0x3130, 0x318f], // Hangul Compatibility Jamo
  [0xa960, 0xa97f], // Hangul Jamo Extended-A
  [0xac00, 0xd7a3], // Hangul Syllables
  [0xd7b0, 0xd7ff], // Hangul Jamo Extended-B
  [0x3040, 0x309f], // Hiragana
  [0x30a0, 0x30ff], // Katakana
  [0x31f0, 0x31ff], // Katakana Phonetic Extensions
  [0x3400, 0x4dbf], // CJK Extension A
  [0x4e00, 0x9fff], // CJK Unified Ideographs
  [0xf900, 0xfaff], // CJK Compatibility Ideographs
  [0x20000, 0x2fa1f], // CJK Extensions B and later
];

export function isWide(codePoint: number): boolean {
  return WIDE_RANGES.some(([lo, hi]) => codePoint >= lo && codePoint <= hi);
}

export function weightedLength(text: string): number {
  let total = 0;
  for (const ch of text) total += isWide(ch.codePointAt(0)!) ? 2 : 1;
  return total;
}

export type LengthVerdict = 'ok' | 'too_short' | 'too_long';

export function checkLength(text: string): LengthVerdict {
  const units = weightedLength(text);
  if (units < MIN_UNITS) return 'too_short';
  if (units > MAX_UNITS) return 'too_long';
  return 'ok';
}
