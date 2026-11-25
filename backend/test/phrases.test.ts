import { describe, expect, it } from 'vitest';
import { extractPhrases, normalizeWord, pickFirstPhrases } from '../src/rules/phrases.js';

describe('phrases', () => {
  it('strips Korean particles', () => {
    expect(normalizeWord('생각을')).toBe('생각');
    expect(normalizeWord('생각이')).toBe('생각');
    expect(normalizeWord('학교에서도')).toBe('학교');
    expect(normalizeWord('Morning,')).toBe('morning,');
  });

  it('matches the same phrase with different particles', () => {
    const a = extractPhrases('오늘 아침의 생각을 적는다').map((p) => p.key);
    const b = extractPhrases('오늘 아침에 생각이 났다').map((p) => p.key);
    expect(a).toContain('오늘 아침');
    expect(b).toContain('오늘 아침');
  });

  it('keeps the typed words for display and skips filler', () => {
    const phrases = extractPhrases('The quiet morning is mine.');
    expect(phrases.map((p) => p.text)).toContain('quiet morning');
    expect(phrases.map((p) => p.key)).not.toContain('the quiet');
    expect(phrases.map((p) => p.key)).not.toContain('is mine');
  });

  it('never crosses a sentence end', () => {
    const keys = extractPhrases('비가 왔다. 마음이 편했다').map((p) => p.key);
    expect(keys).not.toContain('왔다 마음');
  });

  it('shows at most 3, longest first, without repeats inside longer ones', () => {
    const shown = pickFirstPhrases([
      { key: 'quiet morning', text: 'quiet morning', n: 2 },
      { key: 'quiet morning walks', text: 'quiet morning walks', n: 3 },
      { key: 'spring rain', text: 'spring rain', n: 2 },
      { key: 'old letters', text: 'old letters', n: 2 },
      { key: 'blue door', text: 'blue door', n: 2 },
    ]);
    expect(shown.map((p) => p.key)).toEqual(['quiet morning walks', 'spring rain', 'old letters']);
  });
});
