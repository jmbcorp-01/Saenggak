import { describe, expect, it } from 'vitest';
import { contentScore, processScore, thoughtScore } from '../src/rules/thoughtScore.js';
import { needsHumanCheck, riskScore, type Activity } from '../src/rules/risk.js';
import type { TypingEvent } from '../src/rules/humanCheck.js';

const session = (events: TypingEvent[]) => ({ events, rejectedPastes: 0, activeMs: 0 });

/** Types [n] characters at a fixed gap, as when copying text from another screen. */
function steady(n: number, gap = 150): TypingEvent[] {
  return Array.from({ length: n }, (_, k) => ({ t: k * gap, i: 1, d: 0, s: 'keyboard' as const }));
}

/** Uneven typing with a pause before every sentence and a few corrections. */
function reflective(n: number): TypingEvent[] {
  const events: TypingEvent[] = [];
  let t = 0;
  let seed = 3;
  for (let k = 0; k < n; k++) {
    seed = (seed * 9301 + 49297) % 233280;
    t += k % 25 === 0 ? 4_000 : 90 + Math.floor((seed / 233280) * 400);
    events.push({ t, i: 1, d: 0, s: 'keyboard' });
    if (k % 30 === 10) events.push({ t: (t += 300), i: 0, d: 2, s: 'keyboard' });
  }
  return events;
}

describe('thought score', () => {
  it('scores reflective typing well above steady copying', () => {
    const copied = processScore(session(steady(120)));
    const thought = processScore(session(reflective(120)));
    expect(copied).toBeLessThan(20);
    expect(thought).toBeGreaterThan(60);
  });

  it('gives a spoken post a neutral typing score', () => {
    expect(processScore(session([{ t: 0, i: 80, d: 0, s: 'voice' }]))).toBe(50);
  });

  it('reads the text signals, rewards new phrases and caps near-duplicates', () => {
    expect(contentScore({ signals: { machineLike: 0, depth: 10 }, nearDuplicate: false, firstPhrases: 0 })).toBe(100);
    expect(contentScore({ signals: { machineLike: 10, depth: 0 }, nearDuplicate: false, firstPhrases: 0 })).toBe(0);
    expect(contentScore({ signals: null, nearDuplicate: false, firstPhrases: 1 })).toBe(55);
    expect(contentScore({ signals: { machineLike: 0, depth: 10 }, nearDuplicate: true, firstPhrases: 2 })).toBe(10);
    expect(thoughtScore(80, 40)).toBe(60);
  });
});

describe('activity risk', () => {
  const calm: Activity = { last10m: {}, lastHour: {}, accountAgeHours: 200, lowScorePosts: 0, hoursSinceCheck: null };

  it('leaves ordinary activity alone', () => {
    expect(riskScore({ ...calm, last10m: { empathy: 12, follow: 3 }, lastHour: { empathy: 40 } })).toBe(0);
    expect(needsHumanCheck(calm)).toBe(false);
  });

  it('asks for a check after bursts no reader would make', () => {
    const burst = { ...calm, last10m: { empathy: 50 }, lastHour: { empathy: 150 } };
    expect(riskScore(burst)).toBe(70);
    expect(needsHumanCheck(burst)).toBe(true);
    // A check passed within a day lets the person go on.
    expect(needsHumanCheck({ ...burst, hoursSinceCheck: 2 })).toBe(false);
    expect(needsHumanCheck({ ...burst, hoursSinceCheck: 30 })).toBe(true);
  });

  it('asks when posts keep looking copied, and sooner after failed checks', () => {
    expect(needsHumanCheck({ ...calm, lowScorePosts: 2 })).toBe(false);
    expect(needsHumanCheck({ ...calm, lowScorePosts: 3 })).toBe(true);
    // One failed check alone is not enough; a burst plus failures is.
    expect(needsHumanCheck({ ...calm, lastHour: { check_failed: 1 } })).toBe(false);
    expect(needsHumanCheck({ ...calm, last10m: { follow: 25 }, lastHour: { check_failed: 2 } })).toBe(true);
  });
});
