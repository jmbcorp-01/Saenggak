/**
 * "처음 쓴 표현": finds the two- and three-word phrases in a post, normalized so
 * that the same expression matches across posts. Korean particles are removed
 * from the end of each word ("생각을" and "생각이" both become "생각").
 */

// Longest first, so "에서도" is removed before "도".
const KOREAN_PARTICLES = [
  '에서부터', '으로부터', '에서도', '으로도', '이라도', '에게서', '한테서',
  '에서', '에게', '한테', '으로', '로도', '까지', '부터', '보다', '처럼', '마저',
  '조차', '이나', '이랑', '하고', '에도', '와', '과', '은', '는', '이', '가',
  '을', '를', '에', '께', '로', '의', '도', '만', '랑', '나',
].sort((a, b) => b.length - a.length);

const ENGLISH_STOPWORDS = new Set([
  'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for',
  'with', 'is', 'am', 'are', 'was', 'were', 'be', 'it', 'i', 'you', 'we',
  'they', 'he', 'she', 'my', 'your', 'our', 'that', 'this', 'so', 'as', 'not',
]);

const HANGUL = /^[가-힣]+$/;

export interface Phrase {
  /** Normalized key stored in the first-use table. */
  key: string;
  /** The words as the writer typed them, for display. */
  text: string;
  /** Number of words. */
  n: 2 | 3;
}

interface Token {
  raw: string;
  norm: string;
}

export function normalizeWord(word: string): string {
  const w = word.normalize('NFC').toLowerCase();
  if (!HANGUL.test(w)) return w;
  for (const p of KOREAN_PARTICLES) {
    if (w.length > p.length && w.endsWith(p)) return w.slice(0, -p.length);
  }
  return w;
}

export function tokenize(text: string): Token[] {
  return text
    .split(/\s+/)
    .map((raw) => raw.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ''))
    .filter((raw) => raw.length > 0)
    .map((raw) => ({ raw, norm: normalizeWord(raw) }));
}

function isFiller(t: Token): boolean {
  return ENGLISH_STOPWORDS.has(t.norm) || t.norm.length === 0;
}

/** Every distinct 2- and 3-word phrase in [text] that is not all filler. */
export function extractPhrases(text: string): Phrase[] {
  // Phrases never cross a sentence end.
  const sentences = text.split(/[.!?。！？\n]+/);
  const seen = new Set<string>();
  const out: Phrase[] = [];
  for (const sentence of sentences) {
    const tokens = tokenize(sentence);
    for (const n of [3, 2] as const) {
      for (let k = 0; k + n <= tokens.length; k++) {
        const slice = tokens.slice(k, k + n);
        if (slice.every(isFiller)) continue;
        if (slice.filter((t) => !isFiller(t)).length < 2) continue;
        const key = slice.map((t) => t.norm).join(' ');
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ key, text: slice.map((t) => t.raw).join(' '), n });
      }
    }
  }
  return out;
}

export const MAX_FIRST_PHRASES_SHOWN = 3;

/**
 * Chooses which first-used phrases to show: longer phrases first, and a
 * two-word phrase is skipped when a shown three-word phrase contains it.
 */
export function pickFirstPhrases(firsts: Phrase[]): Phrase[] {
  const sorted = [...firsts].sort((a, b) => b.n - a.n);
  const shown: Phrase[] = [];
  for (const p of sorted) {
    if (shown.length >= MAX_FIRST_PHRASES_SHOWN) break;
    if (shown.some((s) => ` ${s.key} `.includes(` ${p.key} `))) continue;
    shown.push(p);
  }
  return shown;
}
