import { describe, expect, it } from 'vitest';
import { checkLength, lineCount, tidyPost, weightedLength } from '../src/rules/weightedLength.js';
import { activeDurationMs, evaluate, parseSession } from '../src/rules/humanCheck.js';
import { followUnlocked } from '../src/rules/follow.js';
import { cosineSimilarity, MAX_COSINE_DISTANCE, summarizeSimilar } from '../src/rules/similar.js';
import { humanSession } from './helpers.js';

describe('weighted length', () => {
  it('counts Hangul as 2 and Latin as 1', () => {
    expect(weightedLength('나는 I')).toBe(6);
  });
  it('accepts 40 to 200 Korean characters', () => {
    expect(checkLength('가'.repeat(39))).toBe('too_short');
    expect(checkLength('가'.repeat(40))).toBe('ok');
    expect(checkLength('가'.repeat(200))).toBe('ok');
    expect(checkLength('가'.repeat(201))).toBe('too_long');
  });
  it('keeps one blank line at most and drops stray spaces', () => {
    expect(tidyPost('\n\n첫 줄   \r\n\n\n\n\n둘째 줄\t\n\n')).toBe('첫 줄\n\n둘째 줄');
    expect(tidyPost('한 줄\n다음 줄')).toBe('한 줄\n다음 줄');
  });
  it('allows twelve lines, blank ones included', () => {
    const lines = (n: number) => Array.from({ length: n }, () => '가나다라마바').join('\n');
    expect(lineCount(lines(12))).toBe(12);
    expect(checkLength(lines(12))).toBe('ok');
    expect(checkLength(lines(13))).toBe('too_many_lines');
  });
});

describe('human check', () => {
  const text = 'I keep thinking about the quiet morning walks I took last spring.';

  it('passes uneven typing', () => {
    const s = parseSession(humanSession(text))!;
    expect(evaluate(s, [...text].length)).toEqual([]);
  });

  it('rejects malformed sessions', () => {
    expect(parseSession(null)).toBeNull();
    expect(parseSession({ events: [{ t: 5, i: 1, d: 0, s: 'keyboard' }, { t: 1, i: 1, d: 0, s: 'keyboard' }] })).toBeNull();
    expect(parseSession({ events: [{ t: 1, i: 1, d: 0, s: 'paste' }] })).toBeNull();
  });

  it('flags a pasted chunk, a mismatch, perfect rhythm and machine speed', () => {
    const chunk = parseSession({ events: [{ t: 0, i: 30, d: 0, s: 'keyboard' }] })!;
    expect(evaluate(chunk, 30)).toContain('invalid_session');
    expect(evaluate(parseSession(humanSession(text))!, 10)).toContain('text_mismatch');

    const regular = parseSession({
      events: [...text].map((_, k) => ({ t: k * 200, i: 1, d: 0, s: 'keyboard' })),
    })!;
    expect(evaluate(regular, [...text].length)).toContain('too_regular');

    const fast = parseSession({
      events: [...text].map((_, k) => ({ t: k * 20 + (k % 3) * 5, i: 1, d: 0, s: 'keyboard' })),
    })!;
    expect(evaluate(fast, [...text].length)).toContain('too_fast');
  });

  it('allows large voice chunks', () => {
    const s = parseSession({ events: [{ t: 0, i: 40, d: 0, s: 'voice' }] })!;
    expect(evaluate(s, 40)).toEqual([]);
  });

  it('does not count long pauses as typing time', () => {
    const events = [0, 200, 40_200, 40_500].map((t) => ({ t, i: 1, d: 0, s: 'keyboard' as const }));
    expect(activeDurationMs(events)).toBe(500);
  });
});

describe('follow permission', () => {
  it('unlocks at 10 writing days', () => {
    expect(followUnlocked({ writingDays: 9, recentBlocks: 0, daysSinceLoss: null })).toBe(false);
    expect(followUnlocked({ writingDays: 10, recentBlocks: 0, daysSinceLoss: null })).toBe(true);
  });
  it('is lost at 3 blocks and returns after 10 more days', () => {
    expect(followUnlocked({ writingDays: 40, recentBlocks: 3, daysSinceLoss: 0 })).toBe(false);
    expect(followUnlocked({ writingDays: 40, recentBlocks: 0, daysSinceLoss: 9 })).toBe(false);
    expect(followUnlocked({ writingDays: 40, recentBlocks: 0, daysSinceLoss: 10 })).toBe(true);
  });
});

describe('similar thoughts', () => {
  it('hides counts under 3 people', () => {
    expect(summarizeSimilar(2)).toEqual({ people: 2, show: false });
    expect(summarizeSimilar(3)).toEqual({ people: 3, show: true });
  });
  it('matches the pgvector distance', () => {
    expect(MAX_COSINE_DISTANCE).toBeCloseTo(0.18);
    expect(cosineSimilarity([1, 0], [1, 0])).toBe(1);
    expect(cosineSimilarity([1, 0], [0, 1])).toBe(0);
  });
});
