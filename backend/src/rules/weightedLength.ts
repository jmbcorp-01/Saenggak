/**
 * Post length rules, kept identical to app/lib/core/weighted_length.dart.
 * Hangul, kana and Han characters count 2, everything else 1.
 */
export const MIN_UNITS = 80;
export const MAX_UNITS = 400;
/** Lines in a post, blank ones included, so one post never fills the screen. */
export const MAX_LINES = 12;

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

/**
 * The post as it is kept and shown: line endings made plain, spaces at line
 * ends and blank lines at the start and end dropped, and runs of blank lines
 * cut to one. Kept identical to WeightedLength.tidy in the app.
 */
export function tidyPost(text: string): string {
  return text
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((line) => line.replace(/[ \t\u3000]+$/, ''))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function lineCount(text: string): number {
  return text === '' ? 0 : text.split('\n').length;
}

export type LengthVerdict = 'ok' | 'too_short' | 'too_long' | 'too_many_lines';

/** Checks a tidied post. */
export function checkLength(text: string): LengthVerdict {
  const units = weightedLength(text);
  if (units < MIN_UNITS) return 'too_short';
  if (units > MAX_UNITS) return 'too_long';
  if (lineCount(text) > MAX_LINES) return 'too_many_lines';
  return 'ok';
}
