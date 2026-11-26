/**
 * The thought score: how much a post looks thought through and typed by a
 * person, 0 to 100. Internal only. It orders the 추천 feed and feeds the
 * activity risk score; the writer never sees it.
 *
 * Half comes from how the post was typed (pauses, corrections, rhythm), half
 * from the text (whether it reads as machine-written, how personal and
 * specific it is, whether it repeats an existing post).
 */
import type { TypingSession } from './humanCheck.js';

/** A gap long enough to be a moment of thought, but not leaving the app. */
export const PAUSE_MIN_MS = 1_500;
export const PAUSE_MAX_MS = 30_000;
/** Pauses per 100 characters that count as fully reflective writing. */
const FULL_PAUSES_PER_100 = 4;
/** Share of typed characters later deleted that counts as fully revised. */
const FULL_REVISION = 0.08;

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));

/**
 * How the post was typed. A steady stream with no pause and no correction,
 * as when copying from another screen, scores low.
 */
export function processScore(session: TypingSession): number {
  const kb = session.events.filter((e) => e.s === 'keyboard');
  const typed = kb.reduce((n, e) => n + e.i, 0);
  // Mostly spoken: the typing record says little either way.
  if (typed < 10) return 50;

  let pauses = 0;
  const quick: number[] = [];
  for (let k = 1; k < kb.length; k++) {
    const gap = kb[k]!.t - kb[k - 1]!.t;
    if (gap >= PAUSE_MIN_MS && gap <= PAUSE_MAX_MS) pauses++;
    else if (gap < PAUSE_MIN_MS && kb[k]!.i > 0) quick.push(gap);
  }
  const pauseShare = clamp01((pauses / (typed / 100)) / FULL_PAUSES_PER_100);

  const deleted = kb.reduce((n, e) => n + e.d, 0);
  const revision = clamp01(deleted / typed / FULL_REVISION);

  let rhythm = 0;
  if (quick.length >= 5) {
    const mean = quick.reduce((a, b) => a + b, 0) / quick.length;
    const sd = Math.sqrt(quick.reduce((a, v) => a + (v - mean) ** 2, 0) / quick.length);
    rhythm = mean === 0 ? 0 : clamp01((sd / mean - 0.15) / 0.5);
  }

  return Math.round(100 * (0.4 * pauseShare + 0.3 * revision + 0.3 * rhythm));
}

/** What the content filter read in the text, each 0 to 10. */
export interface TextSignals {
  /** How much it reads as written by AI or copied from elsewhere. */
  machineLike: number;
  /** How personal, specific and reflective it is. */
  depth: number;
}

export interface ContentFacts {
  signals: TextSignals | null;
  /** Another person already posted nearly the same text. */
  nearDuplicate: boolean;
  /** Phrases this post was the first in the app to use. */
  firstPhrases: number;
}

export function contentScore(f: ContentFacts): number {
  let score = f.signals ? (10 - f.signals.machineLike) * 5 + f.signals.depth * 5 : 50;
  score += Math.min(2, f.firstPhrases) * 5;
  if (f.nearDuplicate) score = Math.min(score, 10);
  return Math.round(Math.min(100, Math.max(0, score)));
}

export function thoughtScore(process: number, content: number): number {
  return Math.round(0.5 * process + 0.5 * content);
}

/** Posts scoring below this look automated or copied. */
export const LOW_THOUGHT_SCORE = 25;

/** Cosine distance under which two posts are the same text in other words. */
export const NEAR_DUPLICATE_DISTANCE = 0.04;
